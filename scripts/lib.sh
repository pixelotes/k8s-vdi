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

# Installs missing tools with Homebrew when possible; otherwise fails with a clear message.
require() {
  local missing=()
  for b in "$@"; do command -v "$b" >/dev/null || missing+=("$b"); done
  ((${#missing[@]})) || return 0
  if command -v brew >/dev/null; then
    log "Installing ${missing[*]} with Homebrew"
    brew install "${missing[@]}" || die "Homebrew could not install: ${missing[*]}"
    for b in "${missing[@]}"; do
      command -v "$b" >/dev/null || die "$b was installed but is not in PATH (open a new shell?)"
    done
  else
    die "Missing tools: ${missing[*]}. Install them (https://kind.sigs.k8s.io, https://helm.sh) and retry."
  fi
}

die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# Checks everything the lab needs before touching anything.
preflight() {
  log "Checking prerequisites"
  [[ $EUID -ne 0 ]] || die "Do not run with sudo: kind, Docker and Homebrew must run as your user."
  for b in docker kubectl curl shasum; do
    command -v "$b" >/dev/null || die "$b not found. Install OrbStack (it provides docker and kubectl): https://orbstack.dev"
  done
  docker info >/dev/null 2>&1 || die "Docker is not responding. Start OrbStack and retry."
  require kind helm
}

# Registers the JupyterHub chart repository (needed by 'helm dependency build').
helm_repos() {
  helm repo add jupyterhub https://hub.jupyter.org/helm-chart/ --force-update >/dev/null
  helm repo update jupyterhub >/dev/null
}
