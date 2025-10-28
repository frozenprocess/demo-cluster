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
/usr/bin/scp -i "/home/ubuntu/calico-demo.pem" -o StrictHostKeyChecking=no ubuntu@10.138.0.4:/home/ubuntu/join.sh /home/ubuntu/join.sh 
chmod +x /home/ubuntu/join.sh

rm -rf /home/ubuntu/calico-demo.pem
