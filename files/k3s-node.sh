#!/bin/bash

TRIES=0

while [[ $(curl --write-out '%{http_code}' --silent --output /dev/null $1:6443) != "400" ]]
do
    if [[ $TRIES -eq 60 ]];then
        echo "Filed to query Control plane"
        break
    fi
    echo "Waiting for $1"
    sleep 1
    TRIES=$(( TRIES + 1 ))
done

echo "Agents"
/usr/bin/scp -i "/home/ubuntu/calico-demo.pem" -o StrictHostKeyChecking=no ubuntu@$1:/home/ubuntu/node-token /home/ubuntu/node-token 
K3S_TOKEN=`cat /home/ubuntu/node-token` K3S_URL="https://$1:6443" INSTALL_K3S_EXEC="--kubelet-arg=config=/etc/kubelet.conf" INSTALL_K3S_SKIP_DOWNLOAD=true /root/install.sh
rm -rf /home/ubuntu/calico-demo.pem
