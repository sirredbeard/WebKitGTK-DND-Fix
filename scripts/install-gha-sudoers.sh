#!/usr/bin/env bash
# Passwordless sudo for Actions runner user on self-hosted webkit-dnd hosts.
# Root-owned __pycache__ from containers and install of /usr/local/sbin scripts need this.
set -euo pipefail
USER_NAME="${GHA_USER:-gha}"
FILE=/etc/sudoers.d/90-webkit-dnd-gha
if ! id "$USER_NAME" >/dev/null 2>&1; then
  echo "user $USER_NAME missing" >&2
  exit 1
fi
cat >"$FILE" <<SUDO
# WebKitGTK-DND-Fix self-hosted runner — managed by install-gha-sudoers.sh
Defaults:${USER_NAME} !requiretty
Defaults:${USER_NAME} env_keep += "CCACHE_DIR CCACHE_MAXSIZE PATH WEBKIT_DND_CACHE SYNC_MODE WARM_TIMEOUT_SEC WARM_PREFIX WARM_MIRRORS WARM_IMAGES LIVE_SYNC_INTERVAL_SEC DOCKER_ON_EPHEMERAL AUTO_DOCKER_EPHEMERAL_HOURS"
${USER_NAME} ALL=(root) NOPASSWD:ALL
SUDO
chmod 440 "$FILE"
visudo -cf "$FILE"
echo "installed $FILE for $USER_NAME"
if getent group docker >/dev/null; then
  usermod -aG docker "$USER_NAME" 2>/dev/null || true
fi
mkdir -p /var/cache/webkit-dnd/out
touch /var/log/webkit-dnd-cache-sync.log 2>/dev/null || true
chown -R "${USER_NAME}:docker" /var/cache/webkit-dnd 2>/dev/null || chown -R "${USER_NAME}:${USER_NAME}" /var/cache/webkit-dnd
if [[ -d /opt/actions-runner/_work ]]; then
  chown -R "${USER_NAME}:${USER_NAME}" /opt/actions-runner/_work || true
fi
