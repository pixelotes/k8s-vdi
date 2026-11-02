# Shared helpers. Sourced by the other scripts.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER=vdi
SECRETS="$ROOT/.secrets"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
KCTX="kind-$CLUSTER"
k() { kubectl --context "$KCTX" "$@"; }
log() { printf '\033[1;34m==> %s\033[0m\n' "$*"; }

# Returns a persisted random secret (created on first use) so re-runs are stable.
secret() {
  local f="$SECRETS/$1"
  mkdir -p "$SECRETS"; chmod 700 "$SECRETS"
  [[ -s "$f" ]] || { LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24 >"$f"; chmod 600 "$f"; }
  cat "$f"
}

require() {
  local missing=()
  for b in "$@"; do command -v "$b" >/dev/null || missing+=("$b"); done
  if ((${#missing[@]})); then
    command -v brew >/dev/null || { echo "Missing: ${missing[*]} (install them)"; exit 1; }
    log "Installing ${missing[*]} with Homebrew"; brew install "${missing[@]}"
  fi
}
