#!/usr/bin/env bash
# Keycloak with realm "vdi", OIDC client "jupyterhub" and users from keycloak/users.txt.
source "$(dirname "$0")/lib.sh"

admin_pw=$(secret keycloak-admin)
client_secret=$(secret jupyterhub-client)

users_json=""
while read -r user first last groups; do
  [[ -z "$user" || "$user" == \#* ]] && continue
  pw=$(secret "user-$user")
  users_json+="${users_json:+,
}    {\"username\": \"$user\", \"enabled\": true, \"emailVerified\": true,
     \"email\": \"$user@vdi.orb.local\", \"firstName\": \"$first\", \"lastName\": \"$last\",
     \"groups\": [\"${groups//,/\", \"}\"],
     \"credentials\": [{\"type\": \"password\", \"value\": \"$pw\", \"temporary\": false}]}"
done <"$ROOT/keycloak/users.txt"

realm=$(<"$ROOT/keycloak/realm-vdi.json.tpl")
realm=${realm//'${JUPYTERHUB_CLIENT_SECRET}'/$client_secret}
realm=${realm//'${USERS_JSON}'/$users_json}

log "Deploying Keycloak"
k apply -f "$ROOT/keycloak/keycloak.yaml" >/dev/null
k -n keycloak create secret generic keycloak-admin \
  --from-literal=username=admin --from-literal=password="$admin_pw" \
  --dry-run=client -o yaml | k apply -f - >/dev/null
k -n keycloak create secret generic keycloak-realm \
  --from-literal=vdi-realm.json="$realm" --dry-run=client -o yaml | k apply -f - >/dev/null

# The realm is imported at startup (dev mode, in-memory DB): roll pods only when it changes.
sum=$(printf '%s' "$realm" | shasum -a 256 | cut -c1-16)
k -n keycloak patch deploy/keycloak --type merge \
  -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"vdi/realm-sha\":\"$sum\"}}}}}" >/dev/null
k -n keycloak rollout status deploy/keycloak --timeout=300s

log "Waiting for https://keycloak.vdi.orb.local"
for _ in $(seq 60); do
  curl -sf -o /dev/null https://keycloak.vdi.orb.local/realms/vdi/.well-known/openid-configuration && exit 0
  sleep 2
done
echo "Keycloak not reachable through OrbStack" >&2; exit 1
