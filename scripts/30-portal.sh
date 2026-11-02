#!/usr/bin/env bash
# Desktop image + k8svdi chart (JupyterHub) at https://vdi.orb.local, login via Keycloak.
source "$(dirname "$0")/lib.sh"
require helm docker kind

log "Building desktop image"
docker build -q -t vdi-desktop:dev "$ROOT/images/desktop" >/dev/null
kind load docker-image vdi-desktop:dev --name "$CLUSTER" >/dev/null

log "Deploying k8svdi chart"
chart="$ROOT/deploy/helm/k8svdi"
helm dependency build "$chart" >/dev/null
helm --kube-context "$KCTX" upgrade --install vdi "$chart" \
  --namespace vdi --create-namespace \
  -f "$ROOT/deploy/values/lab-keycloak.yaml" \
  --set-string auth.clientSecret="$(secret jupyterhub-client)" \
  --wait --timeout 10m >/dev/null
k -n vdi rollout status deploy/hub --timeout=300s >/dev/null  # restarted by the chart hook

log "Waiting for https://vdi.orb.local"
for _ in $(seq 60); do
  curl -sf -o /dev/null https://vdi.orb.local/hub/health && exit 0
  sleep 2
done
echo "Portal not reachable through OrbStack" >&2; exit 1
