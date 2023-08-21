#!/bin/bash
ARCH=`uname -m`

if [[ $ARCH == "x86_64" ]]
then
curl -L https://github.com/mikefarah/yq/releases/download/v4.33.3/yq_linux_amd64 -o /usr/local/bin/yq
chmod +x /usr/local/bin/yq
else
curl -L https://github.com/mikefarah/yq/releases/download/v4.33.3/yq_linux_arm64 -o /usr/local/bin/yq
chmod +x /usr/local/bin/yq
fi

if [[ -z "$1" ]]
then
K3S_VERSION=1.25
else
K3S_VERSION=$1
fi

# Get the latest K3s binary for the above version of K3s
INSTALL_K3S_VERSION=`curl https://api.github.com/repos/k3s-io/k3s/releases | yq -r '.[].tag_name' | egrep "$K3S_VERSION" | head -n 1`

if [[ $ARCH == "x86_64" ]]
then
echo "Downloading k3s binary for $ARCH"
/usr/bin/curl -L https://github.com/k3s-io/k3s/releases/download/$INSTALL_K3S_VERSION/k3s -o /usr/local/bin/k3s
echo "Downloading calicoctl binary $ARCH"
/usr/bin/curl -L https://github.com/projectcalico/calico/releases/latest/download/calicoctl-linux-amd64 -o /usr/local/bin/calicoctl
else
echo "Downloading k3s binary for $ARCH"
/usr/bin/curl -L https://github.com/k3s-io/k3s/releases/download/$INSTALL_K3S_VERSION/k3s-arm64 -o /usr/local/bin/k3s
echo "Downloading calicoctl binary $ARCH"
/usr/bin/curl -L https://github.com/projectcalico/calico/releases/latest/download/calicoctl-linux-arm64 -o /usr/local/bin/calicoctl
fi

/usr/bin/chmod +x /usr/local/bin/k3s
/usr/bin/chmod +x /usr/local/bin/calicoctl 

/usr/bin/curl https://get.k3s.io/ > /root/install.sh
/usr/bin/chmod +x /root/install.sh


# Increase Kubelet Pod limit
cat >>  /etc/kubelet.conf <<-EOF
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
maxPods: 4000
EOF
# Increase Kubelet Pod limit
