## GuestBook example

This example shows how to build a simple, multi-tier web application using Kubernetes and Docker.

The example consists of:
- A web frontend
- A redis master (for storage and a replicated set of redis slaves)

The web front end interacts with the redis master via javascript redis API calls.

### Step Zero: Prerequisites

This example requires a kubernetes cluster.  See the [Getting Started guides](../../docs/getting-started-guides) for how to get started.

If you are running from source, replace commands such as `kubectl` below with calls to `cluster/kubectl.sh`.

### Step One: Fire up the redis master

Note: This redis-master is *not* highly available.  Making it highly available would be a very interesting, but intricate exercise - redis doesn't actually support multi-master deployments at the time of this writing, so high availability would be a somewhat tricky thing to implement, and might involve periodic serialization to disk, and so on.

Use (or just create) the file `examples/guestbook/redis-master-controller.json` which describes a single pod running a redis key-value server in a container:

Note that, although the redis server runs just with a single replica, we use replication controller to enforce that exactly one pod keeps running (e.g. in a event of node going down, the replication controller will ensure that the redis master gets restarted on a healthy node).   This could result in data loss.

**These json files are for v1beta1.  See the [v1beta3/](v1beta3/) folder for updated equivalents.**

```js
{
  "id": "redis-master-controller",
  "kind": "ReplicationController",
  "apiVersion": "v1beta1",
  "desiredState": {
    "replicas": 1,
    "replicaSelector": {"name": "redis-master"},
    "podTemplate": {
      "desiredState": {
        "manifest": {
          "version": "v1beta1",
          "id": "redis-master",
          "containers": [{
            "name": "redis-master",
            "image": "dockerfile/redis",
            "ports": [{
              "containerPort": 6379,   # containerPort: Where traffic to redis ultimately is routed to.
            }]
          }]
        }
      },
      "labels": {
        "name": "redis-master",
        "app": "redis"
      }
    }
  },
  "labels": {
    "name": "redis-master" # This label needed for when we start our redis-master service.
  }
}
```

Now, create the redis pod in your Kubernetes cluster by running:

```shell
$ kubectl create -f examples/guestbook/redis-master-controller.json

$ cluster/kubectl.sh get rc
CONTROLLER                             CONTAINER(S)            IMAGE(S)                                 SELECTOR                     REPLICAS
redis-master-controller                redis-master            dockerfile/redis                         name=redis-master            1
```

Once that's up you can list the pods in the cluster, to verify that the master is running:

```shell
$ kubectl get pods
```

You'll see all kubernetes components, most importantly the redis master pod. It will also display the machine that the pod is running on once it gets placed (may take up to thirty seconds):

```shell
POD                                          IP                  CONTAINER(S)            IMAGE(S)                                 HOST                                                              LABELS                                                     STATUS
redis-master-controller-gb50a                10.244.3.7          redis-master            dockerfile/redis                         kubernetes-minion-7agi.c.hazel-mote-834.internal/104.154.54.203   app=redis,name=redis-master                                Running
```

If you ssh to that machine, you can run `docker ps` to see the actual pod:

```shell
me@workstation$ gcloud compute ssh kubernetes-minion-7agi

me@kubernetes-minion-7agi:~$ sudo docker ps
CONTAINER ID        IMAGE                                  COMMAND                CREATED              STATUS              PORTS                    NAMES
0ffef9649265        dockerfile/redis:latest                "redis-server /etc/r   About a minute ago   Up About a minute                            k8s_redis-master.767aef46_redis-master-controller-gb50a.default.api_4530d7b3-ae5d-11e4-bf77-42010af0d719_579ee964
```

(Note that initial `docker pull` may take a few minutes, depending on network conditions.  You can monitor the status of this by running `journalctl -f -u docker` to check when the image is being downloaded.  Of course, you can also run `journalctl -f -u kubelet` to see what state the kubelet is in as well during this time.

### Step Two: Fire up the master service
A Kubernetes 'service' is a named load balancer that proxies traffic to *one or more* containers. This is done using the *labels* metadata which we defined in the redis-master pod above.  As mentioned, in redis there is only one master, but we nevertheless still want to create a service for it.  Why?  Because it gives us a deterministic way to route to the single master using an elastic IP.

The services in a Kubernetes cluster are discoverable inside other containers via environment variables. 

Services find the containers to load balance based on pod labels.

The pod that you created in Step One has the label `name=redis-master`. The selector field of the service determines *which pods will receive the traffic* sent to the service, and the port and containerPort (targetPort in v1beta3 and higher APIs) information defines what port the service proxy will run at. 

Use the file `examples/guestbook/redis-master-service.json`:

```js
{
  "id": "redis-master",
  "kind": "Service",
  "apiVersion": "v1beta1",
  "port": 6379,
  "containerPort": 6379,
  "selector": {
    "name": "redis-master"
  },
  "labels": {
    "name": "redis-master"
  }
}
```

to create the service by running:

```shell
$ kubectl create -f examples/guestbook/redis-master-service.json
redis-master

$ kubectl get services
NAME                    LABELS                                    SELECTOR                     IP                  PORT
redis-master            name=redis-master                         name=redis-master            10.0.246.242        6379
```

This will cause all pods to see the redis master apparently running on <ip>:6379.  The traffic flow from slaves to masters can be described in two steps, like so.

- A *redis slave* will connect to "port" on the *redis master service*
- Traffic will be forwarded from the service "port" (on the service node) to the  *containerPort* (targetPort in v1beta3 and higher APIs) on the pod which (a node the service listens to). 

Thus, once created, the service proxy on each minion is configured to set up a proxy on the specified port (in this case port 6379).

### Step Three: Fire up the replicated slave pods
Although the redis master is a single pod, the redis read slaves are a 'replicated' pod. In Kubernetes, a replication controller is responsible for managing multiple instances of a replicated pod.  The replicationController will automatically launch new Pods if the number of replicas falls (this is quite easy - and fun - to test, just kill the docker processes for your pods at will and watch them come back online on a new node shortly thereafter).

Use the file `examples/guestbook/redis-slave-controller.json`, which looks like this:

```js
{
  "id": "redis-slave-controller",
  "kind": "ReplicationController",
  "apiVersion": "v1beta1",
  "desiredState": {
    "replicas": 2,
    "replicaSelector": {"name": "redis-slave"},
    "podTemplate": {
      "desiredState": {
         "manifest": {
           "version": "v1beta1",
           "id": "redis-slave",
           "containers": [{
             "name": "redis-slave",
             "image": "kubernetes/redis-slave:v2",
             "ports": [{"containerPort": 6379}]
           }]
         }
      },
      "labels": {
        "name": "redis-slave",
        "uses": "redis-master",
        "app": "redis"
      }
    }
  },
  "labels": {"name": "redis-slave"}
}
```

to create the replication controller by running:

```shell
$ kubectl create -f examples/guestbook/redis-slave-controller.json
redis-slave-controller

$ kubectl get rc
CONTROLLER                             CONTAINER(S)            IMAGE(S)                                 SELECTOR                     REPLICAS
redis-master-controller                redis-master            dockerfile/redis                         name=redis-master            1
redis-slave-controller                 redis-slave             kubernetes/redis-slave:v2                name=redis-slave             2
```

The redis slave is started with the following command:

```shell
redis-server --slaveof redis-master 6379
```

Once that's up you can list the pods in the cluster, to verify that the master and slaves are running:

```shell
$ kubectl get pods
POD                                          IP                  CONTAINER(S)            IMAGE(S)                                 HOST                                                              LABELS                                                     STATUS
redis-master-controller-gb50a                10.244.3.7          redis-master            dockerfile/redis                         kubernetes-minion-7agi.c.hazel-mote-834.internal/104.154.54.203   app=redis,name=redis-master                                Running
redis-slave-controller-182tv                 10.244.3.6          redis-slave             kubernetes/redis-slave:v2                kubernetes-minion-7agi.c.hazel-mote-834.internal/104.154.54.203   app=redis,name=redis-slave,uses=redis-master               Running
redis-slave-controller-zwk1b                 10.244.2.8          redis-slave             kubernetes/redis-slave:v2                kubernetes-minion-3vxa.c.hazel-mote-834.internal/104.154.54.6     app=redis,name=redis-slave,uses=redis-master               Running
```

You will see a single redis master pod and two redis slave pods.

### Step Four: Create the redis slave service

Just like the master, we want to have a service to proxy connections to the read slaves. In this case, in addition to discovery, the slave service provides transparent load balancing to web app  clients. 

The service specification for the slaves is in `examples/guestbook/redis-slave-service.json`:

```js
{
  "id": "redis-slave",
  "kind": "Service",
  "apiVersion": "v1beta1",
  "port": 6379,
  "containerPort": 6379,
  "labels": {
    "name": "redis-slave"
  },
  "selector": {
    "name": "redis-slave"
  }
}
```

This time the selector for the service is `name=redis-slave`, because that identifies the pods running redis slaves. It may also be helpful to set labels on your service itself as we've done here to make it easy to locate them with the `cluster/kubectl.sh get services -l "label=value"` command.

Now that you have created the service specification, create it in your cluster by running:

```shell
$ kubectl create -f examples/guestbook/redis-slave-service.json
redis-slave

$ kubectl get services
NAME                    LABELS                                    SELECTOR                     IP                  PORT
redis-master            name=redis-master                         name=redis-master            10.0.246.242        6379
redis-slave             name=redis-slave                          name=redis-slave             10.0.72.62          6379
```

### Step Five: Create the frontend pod

This is a simple PHP server that is configured to talk to either the slave or master services depending on whether the request is a read or a write. It exposes a simple AJAX interface, and serves an angular-based UX. Like the redis read slaves it is a replicated service instantiated by a replication controller.

It can now leverage writes to the load balancing redis-slaves, which can be highly replicated.

The pod is described in the file `examples/guestbook/frontend-controller.json`:

```js
{
  "id": "frontend-controller",
  "kind": "ReplicationController",
  "apiVersion": "v1beta1",
  "desiredState": {
    "replicas": 3,
    "replicaSelector": {"name": "frontend"},
    "podTemplate": {
      "desiredState": {
         "manifest": {
           "version": "v1beta1",
           "id": "frontend",
           "containers": [{
             "name": "php-redis",
             "image": "kubernetes/example-guestbook-php-redis:v2",
             "ports": [{"name": "http-server", "containerPort": 80}]
           }]
         }
       },
       "labels": {
         "name": "frontend",
         "uses": "redis-slave-or-redis-master",
         "app": "frontend"
       }
      }},
  "labels": {"name": "frontend"}
}
```

Using this file, you can turn up your frontend with:

```shell
$ kubectl create -f examples/guestbook/frontend-controller.json
frontend-controller

$ kubectl get rc
CONTROLLER                             CONTAINER(S)            IMAGE(S)                                   SELECTOR                     REPLICAS
frontend-controller                    php-redis               kubernetes/example-guestbook-php-redis:v2  name=frontend                3
redis-master-controller                redis-master            dockerfile/redis                           name=redis-master            1
redis-slave-controller                 redis-slave             kubernetes/redis-slave:v2                  name=redis-slave             2
```

Once that's up (it may take ten to thirty seconds to create the pods) you can list the pods in the cluster, to verify that the master, slaves and frontends are running:

```shell
$ kubectl get pods
POD                                          IP                  CONTAINER(S)            IMAGE(S)                                   HOST                                                              LABELS                                                     STATUS
frontend-controller-5m1zc                    10.244.1.131        php-redis               kubernetes/example-guestbook-php-redis:v2  kubernetes-minion-3vxa.c.hazel-mote-834.internal/146.148.71.71    app=frontend,name=frontend,uses=redis-slave,redis-master   Running
frontend-controller-ckn42                    10.244.2.134        php-redis               kubernetes/example-guestbook-php-redis:v2  kubernetes-minion-by92.c.hazel-mote-834.internal/104.154.54.6     app=frontend,name=frontend,uses=redis-slave,redis-master   Running
frontend-controller-v5drx                    10.244.0.128        php-redis               kubernetes/example-guestbook-php-redis:v2  kubernetes-minion-wilb.c.hazel-mote-834.internal/23.236.61.63     app=frontend,name=frontend,uses=redis-slave,redis-master   Running
redis-master-controller-gb50a                10.244.3.7          redis-master            dockerfile/redis                           kubernetes-minion-7agi.c.hazel-mote-834.internal/104.154.54.203   app=redis,name=redis-master                                Running
redis-slave-controller-182tv                 10.244.3.6          redis-slave             kubernetes/redis-slave:v2                  kubernetes-minion-7agi.c.hazel-mote-834.internal/104.154.54.203   app=redis,name=redis-slave,uses=redis-master               Running
redis-slave-controller-zwk1b                 10.244.2.8          redis-slave             kubernetes/redis-slave:v2                  kubernetes-minion-3vxa.c.hazel-mote-834.internal/104.154.54.6     app=redis,name=redis-slave,uses=redis-master               Running
```

You will see a single redis master pod, two redis slaves, and three frontend pods.

The code for the PHP service looks like this:

```php
<?

set_include_path('.:/usr/share/php:/usr/share/pear:/vendor/predis');

error_reporting(E_ALL);
ini_set('display_errors', 1);

require 'predis/autoload.php';

if (isset($_GET['cmd']) === true) {
  header('Content-Type: application/json');
  if ($_GET['cmd'] == 'set') {
    $client = new Predis\Client([
      'scheme' => 'tcp',
      'host'   => 'redis-master',
      'port'   => 6379,
    ]);
    
    $client->set($_GET['key'], $_GET['value']);
    print('{"message": "Updated"}');
  } else {
    $client = new Predis\Client([
      'scheme' => 'tcp',
      'host'   => 'redis-slave',
      'port'   => 6379,
    ]);

    $value = $client->get($_GET['key']);
    print('{"data": "' . $value . '"}');
  }
} else {
  phpinfo();
} ?>
```

### Step Six: Create the guestbook service.

Just like the others, you want a service to group your frontend pods.
The service is described in the file `examples/guestbook/frontend-service.json`:

**NOTE** This json snippet has been modified, in that it adds the publicIPs field for illustration purposes only.

```js
{
  "id": "frontend",
  "kind": "Service",
  "apiVersion": "v1beta1",
  "port": 8000,
  "containerPort": "http-server",
  "publicIPs":["10.11.22.33"],
  "selector": {
    "name": "frontend"
  },
  "labels": {
    "name": "frontend"
  },
  "createExternalLoadBalancer": true
}
```

If running a single node local setup, or single VM, you don't need `createExternalLoadBalancer`, nor do you need `publicIPs`.
Read the *Accessing the guestbook site externally* section below for details and set 10.11.22.33 accordingly (for now, you can 
delete these parameters or run this - either way it won't hurt anything to have both parameters the way they are).

```shell
$ kubectl create -f examples/guestbook/frontend-service.json
frontend

$ kubectl get services
NAME                    LABELS                                    SELECTOR                     IP                  PORT
frontend                name=frontend                             name=frontend                10.0.93.211         8000
redis-master            name=redis-master                         name=redis-master            10.0.246.242        6379
redis-slave             name=redis-slave                          name=redis-slave             10.0.72.62          6379
```

### A few Google Container Engine specifics for playing around with the services.

In GCE, `cluster/kubectl.sh` automatically creates forwarding rule for services with `createExternalLoadBalancer`.

```shell
$ gcloud compute forwarding-rules list
NAME                  REGION      IP_ADDRESS     IP_PROTOCOL TARGET
frontend              us-central1 130.211.188.51 TCP         us-central1/targetPools/frontend
```

You can grab the external IP of the load balancer associated with that rule and visit `http://130.211.188.51:8000`.

In GCE, you also may need to open the firewall for port 8000 using the [console][cloud-console] or the `gcloud` tool. The following command will allow traffic from any source to instances tagged `kubernetes-minion`:

```shell
$ gcloud compute firewall-rules create --allow=tcp:8000 --target-tags=kubernetes-minion kubernetes-minion-8000
```

For GCE details about limiting traffic to specific sources, see the [GCE firewall documentation][gce-firewall-docs].

[cloud-console]: https://console.developer.google.com
[gce-firewall-docs]: https://cloud.google.com/compute/docs/networking#firewalls

### Accessing the guestbook site externally

The pods that we have set up are reachable through the frontend service, but you'll notice that 10.0.93.211 (the IP of the frontend service) is unavailable from outside of kubernetes. 
Of course, if you are running kubernetes minions locally, this isn't such a big problem - the port binding will allow you to reach the guestbook website at localhost:8000... but the beloved **localhost** solution obviously doesn't work in any real world scenario.

Unless you have access to the `createExternalLoadBalancer` feature (cloud provider specific), you will want to set up a **publicIP on a minion**, so that the service can be accessed from outside of the internal kubernetes network. This is quite easy.  You simply look at you're list of kubelet IP addresses, and update the service file to include a `publicIPs` string, which is mapped to an IP address of any number of your existing kubelets.  This will allow all you're kubelets to act as external entry points to the service (translation: this will allow you to browse the guestbook site at your kubelet IP address from your browser).

If you are more advanced in the ops arena, note you can manually get the service IP from looking at the output of `kubectl get pods,services`, and modify your firewall using standard tools and services (firewalld, iptables, selinux) which you are already familar with.

And of course, finally, if you are running Kubernetes locally, you can just visit http://localhost:8000.

### Step Seven: Cleanup

To turn down a Kubernetes cluster, if you ran this from source, you can use

```shell
$ cluster/kube-down.sh
```

If you are in a live kubernetes cluster, you can just kill the pods, using a script such as this (obviously, read through it and make sure you understand it before running it blindly, as it will kill several pods automatically for you).

```shell
### First, kill services and controllers.
kubectl stop -f examples/guestbook/redis-slave-controller.json
kubectl stop -f examples/guestbook/frontend-controller.json
kubectl delete -f examples/guestbook/redis-master-service.json
kubectl delete -f examples/guestbook/redis-slave-service.json
kubectl delete pod redis-master # This is the only pod that requires manual removal.
```

### Troubleshooting

the Guestbook example can fail for a variety of reasons, which makes it an effective test.  Lets test the web app simply using *curl*, so we can see whats going on.

Before we proceed, what are some setup idiosyncracies that might cause the app to fail (or, appear to fail, when merely you have a *cold start* issue.

- running kubernetes from HEAD, in which case, there may be subtle bugs in the kubernetes core component interactions.
- running kubernetes with security turned on, in such a way that containers are restricted from doing their job.
- starting the kubernetes and not allowing enough time for all services and pods to come online, before doing testing.



To post a message (Note that this call *overwrites* the messages field), so it will be reset to just one entry.

```
curl "localhost:8000/index.php?cmd=set&key=messages&value=jay_sais_hi"
```

And, to get messages afterwards...

```
curl "localhost:8000/index.php?cmd=get&key=messages"
```

1) When the *Web page hasn't come up yet*:

When you go to localhost:8000, you might not see the page at all.  Testing it with curl...
```shell
   ==> default: curl: (56) Recv failure: Connection reset by peer
```
This means the web frontend isn't up yet. Specifically, the  "reset by peer" message is occuring because you are trying to access the *right port*, but *nothing is bound* to that port yet. Wait a while, possibly about 2 minutes or more, depending on your set up. Also, run a *watch* on docker ps, to see if containers are cycling on and off or not starting.

```watch 
$> watch -n 1 docker ps
```

If you run this on a node to which the frontend is assigned, you will eventually see the frontend container turns on.  At that point, this basic error will likely go away.

2) *Temporarily, while waiting for the app to come up* , you might see a few of these:

```shell
==> default: <br />
==> default: <b>Fatal error</b>:  Uncaught exception 'Predis\Connection\ConnectionException' with message 'Error while reading line from the server [tcp://10.254.168.69:6379]' in /vendor/predis/predis/lib/Predis/Connection/AbstractConnection.php:141
```

The fix, just go get some coffee.  When you come back, there is a good chance the service endpoint will eventually be up.  If not, make sure its running and that the redis master / slave docker logs show something like this.

```shell
$> docker logs 26af6bd5ac12
...
[9] 20 Feb 23:47:51.015 # WARNING: The TCP backlog setting of 511 cannot be enforced because /proc/sys/net/core/somaxconn is set to the lower value of 128.
[9] 20 Feb 23:47:51.015 * The server is now ready to accept connections on port 6379
[9] 20 Feb 23:47:52.005 * Connecting to MASTER 10.254.168.69:6379
[9] 20 Feb 23:47:52.005 * MASTER <-> SLAVE sync started
```

3) *When security issues cause redis writes to fail* you may have to run *docker logs* on the redis containers:

```shell
==> default: <b>Fatal error</b>:  Uncaught exception 'Predis\ServerException' with message 'MISCONF Redis is configured to save RDB snapshots, but is currently not able to persist on disk. Commands that may modify the data set are disabled. Please check Redis logs for details about the error.' in /vendor/predis/predis/lib/Predis/Client.php:282" 
```
The fix is to setup SE Linux properly (don't just turn it off).  Remember that you can also rebuild this entire app from scratch, using the dockerfiles, and modify while redeploying.  Reach out on the mailing list if you need help doing so!
