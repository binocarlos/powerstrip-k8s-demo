#!/bin/bash

. /srv/powerstrip-base-install/ubuntu/lib.sh

POWERSTRIP_FLOCKER_IMAGE="clusterhq/powerstrip-flocker"
REAL_DOCKER_SOCKET="unix:///var/run/docker.real.sock"
IP=`cat /etc/flocker/my_address`
CONTROLIP=`cat /etc/flocker/master_address`
HOSTID=$(powerstrip-base-install-get-flocker-uuid)

export DOCKER_HOST="$REAL_DOCKER_SOCKET"

supervisorctl stop powerstrip
supervisorctl stop powerstrip-flocker
docker rm -f powerstrip powerstrip-flocker

docker run --name powerstrip-flocker -d \
  --expose 80 \
  -e "MY_NETWORK_IDENTITY=$IP" \
  -e "FLOCKER_CONTROL_SERVICE_BASE_URL=http://$CONTROLIP:80/v1" \
  -e "MY_HOST_UUID=$HOSTID" \
  -v /srv/powerstrip-flocker/powerstripflocker/adapter.py:/app/powerstripflocker/adapter.py \
  $POWERSTRIP_FLOCKER_IMAGE

supervisorctl start powerstrip