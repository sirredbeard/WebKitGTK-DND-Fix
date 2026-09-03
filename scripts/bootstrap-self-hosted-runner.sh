#!/usr/bin/env bash
# Bootstrap a Fedora host as a GitHub Actions self-hosted runner for WebKitGTK-DND-Fix.
# Run as root. Env:
#   RUNNER_NAME   required unique name (e.g. azure-d16ds-webkit-dnd)
#   RUNNER_LABELS default: self-hosted,linux,x64,webkit-dnd,fedora-44
#   RUNNER_TOKEN  registration token (repo admin) OR GH_TOKEN with admin:repo_hook / admin
#   REPO          default sirredbeard/WebKitGTK-DND-Fix
#   EXTRA_LABELS  optional comma list appended (e.g. azure)
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "run as root" >&2
  exit 1
fi

REPO="${REPO:-sirredbeard/WebKitGTK-DND-Fix}"
RUNNER_NAME="${RUNNER_NAME:?set RUNNER_NAME}"
EXTRA_LABELS="${EXTRA_LABELS:-}"
BASE_LABELS="self-hosted,linux,x64,webkit-dnd,fedora-44"
if [[ -n "$EXTRA_LABELS" ]]; then
  RUNNER_LABELS="${BASE_LABELS},${EXTRA_LABELS}"
else
  RUNNER_LABELS="${RUNNER_LABELS:-$BASE_LABELS}"
fi
RUNNER_VERSION="${RUNNER_VERSION:-2.336.0}"
RUNNER_USER="${RUNNER_USER:-gha}"
RUNNER_HOME="/opt/actions-runner"
CACHE=/var/cache/webkit-dnd

echo "== packages =="
dnf -y upgrade --refresh
dnf -y install --setopt=install_weak_deps=False \
  curl tar gzip jq git git-core rsync zstd pigz ca-certificates \
  tuned ccache mold lld ninja-build cmake \
  dnf-plugins-core

# Docker CE
if ! command -v docker >/dev/null; then
  dnf -y install dnf-plugins-core
  dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo 2>/dev/null \
    || dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
  dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
systemctl enable --now docker

id -u "$RUNNER_USER" >/dev/null 2>&1 || useradd -r -m -s /bin/bash "$RUNNER_USER"
usermod -aG docker "$RUNNER_USER"

mkdir -p "$CACHE"/{ccache,build-gtk,prefix,out,buildx-cache,images,tools,mirrors,dnf,pip,git-partial}
chown -R "${RUNNER_USER}:${RUNNER_USER}" "$CACHE"
chmod 755 /var/cache/webkit-dnd

# host tune if present next to this script or already on disk
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [[ -x "${SCRIPT_DIR}/host-tune-fedora-runner.sh" ]]; then
  bash "${SCRIPT_DIR}/host-tune-fedora-runner.sh" || true
elif [[ -x /opt/webkit-dnd/host-tune-fedora-runner.sh ]]; then
  bash /opt/webkit-dnd/host-tune-fedora-runner.sh || true
fi

echo "== actions runner ${RUNNER_VERSION} =="
mkdir -p "$RUNNER_HOME"
cd "$RUNNER_HOME"
if [[ ! -f ./config.sh ]]; then
  curl -fsSL -o actions-runner-linux-x64.tar.gz \
    "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
  tar xzf actions-runner-linux-x64.tar.gz
  rm -f actions-runner-linux-x64.tar.gz
fi
chown -R "${RUNNER_USER}:${RUNNER_USER}" "$RUNNER_HOME"

if [[ -z "${RUNNER_TOKEN:-}" ]]; then
  if [[ -n "${GH_TOKEN:-}" ]] && command -v gh >/dev/null; then
    RUNNER_TOKEN=$(gh api -X POST "repos/${REPO}/actions/runners/registration-token" --jq .token)
  else
    echo "set RUNNER_TOKEN or GH_TOKEN" >&2
    exit 1
  fi
fi

# remove prior config if re-bootstrap
if [[ -f .runner ]]; then
  sudo -u "$RUNNER_USER" ./config.sh remove --token "$RUNNER_TOKEN" || true
fi

sudo -u "$RUNNER_USER" ./config.sh \
  --url "https://github.com/${REPO}" \
  --token "$RUNNER_TOKEN" \
  --name "$RUNNER_NAME" \
  --labels "$RUNNER_LABELS" \
  --work _work \
  --unattended \
  --replace

./svc.sh install "$RUNNER_USER"
./svc.sh start
./svc.sh status || true

echo "== runner online name=${RUNNER_NAME} labels=${RUNNER_LABELS} =="
