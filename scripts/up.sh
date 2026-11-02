#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
for s in "$ROOT"/scripts/[0-9][0-9]-*.sh; do bash "$s"; done
"$ROOT/scripts/info.sh"
