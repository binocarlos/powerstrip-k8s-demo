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
  cat examples/guestbook/redis-master-pod-template.json | sed "s/_DISKTYPE_/$mode/" > /tmp/redis-master-pod.json
  # the redis-master is a pod because then we can use the nodeSelector field
  sudo kubectl create -f /tmp/redis-master-pod.json
  echo "running redis-master-service"
  sudo kubectl create -f /vagrant/examples/guestbook/redis-master-service.json
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
  sleep 5
  sudo ssh -o StrictHostKeyChecking=no -i /root/.ssh/id_rsa root@democluster-node1 sudo bash /vagrant/demo.sh tidy
  sudo ssh -o StrictHostKeyChecking=no -i /root/.ssh/id_rsa root@democluster-node2 sudo bash /vagrant/demo.sh tidy
}

cmd-tidy() {
  # kill all stopped containers that are not wait-for-weave
  sudo docker ps -a | grep Exited | grep -v "wait-for-weave" | awk '{print $1}' | xargs sudo docker rm
}

cmd-shift() {
  local mode="ssd";
  sudo kubectl delete pod redis-master-pod
  sleep 5
  sudo ssh -o StrictHostKeyChecking=no -i /root/.ssh/id_rsa root@democluster-node1 sudo bash /vagrant/demo.sh tidy
  sudo ssh -o StrictHostKeyChecking=no -i /root/.ssh/id_rsa root@democluster-node2 sudo bash /vagrant/demo.sh tidy
  # there is a template for the redis master - we change a nodeSelector to co-ordinate the DB moving servers 
  cat examples/guestbook/redis-master-pod-template.json | sed "s/_DISKTYPE_/$mode/" > /tmp/redis-master-pod.json
  # the redis-master is a pod because then we can use the nodeSelector field
  sudo kubectl create -f /tmp/redis-master-pod.json
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