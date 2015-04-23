# first, lets check the status of our vagrant cluster
vagrant status
# now we SSH into the master node
vagrant ssh master
# we ask Kubernetes for its current status
kubectl get nodes
# OK - its time to deploy some Kubernetes services
kubectl create -f /vagrant/examples/guestbook/redis-master-service.json
kubectl create -f /vagrant/examples/guestbook/frontend-service.json
# lets check those services were registered
kubectl get services
# now, we will deploy the redis master pod to the spinning disk node
kubectl create -f /vagrant/examples/guestbook/redis-master-controller.json
# and we will deploy a replication controller for the PHP container
kubectl create -f /vagrant/examples/guestbook/frontend-controller.json
# now lets check the pods and wait for the redis-master pod to be Running
kubectl get pods
# in particular - lets check that the redis1-master pod is on node1
kubectl get pods | grep name=redis-master
# cool - so now we have an app!
# lets check that we can ask the PHP for messages
curl -sS -L "http://172.16.255.251:8000/index.php?cmd=get&key=messages"
# now we write some data to the PHP app
curl -sS -L "http://172.16.255.251:8000/index.php?cmd=set&key=messages&value=node1,apples"
# now we want to migrate the Redis container from node1 to node2
# we change the nodeSelector from spinning to ssd
kubectl get rc redis-master -o yaml | sed 's/spinning/ssd/' | kubectl update -f -
# then we delete the existing redis pod - the replication controller will restart it
kubectl delete pod -l name=redis-master
# now lets check the pods and wait for the redis-master pod to be Running (again)
kubectl get pods
# in particular - lets check that the redis-master pod is on node2
kubectl get pods | grep name=redis-master
# the data should have migrated along with the pod (because flocker)
curl -sS -L "http://172.16.255.251:8000/index.php?cmd=get&key=messages"
# yay! we have migrated a database container AND its data using Kubernetes and Flocker