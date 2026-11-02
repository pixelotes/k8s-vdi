#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
echo
echo "Portal:          https://vdi.orb.local"
echo "Keycloak admin:  https://keycloak.vdi.orb.local/admin   admin / $(secret keycloak-admin)"
echo "Account console: https://keycloak.vdi.orb.local/realms/vdi/account"
echo "Users:"
grep -v '^#' "$ROOT/keycloak/users.txt" | while read -r u _; do
  [[ -n "$u" ]] && printf '  %-8s %s\n' "$u" "$(secret "user-$u")"
done
