#!/bin/bash

# Make sure only root can run our script
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

cmd-ls() {
  echo "listing pods"
  sudo kubectl get pods
  echo "listing rcs"
  sudo kubectl get rc
  echo "listing services"
  sudo kubectl get services
}

cmd-up() {
  local mode="$1";

  if [[ -z "$mode" ]]; then
    mode="spinning"
  fi
  echo "label node1 as spinning disk"
  sudo kubectl label --overwrite nodes democluster-node1 disktype=spinning
  echo "label node1 as ssd disk"
  sudo kubectl label --overwrite nodes democluster-node2 disktype=ssd
  echo "running redis-master-pod - $mode"
  # the redis-master is a pod because then we can use the nodeSelector field
  sudo kubectl create -f /vagrant/examples/guestbook/redis-master-pod-$mode.json
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
  cmd-ls
}

cmd-down() {
  sudo kubectl delete rc frontend-controller
  sudo kubectl delete rc redis-slave-controller
  sudo kubectl get pods | awk 'NR!=1' | awk '{print $1}' | xargs sudo kubectl delete pod || true
  sudo kubectl get services | awk 'NR!=1' | awk '{print $1}' | grep -v "kubernetes" | xargs sudo kubectl delete service || true
  cmd-ls
}

cmd-tidy() {
  sudo docker ps -a | grep Exited | grep -v "wait-for-weave" | awk '{print $1}' | xargs sudo docker rm
}

usage() {
cat <<EOF
Usage:
demo.sh up  <spinning|ssd>
demo.sh down
demo.sh ls
demo.sh tidy
EOF
  exit 1
}

main() {
  case "$1" in
  up)                       shift; cmd-up $@;;
  down)                     shift; cmd-down $@;;
  ls)                       shift; cmd-ls $@;;
  tidy)                     shift; cmd-tidy $@;;
  *)                        usage $@;;
  esac
}

main "$@"