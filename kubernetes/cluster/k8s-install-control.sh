#!/bin/bash


# Replace <your_pod_network_cidr> with a suitable CIDR,
# e.g., 10.244.0.0/16 for Flannel
sudo kubeadm init --pod-network-cidr=10.224.0.0/16

#
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# apply flannel yaml from master project at github
#kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
kubectl apply -f kube-flannel.yaml

# flannel for some reason doesnt take the network correctly
# from the yaml?? wtheck man
kubectl -n kube-flannel patch configmap kube-flannel-cfg \
--type merge \
-p '{"data":{"net-conf.json":"{\n \"Network\": \"10.224.0.0/16\",\n \"Backend\": {\"Type\":\"vxlan\"}\n}\n"}}'


# whoaaa. slow down a sec or 2
sleep 3


# To allow pods to be scheduled on the control plane
# node, remove this taint using the kubectl taint command:
# (not recommended) this is here only for development tests
#kubectl taint nodes fusion node-role.kubernetes.io/control-plane:NoSchedule-


# output stuffs
echo "kubectl get nodes && kubectl get pods -A"
