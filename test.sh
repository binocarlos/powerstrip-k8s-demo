#!/bin/bash

do-error() {
  echo "-------------------" >&2
  echo "ERROR!" >&2
  echo "$@" >&2
  exit 1
}

# block until the redis container is running
wait-for-redis-running() {
  while [[ ! `vagrant ssh master -c "kubectl get pods | grep name=redis-master | grep Running"` ]];
  do
    echo "wait for container to be Running" && sleep 5
  done
  echo "Sleeping for 10 secs for network"
  sleep 10
}

if [[ -f "/vagrant" ]]; then
  do-error "it looks like you are running the test from inside vagrant"
fi

datestring=$(date)
unixsecs=$(date +%s)
flockervolumename="testflocker$unixsecs"
swarmvolumename="testswarm$unixsecs"
# we write the datestring into the guestbook with no spaces because URL encoding
writedate=`echo "$datestring" | sed 's/ //g'`

echo "running test of basic Flocker migration without k8s"

# this will test that the underlying flocker mechanism is working
# it runs an Ubuntu container on node1 that writes to a Flocker volume
# it then runs another Ubuntu container on node2 that loads the data from this volume

echo "pull busybox onto node1"
vagrant ssh node1 -c "sudo docker pull busybox"
echo "pull busybox onto node2"
vagrant ssh node2 -c "sudo docker pull busybox"

echo "writing data to node1 ($datestring)"
vagrant ssh node1 -c "sudo docker run --rm -v /flocker/$flockervolumename:/data busybox sh -c \"echo $datestring > /data/file.txt\""
echo "reading data from node2"
filecontent=`vagrant ssh node2 -c "sudo docker run --rm -v /flocker/$flockervolumename:/data busybox sh -c \"cat /data/file.txt\""`
if [[ $filecontent == *"$datestring"* ]]
then
  echo "Datestring: $datestring found!"
else
  do-error "The contents of the text file is not $datestring it is: $filecontent"
fi

echo "clean up k8s"
vagrant ssh master -c "sudo bash /vagrant/demo.sh down"
vagrant ssh master -c "sudo bash /vagrant/demo.sh down"

echo "Starting k8s services"
vagrant ssh master -c "kubectl create -f /vagrant/examples/guestbook/redis-master-service.json"
vagrant ssh master -c "kubectl create -f /vagrant/examples/guestbook/frontend-service.json"
echo "Starting k8s rcs"
vagrant ssh master -c "kubectl create -f /vagrant/examples/guestbook/redis-master-controller.json"
vagrant ssh master -c "kubectl create -f /vagrant/examples/guestbook/frontend-controller.json"
echo "Listing k8s services & rcs & pods"
vagrant ssh master -c "sudo bash /vagrant/demo.sh ps"

echo "Waiting for the redis-master to become Running"

wait-for-redis-running

echo "Writing a value to the guestbook"
insertresponse=`vagrant ssh master -c "curl -sS -L \"http://172.16.255.251:8000/index.php?cmd=set&key=messages&value=node1,apples,$writedate\""`
output=`vagrant ssh master -c "curl -sS -L \"http://172.16.255.251:8000/index.php?cmd=get&key=messages\""`

if [[ $output == *"$writedate"* ]]
then
  echo "Datestring: $writedate found!"
else
  do-error "The contents of the guestbook entry does not contain $writedate it is: $output"
fi

echo "Rewriting the k8s rc"
vagrant ssh master -c "kubectl get rc redis-master -o yaml | sed 's/spinning/ssd/' | kubectl update -f -"

echo "Deleting the redis-master pod"
vagrant ssh master -c "kubectl delete pod -l name=redis-master"

echo "Waiting for the redis-master to become Running"

wait-for-redis-running

echo "Get the value from the guestbook"
output=`vagrant ssh master -c "curl -sS -L \"http://172.16.255.251:8000/index.php?cmd=get&key=messages\""`

if [[ $output == *"$writedate"* ]]
then
  echo "Datestring: $writedate found!"
else
  do-error "The contents of the guestbook entry does not contain $writedate it is: $output"
fi

echo "all tests were succesful"
exit 0