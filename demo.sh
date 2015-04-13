#!/bin/bash

# Make sure only root can run our script
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

cmd-ls() {
  echo "listing nodes"
  sudo kubectl get nodes
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
  sudo kubectl get pods
}

cmd-down() {
  kubectl delete rc frontend-controller
  kubectl get pods | awk 'NR!=1' | awk '{print $1}' | xargs kubectl delete pod || true
  kubectl get services | awk 'NR!=1' | awk '{print $1}' | grep -v "kubernetes" | xargs kubectl delete service || true
  cmd-ls
  sleep 10
  ssh -o StrictHostKeyChecking=no -i /root/.ssh/id_rsa root@democluster-node1 bash /vagrant/demo.sh tidy
  ssh -o StrictHostKeyChecking=no -i /root/.ssh/id_rsa root@democluster-node2 bash /vagrant/demo.sh tidy
}

cmd-tidy() {
  # kill all stopped containers that are not wait-for-weave
  sudo docker ps -a | grep Exited | grep -v "wait-for-weave" | awk '{print $1}' | xargs sudo docker rm
}

cmd-shift() {
  local mode="ssd";
  echo "deleting redis-master-pod - spinning"
  kubectl delete pod redis-master-pod
  sleep 5
  # there is a template for the redis master - we change a nodeSelector to co-ordinate the DB moving servers 
  cat /vagrant/examples/guestbook/redis-master-pod-template.json | sed "s/_DISKTYPE_/$mode/" > /tmp/redis-master-pod-ssd.json
  # the redis-master is a pod because then we can use the nodeSelector field
  kubectl create -f /tmp/redis-master-pod-ssd.json
  echo "starting redis-master-pod - ssd"
  sudo kubectl get pods
}

usage() {
cat <<EOF
Usage:
demo.sh up  <spinning|ssd>
demo.sh down
demo.sh ls
demo.sh tidy
demo.sh shift
EOF
  exit 1
}

main() {
  case "$1" in
  up)                       shift; cmd-up $@;;
  down)                     shift; cmd-down $@;;
  ls)                       shift; cmd-ls $@;;
  tidy)                     shift; cmd-tidy $@;;
  shift)                    shift; cmd-shift $@;;
  *)                        usage $@;;
  esac
}

main "$@"