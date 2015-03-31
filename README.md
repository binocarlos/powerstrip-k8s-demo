# powerstrip-k8s-demo

A demo of [powerstrip-flocker](https://github.com/clusterhq/powerstrip-flocker) and [powerstrip-weave](https://github.com/binocarlos/powerstrip-weave) working with [kubernetes](https://github.com/googlecloudplatform/kubernetes)

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

## automated example

We have included a script that will run through each of the commands shown above.  To run the script, run the following commnads:

```bash
$ vagrant ssh master
master$ sudo bash /vagrant/run.sh demo
```
