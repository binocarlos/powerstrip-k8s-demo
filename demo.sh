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

cmd-get() {
  curl -sS -L "http://172.16.255.251:8000/index.php?cmd=get&key=messages" | sed 's/^{"data": "//' | sed 's/"}$//'
}

cmd-set() {
  curl -sS -L "http://172.16.255.251:8000/index.php?cmd=set&key=messages&value=$@"
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
  kubectl create -f /vagrant/examples/guestbook/redis-master-service.json
  echo "running frontend-service"
  kubectl create -f /vagrant/examples/guestbook/frontend-service.json
  echo "running redis-master-pod"
  kubectl create -f /vagrant/examples/guestbook/redis-master-controller.json
  echo "running frontend-controller"
  kubectl create -f /vagrant/examples/guestbook/frontend-controller.json
  sleep 10
  kubectl get pods
}

cmd-down() {
  kubectl delete rc -l name=frontend
  kubectl delete pod -l name=frontend
  kubectl delete service -l name=frontend

  kubectl delete rc -l name=redis-master
  kubectl delete pod -l name=redis-master
  kubectl delete service -l name=redis-master

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
  kubectl get rc redis-master -o yaml | sed 's/spinning/ssd/' | kubectl update -f -
  kubectl delete pod -l name=redis-master
  sleep 10
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
  get)                      shift; cmd-get $@;;
  set)                      shift; cmd-set $@;;
  *)                        usage $@;;
  esac
}

main "$@"