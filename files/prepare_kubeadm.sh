#!/bin/bash
ARCH=`uname -m`

YQ_VERSION=`curl https://api.github.com/repos/mikefarah/yq/releases | jq -r '.[].tag_name' | grep -Ev '(-beta|-rc)' | sort -V | tail -n1`
RUNC_VERSION=`curl https://api.github.com/repos/opencontainers/runc/releases | jq -r '.[].tag_name' | grep -Ev '(-beta|-rc)' | sort -V | tail -n1`
CNI_VERSION=`curl https://api.github.com/repos/containernetworking/plugins/releases | jq -r '.[].tag_name' | grep -Ev '(-beta|-rc)' | sort -V | tail -n1`
CONTAINERD_VERSION=`curl https://api.github.com/repos/containerd/containerd/releases | jq -r '.[].tag_name' | grep -Ev '(-beta|-rc)' | sort -V | tail -n1 | sed 's/v//'`
# https://github.com/opencontainers/runc/releases/download/$RUNC_VERSION/runc.amd64
# https://github.com/containernetworking/plugins/releases/download/$CNI_VERSION/cni-plugins-linux-amd64-v$CNI_VERSION.tgz

if [[ $ARCH == "x86_64" ]]
then
curl -L https://github.com/mikefarah/yq/releases/download/$YQ_VERSION/yq_linux_amd64 -o /usr/local/bin/yq
chmod +x /usr/local/bin/yq
curl -L https://github.com/opencontainers/runc/releases/download/$RUNC_VERSION/runc.amd64 -o /usr/local/bin/runc
chmod +x /usr/local/bin/runc
curl -OL https://github.com/containernetworking/plugins/releases/download/$CNI_VERSION/cni-plugins-linux-amd64-$CNI_VERSION.tgz
mkdir -p /opt/cni/bin
tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-$CNI_VERSION.tgz
curl -OL https://github.com/containerd/containerd/releases/download/v$CONTAINERD_VERSION/containerd-$CONTAINERD_VERSION-linux-amd64.tar.gz
tar Cxzvf /usr/local containerd-$CONTAINERD_VERSION-linux-amd64.tar.gz
else
curl -L https://github.com/mikefarah/yq/releases/download/$YQ_VERSION/yq_linux_arm64 -o /usr/local/bin/yq
chmod +x /usr/local/bin/yq
curl -L https://github.com/opencontainers/runc/releases/download/$RUNC_VERSION/runc.arm64 -o /usr/local/bin/runc
chmod +x /usr/local/bin/runc
curl -OL https://github.com/containernetworking/plugins/releases/download/$CNI_VERSION/cni-plugins-linux-arm64-$CNI_VERSION.tgz
mkdir -p /opt/cni/bin
tar Cxzvf /opt/cni/bin cni-plugins-linux-arm64-$CNI_VERSION.tgz
curl -OL https://github.com/containerd/containerd/releases/download/v$CONTAINERD_VERSION/containerd-$CONTAINERD_VERSION-linux-arm64.tar.gz
tar Cxzvf /usr/local containerd-$CONTAINERD_VERSION-linux-arm64.tar.gz
fi

## Is this a GPU node? let's install GPU stuff for AI
gpu=$(lspci | grep -i nvidia | wc -l)
if [ "$gpu" -ge 1 ]; then
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update -y

export NVIDIA_CONTAINER_TOOLKIT_VERSION=1.17.8-1
sudo apt-get install -y \
    nvidia-container-toolkit=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
    nvidia-container-toolkit-base=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
    libnvidia-container-tools=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
    libnvidia-container1=${NVIDIA_CONTAINER_TOOLKIT_VERSION}
else
  echo "No NVIDIA GPU detected."
fi

mkdir -p /usr/local/lib/systemd/system/
curl -L https://raw.githubusercontent.com/containerd/containerd/main/containerd.service -o /usr/local/lib/systemd/system/containerd.service

systemctl daemon-reload
systemctl enable --now containerd

systemctl restart containerd
mkdir /etc/containerd
# Cgroup baby
containerd config default | sed 's/SystemdCgroup = false/SystemdCgroup = true/' > /etc/containerd/config.toml
systemctl restart containerd


cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system

sysctl net.ipv4.ip_forward

if [[ -z "$1" ]]
then
KUBEADM_VERSION=v1.34
else
KUBEADM_VERSION=$1
fi
sudo apt-get update
# apt-transport-https may be a dummy package; if so, you can skip that package
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/$KUBEADM_VERSION/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
# This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$KUBEADM_VERSION/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl


# Increase Kubelet Pod limit
cat >>  /etc/kubelet.conf <<-EOF
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
maxPods: 4000
EOF
# Increase Kubelet Pod limit
