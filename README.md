## powerstrip-k8s-demo

A demo of [powerstrip-flocker](https://github.com/clusterhq/powerstrip-flocker) and [kubernetes](https://github.com/googlecloudplatform/kubernetes) migrating a database with it's data.  The data migration is powered by [flocker](https://github.com/clusterhq/flocker) and the networking is powered by [weave](https://github.com/zettio/weave) 

## install

First you need to install:

 * [virtualbox](https://www.virtualbox.org/wiki/Downloads)
 * [vagrant](http://www.vagrantup.com/downloads.html)

## start vms

To run the demo:

```bash
$ git clone https://github.com/binocarlos/powerstrip-k8s-demo
$ cd powerstrip-k8s-demo
$ vagrant up
```

## example

The first step is to spin up the kubernetes cluster - this will start the redis pod on `node1` (the spinning node) and start 3 PHP pods across both nodes.

```bash
$ vagrant ssh master
master$ sudo bash /vagrant/demo.sh up
```

The next step is to load the app in your browser using the following address:

```
http://172.16.255.251:8000
```

Make a couple of entries into the guestbook.

Now - we will migrate the redis server:

```bash
master$ sudo bash /vagrant/demo.sh shift
```

This will have stopped the original redis server, moved the data onto the other server and then started the redis server.

You can confirm the redis server has moved by using this command:

```bash
master$ sudo kubectl get pods
```

Notice how the `redis-master` pod is running on `node2` (the ssd drive).

Now reload the app in your browser (`http://172.16.255.251:8000`) - notice how the original data you created is still there!

This demonstrates how we can use [kubernetes](https://github.com/googlecloudplatform/kubernetes) and [flocker](https://github.com/clusterhq/flocker) to migrate a database container AND its data.

## overview

The demo is the classic kubernetes `guestbook` app that uses PHP and Redis.

There is a single Redis pod and 3 PHP pods (managed by a replication controller).

We have labeled the 2 minions `spinning` and `ssd` to represent the types of disk they have.

The idea is that we target the redis server onto the `spinning` node to start with.  We then create some data on that node.  Finally, we migrate the redis container and the data we created to the `ssd` node.

This represents a real world migration where we realise that our database server needs a faster disk.