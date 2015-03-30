#!/bin/bash

export API_IP=${API_IP:=10.255.0.10}
export SERVER_IP=${SERVER_IP:=10.255.0.11}
export DOCKER_HOST=${DOCKER_HOST:=tcp://127.0.0.1:2375}
export TEST_MODE=${TEST_MODE:=}
export NODE1_IP=${NODE1_IP:=172.16.255.251}
export NODE2_IP=${NODE2_IP:=172.16.255.252}

cmd-start-api() {
  local disktype="$1";

  if [[ -z $disktype ]]; then
    >&2 echo "disktype must be passed to start-api"
    exit 1
  fi
  local dockerruncmd="";
  read -d '' dockerruncmd << EOF
docker run -d \
  --hostname $disktype \
  --name demo-api \
  -e constraint:storage==$disktype \
  -e WEAVE_CIDR=$API_IP/24 \
  -v /flocker/data1:/tmp \
  binocarlos/multi-http-demo-api:latest
EOF

  echo $dockerruncmd;
  eval $dockerruncmd;
}

cmd-stop-api() {
  read -d '' dockerruncmd << EOF
docker rm -f demo-api
EOF

  echo $dockerruncmd;
  eval $dockerruncmd;
}

cmd-start-server() {
  local dockerruncmd="";
  read -d '' dockerruncmd << EOF
docker run -d \
  --name demo-server \
  -e constraint:storage==disk \
  -e WEAVE_CIDR=$SERVER_IP/24 \
  -e API_IP=$API_IP \
  -p 8080:80 \
  binocarlos/multi-http-demo-server:latest
EOF
  
  echo $dockerruncmd;
  eval $dockerruncmd;
}

cmd-stop-server() {
  read -d '' dockerruncmd << EOF
docker rm -f demo-server
EOF

  echo $dockerruncmd;
  eval $dockerruncmd;
}

cmd-hit-http(){
  read -d '' curlcmd << EOF
curl -L http://$NODE1_IP:8080
EOF

  if [[ -n "$1" ]]; then
    echo $curlcmd;
  fi
  eval $curlcmd;
}

cmd-loop-http() {
  cmd-hit-http show
  cmd-hit-http
  cmd-hit-http
  cmd-hit-http
  cmd-hit-http
  cmd-hit-http
  cmd-hit-http
  cmd-hit-http
  cmd-hit-http
  cmd-hit-http
}

usage() {
cat <<EOF
Usage:
run.sh start-api
run.sh stop-api
run.sh start-server
run.sh stop-server
run.sh hit-http
run.sh loop-http
run.sh runthrough
run.sh ps
run.sh help
EOF
  exit 1
}

wait-for-key() {
  # only wait for a key when not in test mode
  if [[ -z "$TEST_MODE" ]]; then
    echo
    read -p "Press any key to continue... " -n1 -s
    echo
  fi
}

show-message() {
  # only print the messages when not in test mode
  if [[ -z "$TEST_MODE" ]]; then
    echo ""
    echo "#"
    echo "# $1"
    echo "#"
    echo ""
  fi
}

cmd-demo() {
  show-message "Starting HTTP Server On NODE1"
  cmd-start-server
  wait-for-key
  show-message "Starting Database API On NODE1 (disk)"
  cmd-start-api disk
  show-message "docker ps | grep demo-api"
  cmd-ps | grep demo-api
  show-message "Notice how the database (demo-api) is running on node1 (disk)"
  wait-for-key
  show-message "Hitting HTTP Server"
  cmd-loop-http
  show-message "We have created some state on the disk based server"
  wait-for-key
  show-message "Stop Database"
  cmd-stop-api
  wait-for-key
  show-message "Start Database on NODE2 (ssd)"
  cmd-start-api ssd
  wait-for-key
  show-message "docker ps | grep demo-api"
  cmd-ps | grep demo-api
  show-message "Notice how the database (demo-api) is now running on node2 (ssd)"
  wait-for-key
  show-message "Hitting HTTP Server"
  cmd-loop-http
  show-message "The state and the IP address have both moved to node2!"
  wait-for-key
  show-message "Closing server & api"
  cmd-stop-server
  cmd-stop-api

}

cmd-ps() {
  docker ps -a
}

cmd-info() {
  docker info
}

main() {
  case "$1" in
  start-api)             shift; cmd-start-api $@;;
  stop-api)              shift; cmd-stop-api $@;;
  start-server)          shift; cmd-start-server $@;;
  stop-server)           shift; cmd-stop-server $@;;
  hit-http)              shift; cmd-hit-http $@;;
  loop-http)             shift; cmd-loop-http $@;;
  demo)                  shift; cmd-demo $@;;
  ps)                    shift; cmd-ps $@;;
  info)                  shift; cmd-info $@;;
  *)                     usage $@;;
  esac
}

main "$@"
