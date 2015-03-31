#!/bin/bash

# Make sure only root can run our script
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

echo "running redis-master-controller"
sudo kubectl create -f /vagrant/examples/guestbook/redis-master-controller.json
echo "running redis-master-service"
sudo kubectl create -f /vagrant/examples/guestbook/redis-master-service.json
echo "running redis-slave-controller"
sudo kubectl create -f /vagrant/examples/guestbook/redis-slave-controller.json
echo "running redis-slave-service"
sudo kubectl create -f /vagrant/examples/guestbook/redis-slave-service.json
echo "running frontend-controller"
sudo kubectl create -f /vagrant/examples/guestbook/frontend-controller.json
echo "running frontend-service"
sudo kubectl create -f /vagrant/examples/guestbook/frontend-service.json
echo "listing pods"
sudo kubectl get pods
echo "listing rcs"
sudo kubectl get rc
echo "listing services"
sudo kubectl get services