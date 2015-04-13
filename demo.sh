#!/bin/bash

# Make sure only root can run our script
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

cmd-ps() {
  echo "listing nodes"
  sudo kubectl get nodes
  echo "listing pods"
  sudo kubectl get pods
  echo "listing rcs"
  sudo kubectl get rc
  echo "listing services"
  sudo kubectl get services
}

wait-for-redis() {
  local redismode=""

  while [ "$redismode" != "Running" ]
  do
    redismode=`sudo kubectl get pods | grep redis-master-pod | awk '{print $7}'`
    echo "waiting for redis to be in running state: $redismode"
    sleep 5
  done
}

cmd-up() {
  echo "running redis-master-pod - $mode"
  #cat /vagrant/examples/guestbook/redis-master-pod-template.json | sed "s/\"disktype\":\"spinning\"/\"disktype\":\"ssd\"/" > /tmp/redis-master-pod.json
  # the redis-master is a pod because then we can use the nodeSelector field
  kubectl create -f /vagrant/examples/guestbook/redis-master-pod.json
  echo "running redis-master-service"
  kubectl create -f /vagrant/examples/guestbook/redis-master-service.json
  echo "running frontend-controller"
  kubectl create -f /vagrant/examples/guestbook/frontend-controller.json
  echo "running frontend-service"
  kubectl create -f /vagrant/examples/guestbook/frontend-service.json

  wait-for-redis

  kubectl get pods
}

cmd-down() {
  kubectl delete rc frontend-controller
  kubectl get pods | awk 'NR!=1' | awk '{print $1}' | xargs kubectl delete pod || true
  kubectl get services | awk 'NR!=1' | awk '{print $1}' | grep -v "kubernetes" | xargs kubectl delete service || true
  cmd-ps
  sleep 10
  ssh -o StrictHostKeyChecking=no -i /root/.ssh/id_rsa root@democluster-node1 bash /vagrant/demo.sh tidy
  ssh -o StrictHostKeyChecking=no -i /root/.ssh/id_rsa root@democluster-node2 bash /vagrant/demo.sh tidy
}

cmd-tidy() {
  # kill all stopped containers that are not wait-for-weave
  sudo docker ps -a | grep Exited | grep -v "wait-for-weave" | awk '{print $1}' | xargs sudo docker rm
}

cmd-switch() {
  kubectl delete pod redis-master
  kubectl delete service redis-master
  cat /vagrant/examples/guestbook/redis-master-pod.json | sed "s/\"disktype\":\"spinning\"/\"disktype\":\"ssd\"/" > /tmp/redis-master-pod.json
  kubectl create -f /tmp/redis-master-pod.json
  kubectl create -f /vagrant/examples/guestbook/redis-master-service.json
  wait-for-redis
  kubectl get pods
}

usage() {
cat <<EOF
Usage:
demo.sh up  
demo.sh switch [spinning|ssd]
demo.sh down
demo.sh ps
demo.sh tidy
EOF
  exit 1
}

main() {
  case "$1" in
  up)                       shift; cmd-up $@;;
  down)                     shift; cmd-down $@;;
  ps)                       shift; cmd-ps $@;;
  tidy)                     shift; cmd-tidy $@;;
  switch)                   shift; cmd-switch $@;;
  *)                        usage $@;;
  esac
}

main "$@"