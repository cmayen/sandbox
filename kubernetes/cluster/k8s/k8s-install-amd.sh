#!/bin/bash

wget https://repo.radeon.com/amdgpu-install/6.3.4/ubuntu/noble/amdgpu-install_6.3.60304-1_all.deb
sudo apt install -y ./amdgpu-install_6.3.60304-1_all.deb
sudo amdgpu-install --usecase=dkms
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/amd-container-toolkit/apt/ jammy main" | sudo tee /etc/apt/sources.list.d/amd-container-toolkit.list
sudo apt update -y && sudo apt upgrade -y
sudo apt install amd-container-toolkit rocm-smi btop
sudo amd-ctk runtime configure
sudo apt install -y docker.io docker-compose-v2
sudo amd-ctk runtime configure
sudo systemctl restart docker

#curl https://raw.githubusercontent.com/ROCm/k8s-device-plugin/master/k8s-ds-amdgpu-dp.yaml > k8s-ds-amdgpu-dp.yaml
kubectl create -f k8s-ds-amdgpu-dp.yaml

kubectl apply -f tensorflow-gpu.yaml
kubectl get nodes -o wide && kubectl get pods -A -o wide

echo "# once running..."
echo "kubectl logs rocm-test-pod"

