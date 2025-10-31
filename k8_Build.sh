#!/bin/bash
set -e

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Error handling
handle_error() {
    log "ERROR: An error occurred on line $1"
    exit 1
}

trap 'handle_error $LINENO' ERR

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# Variables
KUBERNETES_VERSION=v1.33
CRIO_VERSION=v1.33
CALICO_VERSION=v3.30.3
LONGHORN_VERSION=v1.10.0

# Parse command line arguments
NODE_TYPE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --control-plane)
            NODE_TYPE="control-plane"
            shift
            ;;
        --worker)
            NODE_TYPE="worker"
            shift
            ;;
        *)
            echo "Unknown parameter: $1"
            exit 1
            ;;
    esac
done

# Validate parameters
if [[ -z "$NODE_TYPE" ]]; then
    echo "Error: Must specify --control-plane or --worker"
    exit 1
fi

echo "Setting up Kubernetes $KUBERNETES_VERSION node as: $NODE_TYPE"

# Step 1: System Configuration
log "Configuring system settings..."
sudo swapoff -a
log "Disabled swap"

modprobe br_netfilter
log "Enabled bridge netfilter module"

sysctl -w net.ipv4.ip_forward=1
log "Enabled IP forwarding"

# Step 2: Install Dependencies
log "Updating package lists..."
apt-get -y update

log "Upgrading system packages..."
apt-get -y upgrade

log "Installing common requirements..."
apt-get install -y software-properties-common curl gpg apt-transport-https

#Step3:
#Kuberenetes repo
curl -fsSL https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/Release.key |  gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list

# Add CRIO Repo
curl -fsSL https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/deb/ /" | tee /etc/apt/sources.list.d/cri-o.list

# Add Helm Repo
curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list

#Step4:
#Install Packages
apt-get update
apt-get install -y cri-o kubelet kubeadm kubectl helm
apt-mark hold kubelet kubeadm kubectl #Version 1.33

#Step5:
#Start CR-IO
systemctl enable crio.service
systemctl start crio.service

# Post-installation steps based on node type
if [[ "$NODE_TYPE" == "control-plane" ]]; then
    log "Initializing control plane node..."
    
    # Initialize the control plane
    kubeadm init #--pod-network-cidr=192.168.0.0/16 --kubernetes-version=$KUBERNETES_VERSION

    # Set up kubeconfig for the root user
    mkdir -p $HOME/.kube
    cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    chown $(id -u):$(id -g) $HOME/.kube/config
    source <(kubectl completion bash)
    echo "source <(kubectl completion bash)" >> ~/.bashrc
    alias k=kubectl
    complete -F __start_kubectl k

    # Install Calico CNI
    log "Installing Calico CNI..."
    kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml

    # Install Longhorn CSI
    log "Installing Longhorn CSI..."
    kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/${LONGHORN_VERSION}/deploy/longhorn.yaml

    # Generate and save the join command to user's home directory
    USER_HOME=$(eval echo ~${SUDO_USER})
    log "Generating join command and saving to ${USER_HOME}/k8s_join_cmd.sh..."
    kubeadm token create --print-join-command > "${USER_HOME}/k8s_join_cmd.sh"
    chmod +x "${USER_HOME}/k8s_join_cmd.sh"
    chown ${SUDO_USER}:${SUDO_USER} "${USER_HOME}/k8s_join_cmd.sh"

    log "Control plane initialization completed!"
    log "The cluster join command has been saved to: ${USER_HOME}/k8s_join_cmd.sh"
    log "Share this file with your worker nodes and execute it as root to join the cluster"

elif [[ "$NODE_TYPE" == "worker" ]]; then
    log "Worker node base installation completed"
    log "To join this node to your cluster:"
    log "1. Copy the k8s_join_cmd.sh file from your control plane node"
    log "2. Run the script as root: sudo ./k8s_join_cmd.sh"
fi

log "Node setup completed successfully!"
