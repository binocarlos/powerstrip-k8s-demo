#!/bin/bash

# this is to test everything works - it should NOT be part of the packaged box

activate-service() {
  bash /srv/powerstrip-base-install/ubuntu/install.sh service $1
}

echo 172.16.255.250 > /etc/flocker/my_address
echo 172.16.255.250 > /etc/flocker/master_address

activate-service flocker-control
activate-service flocker-zfs-agent
activate-service powerstrip-flocker
activate-service powerstrip-weave
activate-service powerstrip

supervisorctl reload