#!/bin/bash

set -e
# All in one scipt following this document: 'https://docs.openstack.org/openstack-helm/latest/install/index.html'

# Custom console log
GREEN='\033[0;32m'
# ANSI escape code to reset text color to default
RESET='\033[0m'
console_log() {
  echo -e "${GREEN}>>> [Openstack] [Setup] $1${RESET}"
}

format_and_execute() {
  echo "Working on $1"
  script_path=$1
  sed -i -e 's/\r$//' $script_path
  "${script_path}"
}

check_dos2unix() {
  # Check if dos2unix is installed
  if ! command -v dos2unix &>/dev/null; then
    echo "dos2unix is not installed. Attempting to install..."

    # Check the package manager and install dos2unix
    if command -v apt-get &>/dev/null; then
      sudo apt-get update
      sudo apt-get install dos2unix -y
    elif command -v yum &>/dev/null; then
      sudo yum install dos2unix -y
    elif command -v brew &>/dev/null; then
      brew install dos2unix
    else
      echo "Unable to install dos2unix. Please install it manually."
      exit 1
    fi
  fi
}

format_all_files() {
  folder=$1
  check_dos2unix
  cd $folder
  find ./tools/deployment -type f -exec dos2unix {} \;
}

DEPLOYMENT_DIR="/tmp/osh"
console_log "Before deployment"
mkdir -p $DEPLOYMENT_DIR

console_log "Cleanup environment"
rm -rf "$DEPLOYMENT_DIR/openstack-helm/"
rm -rf "$DEPLOYMENT_DIR/openstack-helm-infra/"
cd $DEPLOYMENT_DIR
git clone https://opendev.org/openstack/openstack-helm.git
git clone https://opendev.org/openstack/openstack-helm-infra.git
pwd
ls -la

console_log "Configure environment"
export OPENSTACK_RELEASE=2023.2
export CONTAINER_DISTRO_NAME=ubuntu
export CONTAINER_DISTRO_VERSION=jammy

console_log "dos2unix formatting"
format_all_files "$DEPLOYMENT_DIR/openstack-helm"
format_all_files "$DEPLOYMENT_DIR/openstack-helm-infra"

# Prepare Kubernetes
console_log "Prepare Kubernetes"
cd "$DEPLOYMENT_DIR/openstack-helm"
ls -la
pwd
format_and_execute ./tools/deployment/common/prepare-k8s.sh

# Deploy Ceph
console_log "Deploy Ceph"
cd "$DEPLOYMENT_DIR/openstack-helm-infra"
ls -la
format_and_execute ./tools/deployment/ceph/ceph-rook.sh
format_and_execute ./tools/deployment/ceph/ceph-adapter-rook.sh

#Setup OpenStack client
console_log "Setup OpenStack client"
cd "$DEPLOYMENT_DIR/openstack-helm"
format_and_execute ./tools/deployment/common/setup-client.sh

# Traffic Routing to Ceph Rados Gateway Service
console_log "Traffic Routing to Ceph Rados Gateway Service"
cd "$DEPLOYMENT_DIR/openstack-helm"
format_and_execute ./tools/deployment/component/common/ingress.sh

# Deploy OpenStack backend
console_log "Deploy OpenStack backend"
cd "$DEPLOYMENT_DIR/openstack-helm"
format_and_execute ./tools/deployment/component/common/rabbitmq.sh
format_and_execute ./tools/deployment/component/common/mariadb.sh
format_and_execute ./tools/deployment/component/common/memcached.sh

# Deploy OpenStack
# Keystone
console_log "Keystone"
cd "$DEPLOYMENT_DIR/openstack-helm"
format_and_execute ./tools/deployment/component/keystone/keystone.sh

# Heat
console_log "Heat"
cd "$DEPLOYMENT_DIR/openstack-helm"
format_and_execute ./tools/deployment/component/heat/heat.sh

# Glance
cd "$DEPLOYMENT_DIR/openstack-helm"
format_and_execute ./tools/deployment/component/glance/glance.sh

# Placement, Nova, Neutron
console_log "Placement, Nova, Neutron"
cd "$DEPLOYMENT_DIR/openstack-helm"
format_and_execute ./tools/deployment/component/compute-kit/openvswitch.sh
format_and_execute ./tools/deployment/component/compute-kit/libvirt.sh
format_and_execute ./tools/deployment/component/compute-kit/compute-kit.sh

# Cinder
console_log "Cinder"
cd "$DEPLOYMENT_DIR/openstack-helm"
format_and_execute ./tools/deployment/component/cinder/cinder.sh

console_log "Congrats!"