#!/usr/bin/env bash
#
# Kubernetes control-plane repair helper
# - Fixes common issues (cgroup mismatch, stale manifests/etcd)
# - Can reset and optionally re-init the control plane
#
# Usage examples:
#   sudo ./k8s-repair.sh --diagnose
#   sudo ./k8s-repair.sh --reset --yes
#   sudo ./k8s-repair.sh --reset --reinit --control-plane-endpoint master-node --upload-certs --yes
#   sudo ./k8s-repair.sh --reinit --init-args "--control-plane-endpoint master-node --upload-certs --pod-network-cidr 10.244.0.0/16" --yes
#
set -euo pipefail

### Defaults / flags ###
RUNTIME_ENDPOINT="unix:///var/run/containerd/containerd.sock"
DO_DIAGNOSE=false
DO_RESET=false
DO_REINIT=false
YES=false
CONTROL_PLANE_ENDPOINT=""
UPLOAD_CERTS=false
INIT_ARGS=""

### Helpers ###
red()   { echo -e "\e[31m$*\e[0m"; }
green() { echo -e "\e[32m$*\e[0m"; }
yellow(){ echo -e "\e[33m$*\e[0m"; }

confirm() {
  if $YES; then
    return 0
  fi
  read -rp "$1 [y/N]: " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]]
}

need_root() {
  if [[ $EUID -ne 0 ]]; then
    red "[FATAL] Please run as root (sudo)."
    exit 1
  fi
}

usage() {
  cat <<EOF
Usage: sudo $0 [options]

Options:
  --diagnose                    Only run diagnostics (no changes)
  --reset                       Run 'kubeadm reset -f' and wipe /etc/kubernetes & /var/lib/etcd
  --reinit                      After repair/reset, run 'kubeadm init'
  --control-plane-endpoint STR  Shortcut to add to kubeadm init (same as passing via --init-args)
  --upload-certs                Add --upload-certs to kubeadm init
  --init-args "ARGS"            Full custom kubeadm init args (overrides the above two options)
  --yes                         Non-interactive; assume 'yes' to prompts
  -h|--help                     Show this message

Examples:
  sudo $0 --reset --reinit --control-plane-endpoint master-node --upload-certs --yes
  sudo $0 --reinit --init-args "--control-plane-endpoint master-node --upload-certs --pod-network-cidr 10.244.0.0/16" --yes
EOF
  exit 0
}

### Parse args ###
while [[ $# -gt 0 ]]; do
  case "$1" in
    --diagnose) DO_DIAGNOSE=true; shift ;;
    --reset) DO_RESET=true; shift ;;
    --reinit) DO_REINIT=true; shift ;;
    --control-plane-endpoint) CONTROL_PLANE_ENDPOINT="$2"; shift 2 ;;
    --upload-certs) UPLOAD_CERTS=true; shift ;;
    --init-args) INIT_ARGS="$2"; shift 2 ;;
    --yes) YES=true; shift ;;
    -h|--help) usage ;;
    *) red "Unknown option: $1"; usage ;;
  esac
done

need_root

echo "=== Kubernetes Repair Script ==="

### 1) Diagnostics ###########################################################
diagnose() {
  echo "==[ DIAGNOSTICS ]========================================================="
  for svc in kubelet containerd; do
    if systemctl is-active --quiet "$svc"; then
      echo "  [OK] $svc is running"
    else
      echo "  [WARN] $svc is NOT running"
    fi
  done

  echo
  echo "  [INFO] Cgroup drivers:"
  local cgroupd="unknown"
  if [[ -f /etc/containerd/config.toml ]]; then
    cgroupd=$(grep -i 'SystemdCgroup' /etc/containerd/config.toml 2>/dev/null | awk -F= '{print $2}' | tr -d ' "')
  fi
  echo "    containerd SystemdCgroup = ${cgroupd:-unknown}"

  local kubelet_cg="unknown"
  if [[ -f /var/lib/kubelet/config.yaml ]]; then
    kubelet_cg=$(grep -i '^cgroupDriver' /var/lib/kubelet/config.yaml 2>/dev/null | awk '{print $2}')
  fi
  echo "    kubelet cgroupDriver     = ${kubelet_cg:-unknown}"

  if [[ "$cgroupd" != "true" || "$kubelet_cg" != "systemd" ]]; then
    echo "  [WARN] cgroup drivers may be mismatched (expect: containerd=true, kubelet=systemd)"
  else
    echo "  [OK] cgroup drivers look consistent (systemd)"
  fi

  echo
  echo "  [INFO] Ports:"
  for port in 6443 10250; do
    if lsof -i :$port &>/dev/null; then
      echo "    Port $port -> IN USE"
    else
      echo "    Port $port -> free"
    fi
  done

  echo
  echo "  [INFO] Control-plane containers (crictl ps -a):"
  if command -v crictl &>/dev/null; then
    crictl --runtime-endpoint "$RUNTIME_ENDPOINT" ps -a | grep -E 'kube-|etcd' || echo "    None found"
  else
    echo "    crictl not installed"
  fi

  echo
  echo "  [INFO] kubelet logs (last 50 lines):"
  journalctl -xeu kubelet -n 50 || true

  echo "========================================================================="
}

### 2) Ensure containerd & kubelet cgroup drivers match (systemd) ##########
fix_cgroups() {
  echo "==[ FIX: cgroup drivers ]================================================="

  # containerd
  if [[ ! -f /etc/containerd/config.toml ]]; then
    echo "  /etc/containerd/config.toml not found, generating default..."
    containerd config default >/etc/containerd/config.toml
  fi
  if grep -q 'SystemdCgroup *= *false' /etc/containerd/config.toml; then
    echo "  Setting containerd SystemdCgroup=true"
    sed -i 's/SystemdCgroup *= *false/SystemdCgroup = true/g' /etc/containerd/config.toml
    systemctl restart containerd
  else
    echo "  containerd SystemdCgroup already true (or not found)"
  fi

  # kubelet (if config exists)
  if [[ -f /var/lib/kubelet/config.yaml ]]; then
    if ! grep -q '^cgroupDriver: systemd' /var/lib/kubelet/config.yaml; then
      echo "  Setting kubelet cgroupDriver=systemd in /var/lib/kubelet/config.yaml"
      cp /var/lib/kubelet/config.yaml /var/lib/kubelet/config.yaml.bak.$(date +%s)
      # Replace or append
      if grep -q '^cgroupDriver:' /var/lib/kubelet/config.yaml; then
        sed -i 's/^cgroupDriver: .*/cgroupDriver: systemd/' /var/lib/kubelet/config.yaml
      else
        echo "cgroupDriver: systemd" >> /var/lib/kubelet/config.yaml
      fi
      systemctl restart kubelet || true
    else
      echo "  kubelet cgroupDriver already systemd"
    fi
  else
    echo "  /var/lib/kubelet/config.yaml not present yet (will be created by kubeadm init)"
  fi
  echo "========================================================================="
}

### 3) Apply kernel/sysctl prereqs ##########################################
sysctl_tune() {
  echo "==[ FIX: sysctl & modules ]==============================================="
  modprobe br_netfilter || true
  cat <<EOF >/etc/sysctl.d/kubernetes.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
  sysctl --system >/dev/null
  echo "========================================================================="
}

### 4) kubeadm reset (optional) #############################################
do_reset() {
  echo "==[ RESET ]==============================================================="
  if confirm "This will run 'kubeadm reset -f' and wipe /etc/kubernetes & /var/lib/etcd. Continue?"; then
    kubeadm reset -f || true
    systemctl stop kubelet || true
    systemctl stop containerd || true
    rm -rf /etc/kubernetes /var/lib/etcd "$HOME/.kube"
    systemctl start containerd
    systemctl start kubelet || true
    green "[OK] Reset complete."
  else
    yellow "[SKIP] Reset aborted."
  fi
  echo "========================================================================="
}

### 5) kubeadm init (optional) ##############################################
do_reinit() {
  echo "==[ INIT ]================================================================"
  local args=""
  if [[ -n "$INIT_ARGS" ]]; then
    args="$INIT_ARGS"
  else
    [[ -n "$CONTROL_PLANE_ENDPOINT" ]] && args="$args --control-plane-endpoint $CONTROL_PLANE_ENDPOINT"
    $UPLOAD_CERTS && args="$args --upload-certs"
  fi

  if [[ -z "$args" ]]; then
    yellow "[WARN] No init arguments provided. You'll probably want at least --control-plane-endpoint."
    if ! confirm "Run 'kubeadm init' with NO extra args?"; then
      echo "Aborting init."
      return
    fi
  fi

  echo "Running: kubeadm init $args"
  kubeadm init $args

  # Setup kubeconfig for the invoking user (root or sudo user)
  local TARGET_USER=${SUDO_USER:-root}
  local TARGET_HOME
  TARGET_HOME=$(eval echo "~$TARGET_USER")

  mkdir -p "$TARGET_HOME/.kube"
  cp /etc/kubernetes/admin.conf "$TARGET_HOME/.kube/config"
  chown "$(id -u "$TARGET_USER")":"$(id -g "$TARGET_USER")" "$TARGET_HOME/.kube/config"

  green "[OK] kubeadm init complete."
  echo "========================================================================="
}

### Main flow ###############################################################

$DO_DIAGNOSE && diagnose

# If only diagnose was requested, exit now.
if $DO_DIAGNOSE && ! $DO_RESET && ! $DO_REINIT; then
  exit 0
fi

sysctl_tune
fix_cgroups

if $DO_RESET; then
  do_reset
fi

if $DO_REINIT; then
  do_reinit
fi

green "[DONE] Repair script finished."

