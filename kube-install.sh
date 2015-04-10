#!/bin/bash -e
#
# Copyright 2015 Shippable Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

if [[ $# > 0 ]]; then
  if [[ "$1" == "slave" ]]; then
    export INSTALLER_TYPE=slave
  else
    export INSTALLER_TYPE=master
  fi
else
  export INSTALLER_TYPE=master
fi

echo "####################################################################"
echo "#################### Installing kubernetes $INSTALLER_TYPE #########"
echo "####################################################################"

export MASTER_IP=`cat /etc/flocker/master_address`
export SLAVE1_IP=`cat /etc/flocker/slave1_address`
export SLAVE2_IP=`cat /etc/flocker/slave2_address`

. /vagrant/box/kube-vars.sh

# Indicates whether the install has succeeded
export is_success=false

update_hosts() {
  ## Update /etc/hosts to add kube-master and kube-slave mapping ##
  echo "updating /etc/hosts to add master IP entry"
  echo "$MASTER_IP $KUBERNETES_MASTER_HOSTNAME" | sudo tee -a /etc/hosts
  echo "$SLAVE1_IP $KUBERNETES_SLAVE1_HOSTNAME" | sudo tee -a /etc/hosts
  echo "$SLAVE2_IP $KUBERNETES_SLAVE2_HOSTNAME" | sudo tee -a /etc/hosts
  cat /etc/hosts
}

update_services_config() {
  # update the config files for the services
  # util.sh file already exists in kubernetes tar at the location
  # cluster/ubuntu/util.sh
  # this script does following
  #   - copies sysV init files from initd_script/ to /etc/init.d
  #   - copies the upstart files from init_conf/ to /etc/init
  #   - copies the config files from default_scripts to /etc/default
  # 
  # Since ONLY the last defined config for a particular key is read from 
  # the file, we just add the new config(s) at the end of the respective
  # files and do not touch the original configs
  echo 'Updating kubernetes services configs'
  cd $KUBERNETES_DIR/cluster/ubuntu/
  sudo ./util.sh

  if [[ $INSTALLER_TYPE == 'master' ]]; then
    echo '######### Updating configurations for kubernetes master ############'

    echo "ETCD=$ETCD_EXECUTABLE_LOCATION/etcd" | sudo tee -a  /etc/default/etcd
    echo "ETCD_OPTS=-listen-client-urls=http://0.0.0.0:$ETCD_PORT" | sudo tee -a /etc/default/etcd
    echo "etcd config updated successfully"

    # update kube-apiserver config
    echo "KUBE_APISERVER=$KUBERNETES_EXECUTABLE_LOCATION/kube-apiserver" | sudo tee -a  /etc/default/kube-apiserver
    echo -e "KUBE_APISERVER_OPTS=\"--address=0.0.0.0 --port=8080 --etcd_servers=http://localhost:4001 --portal_net=10.1.0.0/16 --allow_privileged=true --kubelet_port=10250 --v=0 \"" | sudo tee -a /etc/default/kube-apiserver
    echo 'kube-apiserver config updated successfully'

    # update kube-controller manager config
    echo "KUBE_CONTROLLER_MANAGER=$KUBERNETES_EXECUTABLE_LOCATION/kube-controller-manager" | sudo tee -a  /etc/default/kube-controller-manager
    echo -e "KUBE_CONTROLLER_MANAGER_OPTS=\"--address=0.0.0.0 --master=127.0.0.1:8080 --machines=$KUBERNETES_SLAVE1_HOSTNAME,$KUBERNETES_SLAVE2_HOSTNAME --v=0 \"" | sudo tee -a /etc/default/kube-controller-manager
    echo "kube-controller-manager config updated successfully"


    # update kube-scheduler config
    echo "KUBE_SCHEDULER=$KUBERNETES_EXECUTABLE_LOCATION/kube-scheduler" | sudo tee -a  /etc/default/kube-scheduler
    echo -e "KUBE_SCHEDULER_OPTS=\"--address=0.0.0.0 --master=127.0.0.1:8080 --v=0 \"" | sudo tee -a /etc/default/kube-scheduler
    echo "kube-scheduler config updated successfully"
  else
    echo '######### Updating configurations for kubernetes slave ############'

    slavehostname=$(cat /etc/flocker/hostname)
    fullslavehostname="$KUBERNETES_CLUSTER_ID-$slavehostname"

    # update kubelet config
    echo "KUBELET=$KUBERNETES_EXECUTABLE_LOCATION/kubelet" | sudo tee -a /etc/default/kubelet
    echo "KUBELET_OPTS=\"--address=0.0.0.0 --port=10250 --hostname_override=$fullslavehostname --api_servers=http://$KUBERNETES_MASTER_HOSTNAME:8080 --etcd_servers=http://$KUBERNETES_MASTER_HOSTNAME:4001 --enable_server=true --logtostderr=true --v=0\"" | sudo tee -a /etc/default/kubelet
    echo "kubelet config updated successfully"

    # update kube-proxy config
    echo "KUBE_PROXY=$KUBERNETES_EXECUTABLE_LOCATION/kube-proxy" | sudo tee -a  /etc/default/kube-proxy
    echo -e "KUBE_PROXY_OPTS=\"--etcd_servers=http://$KUBERNETES_MASTER_HOSTNAME:4001 --master=http://$KUBERNETES_MASTER_HOSTNAME:8080 --logtostderr=true \"" | sudo tee -a /etc/default/kube-proxy
    echo "kube-proxy config updated successfully"
  fi
}

remove_redundant_config() {
  # remove the config files for redundant services so that they 
  # dont boot up if server restarts
  if [[ $INSTALLER_TYPE == 'master' ]]; then
    echo 'removing redundant service configs for master ...'

    # removing from /etc/init
    sudo rm -rf /etc/init/kubelet.conf || true
    sudo rm -rf /etc/init/kube-proxy.conf || true

    # removing from /etc/init.d
    sudo rm -rf /etc/init.d/kubelet || true
    sudo rm -rf /etc/init.d/kube-proxy || true

    # removing config from /etc/default
    sudo rm -rf /etc/default/kubelet || true
    sudo rm -rf /etc/default/kube-proxy || true
  else
    echo 'removing redundant service configs for master...'

    # removing from /etc/init
    sudo rm -rf /etc/init/kube-apiserver.conf || true
    sudo rm -rf /etc/init/kube-controller-manager.conf || true
    sudo rm -rf /etc/init/kube-scheduler.conf || true

    # removing from /etc/init.d
    sudo rm -rf /etc/init.d/kube-apiserver || true
    sudo rm -rf /etc/init.d/kube-controller-manager || true
    sudo rm -rf /etc/init.d/kube-scheduler || true

    # removing from /etc/default
    sudo rm -rf /etc/default/kube-apiserver || true
    sudo rm -rf /etc/default/kube-controller-manager || true
    sudo rm -rf /etc/default/kube-scheduler || true
  fi
}

stop_services() {
  # stop any existing services
  if [[ $INSTALLER_TYPE == 'master' ]]; then
    echo 'Stopping master services...'
    sudo service etcd stop || true
    sudo service kube-apiserver stop || true
    sudo service kube-controller-manager stop || true
    sudo service kube-scheduler stop || true
  else
    echo 'Stopping slave services...'
    sudo service kubelet stop || true
    sudo service kube-proxy stop || true
  fi
}

start_services() {
  if [[ $INSTALLER_TYPE == 'master' ]]; then
    echo 'Starting slave services...'
    sudo service etcd start
    ## No need to start kube-apiserver, kube-controller-manager and kube-scheduler
    ## because the upstart scripts boot them up when etcd starts
  else
    echo 'Starting slave services...'
    sudo service kubelet start
    sudo service kube-proxy start
  fi
}

check_service_status() {
  if [[ $INSTALLER_TYPE == 'master' ]]; then
    sudo service etcd status
    sudo service kube-apiserver status
    sudo service kube-controller-manager status
    sudo service kube-scheduler status

    echo 'install of kube-master successful'
    is_success=true
  else
    echo 'Checking slave services status...'
    sudo service kubelet status
    sudo service kube-proxy status

    echo 'install of kube-slave successful'
    is_success=true
  fi
}

before_exit() {
  if [ "$is_success" == true ]; then
    echo "Script Completed Successfully";
  else
    echo "Script executing failed";
  fi
}

trap before_exit EXIT
update_hosts

trap before_exit EXIT
stop_services

trap before_exit EXIT
update_services_config

trap before_exit EXIT
remove_redundant_config

trap before_exit EXIT
start_services

trap before_exit EXIT
check_service_status

echo "Kubernetes $INSTALLER_TYPE install completed"