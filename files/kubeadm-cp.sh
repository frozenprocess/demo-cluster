#!/bin/bash

CLUSTER_CIDR=$1
SERVICE_CIDR=$2
CLUSTER_DNS=`echo $2 | sed -E "s/^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.)[0-9]{1,3}\/[0-9]{2}/\110/"`
CLUSTER_DOMAIN=$3
K3S_FEATURES=$4
DISABLE_CLOUD_PROVIDER=$5
GPU=$7

EXTERNAL_IP=`curl -H "Metadata-Flavor: Google" http://metadata/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip`

if [[ $DISABLE_CLOUD_PROVIDER == "false" ]];then
DISABLE_CLOUD_PROVIDER_STRING="--kubelet-arg=cloud-provider=external --disable-cloud-controller"
fi

kubeadm init --pod-network-cidr=$CLUSTER_CIDR


echo "Waiting for Kubeadm cluster to comeup"
while [[ $(kubectl --kubeconfig="/etc/kubernetes/admin.conf" get nodes --no-headers=true | wc -l) != "1" ]]
do
    sleep 1
done

mkdir -p $HOME/.kube ubuntu/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config ubuntu/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
sudo chown ubuntu:ubuntu ubuntu/.kube/config

if [[ $DISABLE_CLOUD_PROVIDER == "false" ]];then
kubectl --kubeconfig="/etc/kubernetes/admin.conf" create cm -n kube-system cloud-config --from-file=/tmp/cloud.config
kubectl --kubeconfig="/etc/kubernetes/admin.conf" create -f /tmp/cloud-controller.yaml
fi

## Is this a GPU node? let's install GPU stuff for AI
if [[ "$GPU" -ge 1 ]]; then
NVIDIA_VERSION=`curl https://api.github.com/repos/NVIDIA/k8s-device-plugin/releases | yq -r '.[].tag_name' | sort -d | tail -n1`
curl -s https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/$NVIDIA_VERSION/deployments/static/nvidia-device-plugin.yml   | sed '/^[[:space:]]*containers:/i\      runtimeClassName: nvidia' > nvidia.yaml
kubectl --kubeconfig="/etc/kubernetes/admin.conf" create -f nvidia.yaml
fi

kubeadm token create --print-join-command  > /home/ubuntu/join.sh
chmod +x /home/ubuntu/join.sh
chmod 644 /home/ubuntu/join.sh
