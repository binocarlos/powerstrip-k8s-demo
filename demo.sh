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

cmd-redis() {
  local redisaddress=`sudo kubectl get services | grep "redis-master" | awk '{print $4}'`
  local nodename=`sudo kubectl get pods | grep name=redis-master | awk '{print $5}' | sed 's/democluster-//' | sed 's/\/[0-9]\+.[0-9]\+.[0-9]\+.[0-9]\+//'`
  sudo ssh -o StrictHostKeyChecking=no -i /root/.ssh/id_rsa root@democluster-$nodename sudo docker run --entrypoint="/usr/local/bin/redis-cli" dockerfile/redis -h $redisaddress $@
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
  
  echo "running redis-master-service"
  kubectl create -f /etc/k8s-demo/redis-master-service.json
  echo "running frontend-service"
  kubectl create -f /etc/k8s-demo/frontend-service.json
  echo "running redis-master-pod"
  kubectl create -f /etc/k8s-demo/redis-master-pod-spinning.json
  echo "running frontend-controller"
  kubectl create -f /etc/k8s-demo/frontend-controller.json
  
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
  local messages=`cmd-redis get messages`
  local node="ssd"
  if [[ -n "$1" ]]; then
    node=$1
  fi
  echo "delete redis-master-pod"
  kubectl delete pod redis-master-pod
  sleep 5
  echo "re-allocate redis-master-pod"
  kubectl create -f /etc/k8s-demo/redis-master-pod-$node.json
  wait-for-redis
  kubectl get pods
}

cmd-boot() {
  bash /vagrant/install.sh boot $@
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
  boot)                     shift; cmd-boot $@;;
  up)                       shift; cmd-up $@;;
  down)                     shift; cmd-down $@;;
  ps)                       shift; cmd-ps $@;;
  tidy)                     shift; cmd-tidy $@;;
  switch)                   shift; cmd-switch $@;;
  redis)                    shift; cmd-redis $@;;
  *)                        usage $@;;
  esac
}

main "$@"