#!/usr/bin/env bash
# Host performance + cache layout for WebKitGTK DnD self-hosted runner.
# Safe to re-run. Does not stop a running ninja/docker build.
set -euo pipefail

CACHE=/var/cache/webkit-dnd
MIRRORS="${CACHE}/mirrors"
TOOLS="${CACHE}/tools"
IMAGES="${CACHE}/images"

mkdir -p \
  "${CACHE}"/{ccache,build-gtk,prefix,out,buildx-cache,images,tools,mirrors,dnf,pip,git-partial} \
  /etc/systemd/system/actions.runner.sirredbeard-WebKitGTK-DND-Fix.vultr-voc-c-16c-webkit-dnd.service.d

echo "+ packages: tuned, performance tools, git extras"
dnf -y install --setopt=install_weak_deps=False \
  tuned tuned-profiles-cpu-partitioning \
  git git-core rsync zstd pigz jq curl ca-certificates \
  ccache mold lld ninja-build cmake \
  2>&1 | tail -15 || true

# throughput-performance is the right tuned profile for multi-core compile
if command -v tuned-adm >/dev/null; then
  systemctl enable --now tuned 2>/dev/null || true
  tuned-adm profile throughput-performance 2>/dev/null || tuned-adm profile latency-performance 2>/dev/null || true
  tuned-adm active || true
fi

echo "+ sysctl compile-friendly"
cat > /etc/sysctl.d/99-webkit-dnd-perf.conf << 'SYS'
# Prefer RAM for compile working set; still allow swap under pressure
vm.swappiness = 5
vm.vfs_cache_pressure = 50
# Steady writeback during mass object writes (less latency spikes)
vm.dirty_ratio = 20
vm.dirty_background_ratio = 5
vm.dirty_expire_centisecs = 3000
# Many files in WebKit trees
fs.file-max = 2097152
fs.inotify.max_user_watches = 1048576
fs.inotify.max_user_instances = 1024
# Slightly fairer multi-job compile scheduling (avoid autogroup skew)
kernel.sched_autogroup_enabled = 0
# Network: faster large git/ghcr pulls
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.core.netdev_max_backlog = 5000
SYS
sysctl --system >/dev/null 2>&1 || sysctl -p /etc/sysctl.d/99-webkit-dnd-perf.conf || true

echo "+ transparent hugepages madvise"
if [[ -w /sys/kernel/mm/transparent_hugepage/enabled ]]; then
  echo madvise > /sys/kernel/mm/transparent_hugepage/enabled || true
  echo madvise > /sys/kernel/mm/transparent_hugepage/defrag || true
fi
# persist via tmpfiles/rc
cat > /etc/tmpfiles.d/webkit-dnd-thp.conf << 'T'
w /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise
w /sys/kernel/mm/transparent_hugepage/defrag - - - - madvise
T

echo "+ block I/O scheduler none (NVMe/virtio)"
for q in /sys/block/*/queue/scheduler; do
  dev=$(echo "$q" | cut -d/ -f4)
  # skip ram/loop
  [[ "$dev" =~ ^(loop|ram|sr) ]] && continue
  if grep -qw none "$q" 2>/dev/null; then
    echo none > "$q" || true
  elif grep -qw none "${q}" 2>/dev/null; then
    echo none > "$q" || true
  fi
  echo "  $dev: $(cat "$q" 2>/dev/null || true)"
done
# udev rule persist
cat > /etc/udev/rules.d/60-webkit-dnd-io.rules << 'U'
ACTION=="add|change", KERNEL=="vd*|nvme*|sd*", ATTR{queue/scheduler}="none"
U
udevadm control --reload 2>/dev/null || true

echo "+ limits for gha / root compile"
cat > /etc/security/limits.d/99-webkit-dnd.conf << 'L'
gha soft nofile 1048576
gha hard nofile 1048576
gha soft nproc unlimited
gha hard nproc unlimited
root soft nofile 1048576
root hard nofile 1048576
L

echo "+ docker daemon tuned"
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'D'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "20m", "max-file": "3" },
  "live-restore": true,
  "storage-driver": "overlay2",
  "max-concurrent-downloads": 10,
  "max-concurrent-uploads": 5,
  "default-ulimits": {
    "nofile": { "Name": "nofile", "Hard": 1048576, "Soft": 1048576 }
  }
}
D
# Do not restart docker if build container is running
if docker ps --format '{{.Names}}' | grep -q webkitgtk-dnd-build; then
  echo "  docker build running; defer dockerd restart"
else
  systemctl reload docker 2>/dev/null || systemctl restart docker
fi

echo "+ git global performance (gha + root)"
for home in /root /home/gha; do
  [[ -d "$home" ]] || continue
  git config --file "$home/.gitconfig" core.preloadIndex true
  git config --file "$home/.gitconfig" core.fscache true
  git config --file "$home/.gitconfig" core.untrackedCache true
  git config --file "$home/.gitconfig" feature.manyFiles true
  git config --file "$home/.gitconfig" fetch.parallel 8
  git config --file "$home/.gitconfig" pack.threads 0
  git config --file "$home/.gitconfig" index.threads 0
  git config --file "$home/.gitconfig" gc.auto 0
  chown gha:gha "$home/.gitconfig" 2>/dev/null || true
done

echo "+ runner service drop-in (env + limits)"
cat > /etc/systemd/system/actions.runner.sirredbeard-WebKitGTK-DND-Fix.vultr-voc-c-16c-webkit-dnd.service.d/override.conf << 'S'
[Service]
LimitNOFILE=1048576
LimitNPROC=infinity
TasksMax=infinity
OOMScoreAdjust=-500
Environment=ACTIONS_RUNNER_HOOK_JOB_STARTED=/opt/actions-runner/hooks/job-started.sh
Environment=ACTIONS_RUNNER_HOOK_JOB_COMPLETED=/opt/actions-runner/hooks/job-completed.sh
Environment=CCACHE_DIR=/var/cache/webkit-dnd/ccache
Environment=CCACHE_MAXSIZE=40G
Environment=GIT_MIRROR_ROOT=/var/cache/webkit-dnd/mirrors
Environment=WEBKIT_DND_CACHE=/var/cache/webkit-dnd
# Prefer local tools
Environment=PATH=/usr/lib64/ccache:/usr/lib/ccache:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin
S

mkdir -p /opt/actions-runner/hooks
cat > /opt/actions-runner/hooks/job-started.sh << 'H'
#!/usr/bin/env bash
set -euo pipefail
CACHE=/var/cache/webkit-dnd
mkdir -p "$CACHE"/{ccache,build-gtk,prefix,out,buildx-cache,mirrors,tools,images}
# Ensure gha can write even if root touched paths
chmod -R g+rwX "$CACHE" 2>/dev/null || true
# Drop page cache only if idle memory pressure extreme - skip during builds
echo "job-started cache ok nproc=$(nproc)" || true
H
cat > /opt/actions-runner/hooks/job-completed.sh << 'H'
#!/usr/bin/env bash
set -euo pipefail
# Keep ccache and mirrors forever. Only prune dangling docker images older cruft lightly.
docker image prune -f >/dev/null 2>&1 || true
# ccache stats snapshot
CCACHE_DIR=/var/cache/webkit-dnd/ccache ccache -s > /var/cache/webkit-dnd/out/ccache-host-last.txt 2>/dev/null || true
echo "job-completed" || true
H
chmod 755 /opt/actions-runner/hooks/*.sh
chown -R gha:gha /opt/actions-runner/hooks

# Restart runner service only (not docker) to pick up drop-in - may briefly disconnect
systemctl daemon-reload
if docker ps --format '{{.Names}}' | grep -q webkitgtk-dnd; then
  echo "  active build container; runner override applied on next runner restart"
  # Still try runner restart - job worker already running in child; risky
  # Do NOT restart runner mid-job
else
  systemctl restart actions.runner.sirredbeard-WebKitGTK-DND-Fix.vultr-voc-c-16c-webkit-dnd.service
fi

echo "+ ownership"
chown -R gha:docker "${CACHE}"
chmod -R 775 "${CACHE}"

echo "+ pre-seed host packages used outside containers (mirror tools)"
dnf -y install --setopt=install_weak_deps=False \
  libicu tar gzip which findutils procps-ng shadow-utils \
  python3 fuse fuse-libs squashfs-tools desktop-file-utils \
  2>&1 | tail -8 || true

echo HOST_TUNE_OK
tuned-adm active 2>/dev/null || true
sysctl vm.swappiness kernel.sched_autogroup_enabled fs.inotify.max_user_watches | cat
cat /sys/block/vda/queue/scheduler 2>/dev/null || true
free -h | head -2
