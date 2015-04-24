#!/bin/bash
vagrant up
vagrant ssh master -c "kubectl create -f /vagrant/examples/guestbook/redis-master-service.json"
vagrant ssh master -c "kubectl create -f /vagrant/examples/guestbook/frontend-service.json"
vagrant ssh master -c "kubectl create -f /vagrant/examples/guestbook/redis-master-controller.json"
vagrant ssh master -c "kubectl create -f /vagrant/examples/guestbook/frontend-controller.json"
