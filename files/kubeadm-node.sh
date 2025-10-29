#!/bin/bash

TRIES=0

while [[ $(curl -k --write-out '%{http_code}' --silent --output /dev/null https://$1:6443/version) != "200" ]]
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
chmod 600 /home/ubuntu/calico-demo.pem
/usr/bin/scp -i "/home/ubuntu/calico-demo.pem" -o StrictHostKeyChecking=no ubuntu@$1:/home/ubuntu/join.sh /home/ubuntu/join.sh 
chmod +x /home/ubuntu/join.sh
bash /home/ubuntu/join.sh

rm -rf /home/ubuntu/calico-demo.pem
