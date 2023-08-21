#!/bin/bash
POD_CIDR=$1

echo "Waiting for k3s Cluser to comeup"
while [[ $(curl -k --write-out '%{http_code}' --silent --output /dev/null https://`hostname`:6443/) != "401" ]]
do
    sleep 1
done

CALICO_VERSION=`curl https://api.github.com/repos/projectcalico/calico/releases | yq -r '.[].tag_name' | sort -d | tail -n1`

kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/$CALICO_VERSION/manifests/tigera-operator.yaml

sleep 2

kubectl create -f -<<EOF
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    bgp: Enabled
    ipPools:
    - blockSize: 26
      cidr: $POD_CIDR
      encapsulation: VXLAN
      natOutgoing: Enabled
      nodeSelector: all()
---
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}
EOF

echo "Waiting for Calico"
while [[ $(kubectl get tigerastatus -o=jsonpath='{.items[?(@.metadata.name=="calico")].status.conditions[?(@.type=="Available")].status}') != "True" ]]
do
    sleep 1
done
