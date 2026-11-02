#!/usr/bin/env bash
# End-to-end check: login as a user, desktop pod spawns, noVNC answers, logout deletes the pod.
source "$(dirname "$0")/lib.sh"
user=${1:-bob}; pw=$(secret "user-$user"); pod="jupyter-$user"
jar=$(mktemp); trap 'rm -f "$jar"' EXIT
c() { curl -s -c "$jar" -b "$jar" "$@"; }

login() {
  : >"$jar"
  local form
  form=$(c -L https://vdi.orb.local/hub/login | grep -o 'action="[^"]*"' | head -1 | sed 's/action="//;s/"$//;s/&amp;/\&/g')
  [[ -n "$form" ]] || { echo "Keycloak login form not found"; exit 1; }
  c -L -o /dev/null --data-urlencode "username=$user" --data-urlencode "password=$pw" "$form"
  for _ in $(seq 30); do k -n vdi get "pod/$pod" >/dev/null 2>&1 && break; sleep 2; done
}

log "Login as $user"
login
log "Waiting for pod $pod"
k -n vdi wait --for=condition=ready "pod/$pod" --timeout=300s >/dev/null
code=$(c -L -o /dev/null -w '%{http_code}' "https://vdi.orb.local/user/$user/desktop/")
echo "desktop page: HTTP $code"; [[ "$code" == 200 ]] || exit 1
for _ in $(seq 10); do
  c -L -o /dev/null "https://vdi.orb.local/user/$user/desktop/"
  ws=$(c -o /dev/null -m 5 -w '%{http_code}' --http1.1 -H 'Connection: Upgrade' -H 'Upgrade: websocket' \
  -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
  "https://vdi.orb.local/user/$user/desktop-websockify/" || true)
  [[ "$ws" == 101 ]] && break; sleep 3
done
echo "websocket upgrade: HTTP $ws"; [[ "$ws" == 101 ]] || exit 1

k -n vdi wait --for=condition=ready "pod/$pod" --timeout=300s >/dev/null

log "Browser and persistent home"
k -n vdi exec "$pod" -c notebook -- sh -c 'command -v epiphany && echo "$(date +%s)" > ~/.vdi-e2e' >/dev/null
marker=$(k -n vdi exec "$pod" -c notebook -- cat /home/jovyan/.vdi-e2e)
echo "epiphany installed, wrote marker $marker"

log "Logout"
c -L -o /dev/null https://vdi.orb.local/hub/logout
k -n vdi wait --for=delete "pod/$pod" --timeout=120s >/dev/null && echo "pod $pod deleted"
log "Login again (new desktop)"
login
k -n vdi wait --for=condition=ready "pod/$pod" --timeout=300s >/dev/null
[[ "$(k -n vdi exec "$pod" -c notebook -- cat /home/jovyan/.vdi-e2e)" == "$marker" ]] \
  && echo "home persisted across desktops" || { echo "home NOT persisted"; exit 1; }

log "Desktop shutdown (same as the 'Apagar escritorio' launcher)"
k -n vdi exec "$pod" -- /usr/local/bin/vdi-shutdown || true  # pod dies under us
k -n vdi wait --for=delete "pod/$pod" --timeout=120s >/dev/null && echo "pod $pod deleted"

log "Audit trail"
"$ROOT/scripts/audit.sh" | tail -6
log "OK"
