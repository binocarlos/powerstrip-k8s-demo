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

echo "####################################################################"
echo "#################### Downloading kubernetes                 ########"
echo "####################################################################"

. /vagrant/kube-vars.sh

# Indicates whether the install has succeeded
export is_success=false

install_etcd() {
  ## download, extract and update etcd binaries ##
  echo 'Installing etcd on master...'
  cd $KUBERNETES_DOWNLOAD_PATH;
  sudo rm -r etcd-$ETCD_VERSION-linux-amd64 || true;
  etcd_download_url="https://github.com/coreos/etcd/releases/download/$ETCD_VERSION/etcd-$ETCD_VERSION-linux-amd64.tar.gz";
  sudo curl -sS -L $etcd_download_url -o etcd.tar.gz;
  sudo tar xzvf etcd.tar.gz && cd etcd-$ETCD_VERSION-linux-amd64;
  sudo mv -v etcd $ETCD_EXECUTABLE_LOCATION/etcd;
  sudo mv -v etcdctl $ETCD_EXECUTABLE_LOCATION/etcdctl;

  etcd_path=$(which etcd);
  if [[ -z "$etcd_path" ]]; then
    echo 'etcd not installed ...'
    return 1
  else
    echo 'etcd successfully installed ...'
    echo $etcd_path;
    etcd --version;
  fi
}

install_docker() {
  echo "installing docker .........."
  docker_path=$(which docker);
  if [[ -z "$docker_path" ]]; then
    sudo apt-get install -y linux-image-extra-`uname -r`
    sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 36A1D7869245C8950F966E92D8576A8BA88D21E9
    sudo sh -c "echo deb http://get.docker.io/ubuntu docker main > /etc/apt/sources.list.d/docker.list"
    sudo apt-get update
    sudo apt-get install -y lxc-docker
  else
    echo "Docker already installed,skipping..."
  fi
}

download_kubernetes_release() {
  ## download and extract kubernetes archive ##
  echo "Downloading kubernetes release version: $KUBERNETES_RELEASE_VERSION"

  cd $KUBERNETES_DOWNLOAD_PATH
  mkdir -p $KUBERNETES_EXTRACT_DIR
  kubernetes_download_url="https://github.com/GoogleCloudPlatform/kubernetes/releases/download/$KUBERNETES_RELEASE_VERSION/kubernetes.tar.gz";
  sudo curl -sS -L $kubernetes_download_url -o kubernetes.tar.gz;
  sudo tar xzvf kubernetes.tar.gz -C $KUBERNETES_EXTRACT_DIR;
}

extract_server_binaries() {
  ## extract the kubernetes server binaries ##
  echo "Extracting kubernetes server binaries from $KUBERNETES_DIR"
  cd $KUBERNETES_DIR/server
  sudo tar xzvf kubernetes-server-linux-amd64.tar.gz
  echo 'Successfully extracted kubernetes server binaries'
}

update_master_binaries() {
  # place binaries in correct folders
  echo "Updating kubernetes master binaries"
  cd $KUBERNETES_SERVER_BIN_DIR
  sudo cp -vr * $KUBERNETES_EXECUTABLE_LOCATION/
  echo "Successfully updated kubernetes server binaries to $KUBERNETES_EXECUTABLE_LOCATION"
  is_success=true
}

before_exit() {
  if [ "$is_success" == true ]; then
    echo "Script Completed Successfully";
  else
    echo "Script executing failed";
  fi
}

trap before_exit EXIT
install_etcd

trap before_exit EXIT
download_kubernetes_release

trap before_exit EXIT
extract_server_binaries

trap before_exit EXIT
update_master_binaries