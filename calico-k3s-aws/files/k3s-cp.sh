#!/bin/bash
INSTALL_K3S_SKIP_DOWNLOAD=true K3S_KUBECONFIG_MODE="644" INSTALL_K3S_EXEC="--kubelet-arg=config=/etc/kubelet.conf --flannel-backend=none --cluster-cidr=$1 --disable-network-policy --disable=traefik,local-storage,metrics-server,servicelb" /root/install.sh

cp /var/lib/rancher/k3s/server/node-token /home/ubuntu/node-token 
chmod 644 /home/ubuntu/node-token
mkdir -p /home/ubuntu/.kube/
cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
