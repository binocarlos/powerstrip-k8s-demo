#!/bin/bash

# Make sure only root can run our script
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

export BRIDGE_ADDRESS=`cat /etc/flocker/bridge_address`
export BREAKOUT_ADDRESS=`cat /etc/flocker/breakout_address`

# install swarm on the master
# the actual boot command for the powerstrip-weave adapter
# we run without -d so that process manager can manage the process properly
cmd-swarm() {
  . /srv/powerstrip-base-install/ubuntu/lib.sh
  powerstrip-base-install-stop-container swarm
  DOCKER_HOST="unix:///var/run/docker.real.sock" \
  docker run --name swarm \
    -p 2375:2375 \
    swarm manage -H 0.0.0.0:2375 `cat /etc/flocker/swarmips`
}


# install the tcp tunnel on the minions
# wait for the powerstrip container to start because it will produce the docker.sock
cmd-tcptunnel() {
  . /srv/powerstrip-base-install/ubuntu/lib.sh
  powerstrip-base-install-wait-for-container powerstrip
  socat TCP-LISTEN:2375,reuseaddr,fork UNIX-CLIENT:/var/run/docker.sock
}

# a local way of writing a supervisor script
write-service() {
  local service="$1";

  cat << EOF > /etc/supervisor/conf.d/$service.conf
[program:$service]
command=bash /srv/install.sh $service
EOF
}

# a local way to start the services which calls the copied out version of this script
# this is because /vagrant is not mounted until later in the boot process
activate-service() {
  bash /srv/powerstrip-base-install/ubuntu/install.sh service $1
}

# here we are preparing the system for weave based k8s
install-weave() {
  mkdir -p /opt/bin/
  curl \
    --silent \
    --location \
    https://github.com/zettio/weave/releases/download/latest_release/weave \
    --output /opt/bin/weave
  curl \
    --silent \
    --location \
    https://raw.github.com/errordeveloper/weave-demos/master/poseidon/weave-helper \
    --output /opt/bin/weave-helper
  chmod +x /opt/bin/weave
  chmod +x /opt/bin/weave-helper
  /opt/bin/weave create-bridge
  ip addr add dev weave $BRIDGE_ADDRESS
  ip route add $BREAKOUT_ADDRESS dev weave scope link
  ip route add 224.0.0.0/4 dev weave
}

# basic setup such as copy this script to /srv
init() {
  cp -f /vagrant/install.sh /srv/install.sh

  apt-get remove -y puppet
  apt-get remove -y chef

  # pull any updates we have made to the powerstrip-base-install script
  cd /srv/powerstrip-base-install && git pull
  echo "copying keys to /root/.ssh"
  cp /vagrant/insecure_private_key /root/.ssh/id_rsa
  chmod 600 /root/.ssh/id_rsa
  chown root:root /root/.ssh/id_rsa
  cat /vagrant/insecure_public_key >> /root/.ssh/authorized_keys

  # include functions from the powerstrip lib
  . /srv/powerstrip-base-install/ubuntu/lib.sh

  # install / configure the weave bridge
  install-weave

  powerstrip-base-install-configure-docker --bridge="weave" $@

  sleep 2
}

# here we build ontop of powerstrip-base-install and get swarm working on top
# the master expects the file /etc/flocker/swarm_addresses to be present
cmd-master() {

  # init copies the SSH keys and copies this script so it can be referenced by the supervisor scripts
  init $@

  # pull master images
  #bash /srv/powerstrip-base-install/ubuntu/install.sh pullimages master
  #powerstrip-base-install-pullimage swarm

  # get the control + swarm to work
  activate-service flocker-control
  #write-service swarm

  # start services
  supervisorctl reload

  bash /vagrant/kube-install.sh master
}

# /etc/flocker/my_address
# /etc/flocker/master_address - master address
cmd-minion() {

  # init copies the SSH keys and copies this script so it can be referenced by the supervisor scripts
  init $@

  # pull minion images
  #powerstrip-base-install-pullimage ubuntu:latest
  #bash /srv/powerstrip-base-install/ubuntu/install.sh pullimages minion
  #powerstrip-base-install-pullimage binocarlos/multi-http-demo-api
  #powerstrip-base-install-pullimage binocarlos/multi-http-demo-server

  # get the flocker / weave / powerstrip services to work
  activate-service flocker-zfs-agent
  activate-service powerstrip-flocker
  activate-service powerstrip-weave
  activate-service powerstrip
  #write-service tcptunnel

  # start services
  supervisorctl reload

  echo 2000 > /proc/sys/net/ipv4/neigh/default/base_reachable_time_ms

  bash /vagrant/kube-install.sh slave
}

cmd-weave() {
  DOCKER_HOST="unix:///var/run/docker.real.sock" \
  docker run -ti --rm \
    -e DOCKER_SOCKET="/var/run/docker.real.sock" \
    -v /var/run/docker.real.sock:/var/run/docker.sock \
    binocarlos/powerstrip-weave $@
}

usage() {
cat <<EOF
Usage:
install.sh master
install.sh minion
install.sh tcptunnel
install.sh swarm
install.sh weave
install.sh help
EOF
  exit 1
}

main() {
  case "$1" in
  master)                   shift; cmd-master $@;;
  minion)                   shift; cmd-minion $@;;
  tcptunnel)                shift; cmd-tcptunnel $@;;
  swarm)                    shift; cmd-swarm $@;;
  weave)                    shift; cmd-weave $@;;
  *)                        usage $@;;
  esac
}

main "$@"