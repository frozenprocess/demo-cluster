#!/bin/bash

set -euo pipefail

: "${OPERATOR_IMAGE:?set OPERATOR_IMAGE to your pushed L2 dev operator image}"
CALIENT_VERSION="${CALIENT_VERSION:-v3.22.6}"
K3S_VERSION="${K3S_VERSION:-v1.34.1+k3s1}"
KUBEVIRT_VERSION="${KUBEVIRT_VERSION:-v1.8.2}"
CLUSTER_CIDR="${CLUSTER_CIDR:-10.42.0.0/16}"
EFILES="${EFILES:-/vagrant/enterprise_files}"
MANIFESTS="${MANIFESTS:-/vagrant/manifests}"
KUSER="${KUSER:-vagrant}"
KCFG=/home/$KUSER/.kube/config
TOKEN_FILE=/home/$KUSER/ui-token.txt

[ -s "$EFILES/docker.config" ] || { echo "missing $EFILES/docker.config"; exit 1; }
[ -s "$EFILES/license.yaml" ]  || { echo "missing $EFILES/license.yaml"; exit 1; }

MGMT_IFACE="${MGMT_IFACE:-$(ip -o route show default 2>/dev/null | awk '{print $5}' | head -1)}"
[ -n "$MGMT_IFACE" ] || { echo "no default-route (mgmt) iface"; exit 1; }
MGMT_IP=$(ip -4 -o addr show "$MGMT_IFACE" | awk '{print $4}' | cut -d/ -f1)
[ -n "$MGMT_IP" ] || { echo "no IP on mgmt iface $MGMT_IFACE"; exit 1; }
TRUNK_IFACE="${TRUNK_IFACE:-$(ls /sys/class/net | grep -E '^(en|eth)' | grep -v "^${MGMT_IFACE}$" | head -1)}"
[ -n "$TRUNK_IFACE" ] || { echo "no trunk (switch-facing) iface found"; exit 1; }
echo "mgmt=$MGMT_IFACE ($MGMT_IP) ; trunk=$TRUNK_IFACE"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y jq curl
cat > /etc/sysctl.d/99-inotify.conf <<'EOF'
fs.inotify.max_user_instances=8192
fs.inotify.max_user_watches=1048576
EOF
sysctl -p /etc/sysctl.d/99-inotify.conf

if [ ! -x /usr/local/bin/virtctl ]; then
  curl -fsSL -o /usr/local/bin/virtctl \
    "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/virtctl-${KUBEVIRT_VERSION}-linux-amd64"
  chmod +x /usr/local/bin/virtctl
fi

ip addr flush dev "$TRUNK_IFACE" 2>/dev/null || true
ip link set "$TRUNK_IFACE" up

echo "installing k3s ${K3S_VERSION}..."
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$K3S_VERSION" \
  INSTALL_K3S_EXEC="server --write-kubeconfig-mode=644 --flannel-backend=none --disable-network-policy --disable=traefik,local-storage,metrics-server --cluster-cidr=${CLUSTER_CIDR} --tls-san=127.0.0.1 --node-ip=${MGMT_IP}" sh -

for _ in $(seq 1 60); do [ -s /etc/rancher/k3s/k3s.yaml ] && break; sleep 2; done
mkdir -p "/home/$KUSER/.kube"
cp /etc/rancher/k3s/k3s.yaml "$KCFG"
chown -R "$KUSER:$KUSER" "/home/$KUSER/.kube"
chmod 600 "$KCFG"
export KUBECONFIG="$KCFG"

for _ in $(seq 1 60); do
  kubectl get nodes 2>/dev/null | grep -qE 'Ready|NotReady' && break
  sleep 5
done
kubectl get nodes 2>&1 | tail -2

echo "installing Calico Enterprise CRDs + prometheus operator (${CALIENT_VERSION})..."

kubectl create -f "https://downloads.tigera.io/ee/${CALIENT_VERSION}/manifests/operator-crds.yaml" || true
kubectl create -f "https://downloads.tigera.io/ee/${CALIENT_VERSION}/manifests/tigera-prometheus-operator.yaml" || true

echo "installing tigera-operator (image=${OPERATOR_IMAGE})..."
if [ -s "$EFILES/tigera-operator.yaml" ]; then OPSRC="$EFILES/tigera-operator.yaml"; else
  OPSRC=/tmp/tigera-operator.yaml
  curl -fsSL -o "$OPSRC" "https://downloads.tigera.io/ee/${CALIENT_VERSION}/manifests/tigera-operator.yaml"
fi
sed -E "s#image: .*/operator:[^\"']*#image: ${OPERATOR_IMAGE}#" "$OPSRC" | kubectl apply -f -

kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: {name: tigera-operator-crd-update}
rules:
- apiGroups: ["apiextensions.k8s.io"]
  resources: ["customresourcedefinitions"]
  verbs: ["get","list","watch","create","update","patch","delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: {name: tigera-operator-crd-update}
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: tigera-operator-crd-update}
subjects:
- {kind: ServiceAccount, name: tigera-operator, namespace: tigera-operator}
EOF

echo "creating pull secret..."
kubectl create secret generic tigera-pull-secret \
  --type=kubernetes.io/dockerconfigjson -n tigera-operator \
  --from-file=.dockerconfigjson="$EFILES/docker.config" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl patch serviceaccount tigera-operator -n tigera-operator \
  -p '{"imagePullSecrets":[{"name":"tigera-pull-secret"}]}'
kubectl rollout restart deployment tigera-operator -n tigera-operator
kubectl patch deployment -n tigera-prometheus calico-prometheus-operator \
  -p '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"tigera-pull-secret"}]}}}}' 2>/dev/null || true

echo "creating elasticsearch storage (local-storage disabled -> manual hostPath PV)..."
kubectl apply -f - <<'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata: {name: tigera-elasticsearch}
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
---
apiVersion: v1
kind: PersistentVolume
metadata: {name: tigera-elasticsearch-1}
spec:
  capacity: {storage: 5Gi}
  accessModes: [ReadWriteOnce]
  hostPath: {path: /var/tigera/elastic-data/1}
  persistentVolumeReclaimPolicy: Retain
  storageClassName: tigera-elasticsearch
EOF

echo "waiting for operator CRDs to be Established..."
for crd in installations.operator.tigera.io apiservers.operator.tigera.io managers.operator.tigera.io logstorages.operator.tigera.io; do
  for _ in $(seq 1 60); do
    [ "$(kubectl get crd "$crd" -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' 2>/dev/null)" = "True" ] && break
    sleep 2
  done
done

echo "applying Installation + Enterprise CRs..."
kubectl apply -f - <<EOF
apiVersion: operator.tigera.io/v1
kind: Installation
metadata: {name: default}
spec:
  variant: TigeraSecureEnterprise
  flexVolumePath: None
  kubeletVolumePluginPath: /var/lib/kubelet
  calicoNetwork:
    linuxDataplane: BPF
    bgp: Enabled
    multiInterfaceMode: Multus
    nodeAddressAutodetectionV4: {canReach: 8.8.8.8}
    ipPools:
    - cidr: ${CLUSTER_CIDR}
      encapsulation: VXLAN
  imagePullSecrets:
  - name: tigera-pull-secret
---
apiVersion: operator.tigera.io/v1
kind: LogStorage
metadata: {name: tigera-secure}
spec:
  nodes:
    count: 1
    resourceRequirements: {limits: {cpu: "2", memory: 6Gi}, requests: {storage: 5Gi}}
  retention: {auditReports: 91, complianceReports: 91, flows: 8, snapshots: 91}
  storageClassName: tigera-elasticsearch
---
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata: {name: tigera-secure}
---
apiVersion: operator.tigera.io/v1
kind: Manager
metadata: {name: tigera-secure}
---
apiVersion: operator.tigera.io/v1
kind: Monitor
metadata: {name: tigera-secure}
---
apiVersion: operator.tigera.io/v1
kind: LogCollector
metadata: {name: tigera-secure}
EOF

echo "waiting for APIServer..."
until [ "$(kubectl get tigerastatus -o=jsonpath='{.items[?(@.metadata.name=="apiserver")].status.conditions[?(@.type=="Available")].status}' 2>/dev/null)" = "True" ]; do sleep 5; done

echo "applying license..."
kubectl apply -f "$EFILES/license.yaml"

echo "waiting for calico-node..."
kubectl -n calico-system rollout status ds/calico-node --timeout=360s
kubectl patch felixconfiguration default --type=merge \
  -p '{"spec":{"flowLogsFlushInterval":"60s"}}' 2>/dev/null || true

echo "installing Multus (thin)..."
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset.yml

echo "installing KubeVirt (useEmulation: nested VMs are double-nested here)..."
kubectl apply -f "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml"
kubectl apply -f "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml"
kubectl -n kubevirt patch kubevirt kubevirt --type=merge \
  -p '{"spec":{"configuration":{"developerConfiguration":{"useEmulation":true}}}}'
kubectl wait -n kubevirt kv kubevirt --for=condition=Available --timeout=600s

# --- L2 demo resources. NO l2-bridge.sh: the trunk is eth1 directly. ---------
echo "applying L2 demo resources (trunkPort -> ${TRUNK_IFACE})..."
kubectl apply -f "$MANIFESTS/namespace.yaml"
kubectl apply -f "$MANIFESTS/ip-reservations.yaml"
# Ship trunkbr0 in network.yaml (k3d default); rewrite to the real NIC for k3s.
sed "s/name: trunkbr0/name: ${TRUNK_IFACE}/" "$MANIFESTS/network.yaml" | kubectl apply -f -
kubectl apply -f "$MANIFESTS/pools.yaml"
kubectl apply -f "$MANIFESTS/nads.yaml"
kubectl apply -f "$MANIFESTS/policy-1-default-deny.yaml"
kubectl apply -f "$MANIFESTS/policy-3-allow-icmp.yaml"
# kubectl apply -f "$MANIFESTS/vms.yaml"
kubectl apply -f "$MANIFESTS/vm-alpine.yaml"

echo "waiting for Tigera Manager (several minutes)..."
until [ "$(kubectl get tigerastatus -o=jsonpath='{.items[?(@.metadata.name=="manager")].status.conditions[?(@.type=="Available")].status}' 2>/dev/null)" = "True" ]; do sleep 5; done

echo "exposing Tigera Manager UI on ${MGMT_IP}:9443..."
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata: {name: calico-manager-public, namespace: calico-system}
spec:
  type: LoadBalancer
  ports: [{port: 9443, targetPort: 9443, protocol: TCP}]
  selector: {k8s-app: calico-manager}
EOF

echo "creating UI login token..."
kubectl create sa calidemo -n default 2>/dev/null || true
kubectl create clusterrolebinding calidemo-access \
  --clusterrole tigera-network-admin --serviceaccount default:calidemo 2>/dev/null || true
kubectl create token calidemo --duration 999999h > "$TOKEN_FILE"
chown "$KUSER:$KUSER" "$TOKEN_FILE"

echo "done. Manager UI: https://${MGMT_IP}:9443  token: $TOKEN_FILE"
echo "VMs on the ESXi-shared VLAN: kubectl get vmi -n virtual-machines -o wide"
