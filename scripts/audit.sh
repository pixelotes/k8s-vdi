#!/usr/bin/env bash
# Prints the portal audit trail (login, logout, desktop_start, desktop_stop).
source "$(dirname "$0")/lib.sh"
k -n vdi exec deploy/hub -- cat /srv/jupyterhub/audit.jsonl 2>/dev/null || echo "(no events yet)"
