#!/bin/bash

CLUSTER_CIDR=$1
SERVICE_CIDR=$2
CLUSTER_DNS=`echo $2 | sed -E "s/^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.)[0-9]{1,3}\/[0-9]{2}/\110/"`
CLUSTER_DOMAIN=$3
K3S_FEATURES=$4
DISABLE_CLOUD_PROVIDER=$5

# Increase pod-count
cat >>  /etc/kubelet.conf <<-EOF
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
maxPods: 4000
EOF
# Increase pod-count
if [[ $DISABLE_CLOUD_PROVIDER == "false" ]];then
DISABLE_CLOUD_PROVIDER_STRING="--kubelet-arg=cloud-provider=external --disable-cloud-controller"
fi

INSTALL_K3S_SKIP_DOWNLOAD=true K3S_KUBECONFIG_MODE="644" INSTALL_K3S_EXEC="--kubelet-arg=config=/etc/kubelet.conf $DISABLE_CLOUD_PROVIDER_STRING --flannel-backend=none --cluster-cidr=$CLUSTER_CIDR --service-cidr=$SERVICE_CIDR --cluster-dns=$CLUSTER_DNS --cluster-domain=$CLUSTER_DOMAIN --disable-network-policy --disable=$K3S_FEATURES" /root/install.sh

cp /var/lib/rancher/k3s/server/node-token /home/ubuntu/node-token 
chmod 644 /home/ubuntu/node-token
mkdir -p /home/ubuntu/.kube/
cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config

echo "Waiting for k3s Cluser to comeup"
while [[ $(curl -k --write-out '%{http_code}' --silent --output /dev/null https://`hostname`:6443/) != "401" ]]
do
    sleep 1
done

if [[ $DISABLE_CLOUD_PROVIDER == "false" ]];then
kubectl create cm -n kube-system cloud-config --from-file=/tmp/cloud.config
kubectl create -f /tmp/cloud-controller.yaml
fi