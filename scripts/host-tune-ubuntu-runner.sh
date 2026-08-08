#!/usr/bin/env bash
# Host performance + cache layout for Ubuntu self-hosted runner (Azure).
# Safe to re-run. Avoids restarting docker/runner if a job is active unless FORCE_RESTART=1.
set -euo pipefail

CACHE=/var/cache/webkit-dnd
# Azure Ddsv5 ephemeral resource disk is usually mounted at /mnt (fast local SSD).
EPHEMERAL="${WEBKIT_DND_EPHEMERAL:-/mnt}"
RUNNER_SVC_GLOB='actions.runner.*.service'

echo "+ packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  tuned git rsync zstd pigz jq curl ca-certificates \
  ccache cmake ninja-build \
  linux-tools-common linux-tools-generic \
  2>&1 | tail -20 || true

if command -v tuned-adm >/dev/null; then
  systemctl enable --now tuned 2>/dev/null || true
  tuned-adm profile throughput-performance 2>/dev/null \
    || tuned-adm profile virtual-guest 2>/dev/null \
    || true
  tuned-adm active || true
fi

echo "+ sysctl compile-friendly"
cat > /etc/sysctl.d/99-webkit-dnd-perf.conf << 'SYS'
vm.swappiness = 5
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 20
vm.dirty_background_ratio = 5
vm.dirty_expire_centisecs = 3000
fs.file-max = 2097152
fs.inotify.max_user_watches = 1048576
fs.inotify.max_user_instances = 1024
kernel.sched_autogroup_enabled = 0
kernel.numa_balancing = 0
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.core.netdev_max_backlog = 5000
net.core.somaxconn = 4096
net.ipv4.tcp_fastopen = 3
SYS
sysctl --system >/dev/null 2>&1 || sysctl -p /etc/sysctl.d/99-webkit-dnd-perf.conf || true

echo "+ transparent hugepages madvise (not always — better for sparse compile heaps)"
if [[ -w /sys/kernel/mm/transparent_hugepage/enabled ]]; then
  echo madvise > /sys/kernel/mm/transparent_hugepage/enabled || true
  echo madvise > /sys/kernel/mm/transparent_hugepage/defrag || true
fi
cat > /etc/tmpfiles.d/webkit-dnd-thp.conf << 'T'
w /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise
w /sys/kernel/mm/transparent_hugepage/defrag - - - - madvise
T
systemd-tmpfiles --create /etc/tmpfiles.d/webkit-dnd-thp.conf 2>/dev/null || true

echo "+ CPU governor performance where available"
if [[ -d /sys/devices/system/cpu/cpu0/cpufreq ]]; then
  for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo performance > "$g" 2>/dev/null || true
  done
fi

echo "+ block I/O scheduler none"
for q in /sys/block/*/queue/scheduler; do
  dev=$(echo "$q" | cut -d/ -f4)
  [[ "$dev" =~ ^(loop|ram|sr) ]] && continue
  if grep -qw none "$q" 2>/dev/null; then echo none > "$q" || true; fi
  echo "  $dev: $(cat "$q" 2>/dev/null || true)"
done
cat > /etc/udev/rules.d/60-webkit-dnd-io.rules << 'U'
ACTION=="add|change", KERNEL=="vd*|nvme*|sd*|xvd*", ATTR{queue/scheduler}="none"
U
udevadm control --reload 2>/dev/null || true

echo "+ limits"
cat > /etc/security/limits.d/99-webkit-dnd.conf << 'L'
* soft nofile 1048576
* hard nofile 1048576
* soft nproc unlimited
* hard nproc unlimited
gha soft nofile 1048576
gha hard nofile 1048576
gha soft nproc unlimited
gha hard nproc unlimited
L

echo "+ cache dirs on OS disk + hot dirs on ephemeral if present"
mkdir -p \
  "${CACHE}"/{ccache,build-gtk,prefix,out,buildx-cache,images,tools,mirrors,git-partial} \
  /var/log
if [[ -d "$EPHEMERAL" ]] && mountpoint -q "$EPHEMERAL" 2>/dev/null; then
  mkdir -p "$EPHEMERAL/webkit-dnd"/{docker,build-gtk,buildx-cache,tmp}
  chown -R gha:docker "$EPHEMERAL/webkit-dnd" 2>/dev/null || chown -R gha:gha "$EPHEMERAL/webkit-dnd" 2>/dev/null || true
  # Prefer ephemeral for build trees (fast, disposable across deallocate)
  if [[ ! -L "${CACHE}/build-gtk" && ! -d "${CACHE}/build-gtk/.keep-os" ]]; then
    if [[ -d "${CACHE}/build-gtk" ]] && [[ -z "$(ls -A "${CACHE}/build-gtk" 2>/dev/null || true)" ]]; then
      rmdir "${CACHE}/build-gtk" 2>/dev/null || true
    fi
    if [[ ! -e "${CACHE}/build-gtk" ]]; then
      ln -sfn "$EPHEMERAL/webkit-dnd/build-gtk" "${CACHE}/build-gtk"
    fi
  fi
  if [[ ! -L "${CACHE}/buildx-cache" && ! -d "${CACHE}/buildx-cache/.keep-os" ]]; then
    if [[ -d "${CACHE}/buildx-cache" ]] && [[ -z "$(ls -A "${CACHE}/buildx-cache" 2>/dev/null || true)" ]]; then
      rmdir "${CACHE}/buildx-cache" 2>/dev/null || true
    fi
    if [[ ! -e "${CACHE}/buildx-cache" ]]; then
      ln -sfn "$EPHEMERAL/webkit-dnd/buildx-cache" "${CACHE}/buildx-cache"
    fi
  fi
fi
chown -R gha:docker "$CACHE" 2>/dev/null || chown -R gha:gha "$CACHE" 2>/dev/null || true

echo "+ docker daemon.json"
mkdir -p /etc/docker
DAEMON_JSON=/etc/docker/daemon.json
# Keep data-root on OS disk by default (survives deallocate). Optional ephemeral:
# set DOCKER_ON_EPHEMERAL=1 when idle to move graph to /mnt (faster, lost on deallocate).
DATA_ROOT_LINE=""
if [[ "${DOCKER_ON_EPHEMERAL:-0}" == "1" && -d "$EPHEMERAL/webkit-dnd/docker" ]]; then
  DATA_ROOT_LINE='"data-root": "/mnt/webkit-dnd/docker",'
fi
cat > "$DAEMON_JSON" << JSON
{
  ${DATA_ROOT_LINE}
  "log-driver": "json-file",
  "log-opts": { "max-size": "20m", "max-file": "3" },
  "live-restore": true,
  "storage-driver": "overlay2",
  "max-concurrent-downloads": 10,
  "max-concurrent-uploads": 5,
  "default-ulimits": {
    "nofile": { "Name": "nofile", "Hard": 1048576, "Soft": 1048576 }
  },
  "features": { "containerd-snapshotter": false }
}
JSON

echo "+ docker systemd limits"
mkdir -p /etc/systemd/system/docker.service.d
cat > /etc/systemd/system/docker.service.d/webkit-dnd.conf << 'D'
[Service]
LimitNOFILE=1048576
TasksMax=infinity
LimitNPROC=infinity
D

echo "+ github actions runner drop-in (all matching units)"
for svc in /etc/systemd/system/actions.runner.*.service; do
  [[ -f "$svc" ]] || continue
  base=$(basename "$svc")
  mkdir -p "/etc/systemd/system/${base}.d"
  cat > "/etc/systemd/system/${base}.d/override.conf" << 'R'
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
Environment=PATH=/usr/lib/ccache:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/bin
R
done

# Job hooks: touch activity + optional peer warm stamp
mkdir -p /opt/actions-runner/hooks
cat > /opt/actions-runner/hooks/job-started.sh << 'H'
#!/usr/bin/env bash
mkdir -p /var/cache/webkit-dnd/out
date -u +%s > /var/cache/webkit-dnd/out/last-runner-activity 2>/dev/null || true
H
cat > /opt/actions-runner/hooks/job-completed.sh << 'H'
#!/usr/bin/env bash
mkdir -p /var/cache/webkit-dnd/out
date -u +%s > /var/cache/webkit-dnd/out/last-runner-activity 2>/dev/null || true
H
chmod +x /opt/actions-runner/hooks/*.sh
chown -R gha:gha /opt/actions-runner/hooks 2>/dev/null || true

echo "+ fstrim + journald bounds"
systemctl enable --now fstrim.timer 2>/dev/null || true
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/webkit-dnd.conf << 'J'
[Journal]
SystemMaxUse=500M
RuntimeMaxUse=200M
MaxRetentionSec=14day
J

echo "+ git perf defaults for gha"
sudo -u gha git config --global pack.threads "$(nproc)" 2>/dev/null || true
sudo -u gha git config --global core.untrackedCache true 2>/dev/null || true
sudo -u gha git config --global feature.manyFiles true 2>/dev/null || true
sudo -u gha git config --global fetch.parallel 8 2>/dev/null || true
git config --system pack.threads "$(nproc)" 2>/dev/null || true
git config --system core.untrackedCache true 2>/dev/null || true

# Disable swap if tiny/noisy on Azure (we have 64G RAM). Keep file if present but swappiness already 5.
# Prefer no swap on compile hosts with large RAM.
if [[ "${DISABLE_SWAP:-1}" == "1" ]]; then
  swapoff -a 2>/dev/null || true
fi

systemctl daemon-reload

job_busy=0
if pgrep -f 'Runner.Worker' >/dev/null 2>&1 || docker ps -q 2>/dev/null | grep -q .; then
  job_busy=1
fi

if [[ "$job_busy" -eq 1 && "${FORCE_RESTART:-0}" != "1" ]]; then
  echo "+ job active: applied sysctl/THP/files; skipped docker/runner restart"
else
  systemctl try-reload-or-restart docker 2>/dev/null || systemctl restart docker || true
  systemctl restart systemd-journald 2>/dev/null || true
  for svc in /etc/systemd/system/actions.runner.*.service; do
    [[ -f "$svc" ]] || continue
    systemctl restart "$(basename "$svc")" || true
  done
fi

echo "+ summary"
tuned-adm active 2>/dev/null || true
sysctl vm.swappiness kernel.sched_autogroup_enabled
cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
df -h / /mnt /var/cache/webkit-dnd 2>/dev/null || df -h /
docker info 2>/dev/null | grep -E 'Storage Driver|Docker Root|CPUs|Total Memory' || true

# Auto docker-on-ephemeral when VM has been up long enough (default 3h).
# Does nothing if a job is active or uptime is short.
if [[ -x /usr/local/sbin/docker-ephemeral-enable.sh ]]; then
  AUTO_DOCKER_EPHEMERAL_HOURS="${AUTO_DOCKER_EPHEMERAL_HOURS:-2}"     /usr/local/sbin/docker-ephemeral-enable.sh || true
fi
# Always try non-blocking seed export if docker is up
if [[ -x /usr/local/sbin/docker-seed-export.sh ]] && systemctl is-active --quiet docker; then
  systemd-run --unit=webkit-dnd-seed-export-oneshot-$RANDOM --collect --nice=15     /usr/local/sbin/docker-seed-export.sh >/dev/null 2>&1 ||     nice -n 15 /usr/local/sbin/docker-seed-export.sh >/dev/null 2>&1 &
fi

echo "host-tune-ubuntu done"
