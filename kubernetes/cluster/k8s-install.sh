#!/bin/bash

# run initial updates
sudo apt update
sudo apt upgrade -y

# disable swap
sudo swapoff -a
sudo sed -i '/\/swap\.img/ s/^/#/' /etc/fstab

# kernel stuff
sudo modprobe overlay
sudo modprobe br_netfilter
# persist after reboot
echo overlay | sudo tee /etc/modules-load.d/overlay.conf
echo br_netfilter | sudo tee -a /etc/modules-load.d/overlay.conf

# 
sudo tee /etc/sysctl.d/kubernetes.conf<<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system

# install containerd
sudo apt update
sudo apt install -y containerd
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# setup to add kubernetes apt repo
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# install k8s
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl

# mark as hold
sudo apt-mark hold kubelet kubeadm kubectl




