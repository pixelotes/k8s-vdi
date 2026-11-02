#!/usr/bin/env bash
# Destroys the cluster and gateway. Keeps .secrets/ (delete it for fresh passwords).
source "$(dirname "$0")/lib.sh"
docker rm -f vdi-gw >/dev/null 2>&1 || true
kind delete cluster --name "$CLUSTER"
