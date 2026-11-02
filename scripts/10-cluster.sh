#!/usr/bin/env bash
# kind cluster + ingress-nginx + OrbStack gateway (https://*.vdi.orb.local).
source "$(dirname "$0")/lib.sh"
require kind kubectl docker

if ! kind get clusters | grep -qx "$CLUSTER"; then
  log "Creating kind cluster $CLUSTER"
  kind create cluster --config "$ROOT/kind/cluster.yaml"
fi

log "Installing ingress-nginx"
k apply -f "$ROOT/ingress/deploy.yaml" >/dev/null
k -n ingress-nginx patch configmap ingress-nginx-controller --type merge -p \
  '{"data":{"use-forwarded-headers":"true","proxy-read-timeout":"3600","proxy-send-timeout":"3600","proxy-buffer-size":"16k"}}' >/dev/null
k -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=300s

# OrbStack only auto-routes HTTPS to a container's exposed port and kind nodes can't
# carry custom labels, so a tiny TCP forwarder owns the *.vdi.orb.local domains.
if ! docker inspect vdi-gw >/dev/null 2>&1; then
  log "Starting OrbStack gateway vdi-gw"
  docker run -d --name vdi-gw --network kind --restart unless-stopped \
    --label dev.orbstack.domains='vdi.orb.local,*.vdi.orb.local' \
    --label dev.orbstack.http-port=80 \
    alpine/socat:1.8.0.3 tcp-listen:80,fork,reuseaddr "tcp:$CLUSTER-control-plane:80" >/dev/null
fi
