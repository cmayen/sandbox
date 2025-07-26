#!/bin/bash
set -euo pipefail

echo "[INFO] Stopping kubelet and container runtime..."
sudo systemctl stop kubelet || true
sudo systemctl stop containerd || sudo systemctl stop docker || true

echo "[INFO] Resetting kubeadm..."
sudo kubeadm reset -f || true

echo "[INFO] Cleaning up Kubernetes manifests and configs..."
sudo rm -rf /etc/kubernetes/pki
sudo rm -rf /etc/kubernetes/manifests
sudo rm -rf /etc/kubernetes/*.conf

echo "[INFO] Cleaning up etcd data..."
sudo rm -rf /var/lib/etcd

echo "[INFO] Removing kubeconfig..."
rm -rf $HOME/.kube

echo "[INFO] Flushing iptables and resetting network..."
sudo iptables -F
sudo iptables -t nat -F
sudo iptables -t mangle -F
sudo iptables -X
sudo systemctl restart containerd || sudo systemctl restart docker || true

echo "[INFO] Node cleanup complete. Running 'kubeadm init ...'."

sudo kubeadm init --control-plane-endpoint=master-node --upload-certs
