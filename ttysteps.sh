# first, lets check the status of our vagrant cluster
vagrant status
# now we SSH into the master node
vagrant ssh master
# we ask Kubernetes for its current status
sudo kubectl get nodes
sudo kubectl get pods
# next, we show the system containers running on node1
sudo ssh root@democluster-node1 sudo docker ps -a
# OK - its time to deploy some Kubernetes services
sudo kubectl create -f /etc/k8s-demo/reredis-master-service.json
sudo kubectl create -f /etc/k8s-demo/frontend-service.json
# lets check those services were registered
sudo kubectl get services
# now, we will deploy the redis master pod to the spinning disk node
sudo kubectl create -f /etc/k8s-demo/redis-master-pod-spinning.json
# and we will deploy a replication controller for the PHP container
sudo kubectl create -f /etc/k8s-demo/frontend-controller.json
# now lets check the pods and wait for the redis-master pod to be Running
sudo kubectl get pods
# in particular - lets check that the redis1-master pod is on node1
sudo kubectl get pods | grep name=redis-master
# cool - so now we have an app!
# lets check that we can ask the PHP for messages
curl -sS -L "http://172.16.255.251:8000/index.php?cmd=get&key=messages"
# now we write some data to the PHP app
curl -sS -L "http://172.16.255.251:8000/index.php?cmd=set&key=messages&value=node1,apples"
# now we want to migrate the Redis container from node1 to node2
# first, we stop the container
sudo kubectl delete pod redis-master-pod
# next, we schedule the redis container onto node2 (the ssd drive node)
sudo kubectl create -f /etc/k8s-demo/redis-master-pod-ssd.json
# now lets check the pods and wait for the redis-master pod to be Running (again)
sudo kubectl get pods
# in particular - lets check that the redis-master pod is on node2
sudo kubectl get pods | grep name=redis-master
# the data should have migrated along with the pod (because flocker)
curl -sS -L "http://172.16.255.251:8000/index.php?cmd=get&key=messages"
# yay! we have migrated a database container AND its data using Kubernetes and Flocker
# lets confirm for sure that the Redis container has moved to node2
sudo ssh root@democluster-node1 sudo docker ps -a | grep redis-master
# so we can see that the Redis container running on node1 has Exited
sudo ssh root@democluster-node2 sudo docker ps -a | grep redis-master
# the Redis container is now running on node2