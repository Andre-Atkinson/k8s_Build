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

# Set noninteractive frontend to avoid prompts
export DEBIAN_FRONTEND=noninteractive

##############################################
############# ONYL EDIT BELOW  ###############
##############################################
# Variables
KUBERNETES_VERSION=v1.33
CRIO_VERSION=v1.33
CALICO_VERSION=v3.30.3
LONGHORN_VERSION=v1.10.0
METALLB_VERSION=v0.15.2
NODE_NAME=$(hostname)
ADDR_RANGE="192.168.20.150-192.168.20.160"

##############################################
############# STOP EDITING HERE ##############
##############################################

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
apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade

log "Installing common requirements..."
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" software-properties-common curl gpg apt-transport-https

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
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" cri-o kubelet kubeadm kubectl helm
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

    log "Waiting 60 seconds for control plane initialization..."
    sleep 60

    # Set up kubeconfig for both root and sudo user
    # For root user
    mkdir -p /root/.kube
    cp -i /etc/kubernetes/admin.conf /root/.kube/config
    chown root:root /root/.kube/config
    
    # For the user who ran sudo
    USER_HOME=$(eval echo ~${SUDO_USER})
    mkdir -p ${USER_HOME}/.kube
    cp -i /etc/kubernetes/admin.conf ${USER_HOME}/.kube/config
    chown ${SUDO_USER}:${SUDO_USER} ${USER_HOME}/.kube/config
    
    # Setup kubectl completion and aliases for both users
    # For root
    echo "source <(kubectl completion bash)" >> /root/.bashrc
    echo "alias k=kubectl" >> /root/.bashrc
    echo "complete -F __start_kubectl k" >> /root/.bashrc
    
    # For sudo user
    echo "source <(kubectl completion bash)" >> ${USER_HOME}/.bashrc
    echo "alias k=kubectl" >> ${USER_HOME}/.bashrc
    echo "complete -F __start_kubectl k" >> ${USER_HOME}/.bashrc
    
    # Source for current session
    source <(kubectl completion bash)
    alias k=kubectl
    complete -F __start_kubectl k

    # Untaint control plane node to allow pod scheduling
    log "Removing NoSchedule taint from control plane node..."
    kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule-

    # Install Calico CNI
    log "Installing Calico CNI..."
    kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml

    log "Waiting for Calico pods to be ready..."
    kubectl wait --namespace calico-system \
        --for=condition=ready pod \
        --selector=k8s-app=calico-node \
        --timeout=300s
    
    log "Waiting for Calico kube-controllers to be ready..."
    kubectl wait --namespace calico-system \
        --for=condition=ready pod \
        --selector=k8s-app=calico-kube-controllers \
        --timeout=300s

    # Install Longhorn CSI
    log "Installing Longhorn CSI..."
    kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/${LONGHORN_VERSION}/deploy/longhorn.yaml

    log "Waiting for Longhorn pods to be ready..."
    kubectl wait --namespace longhorn-system \
        --for=condition=ready pod \
        --selector=app=longhorn-manager \
        --timeout=300s

    # Install MetalLB Loadbalancer
    log "Installing MetalLB..."
    kubectl apply -f "https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml"

    log "Waiting for MetalLB controller to be ready..."
    kubectl wait --namespace metallb-system \
        --for=condition=ready pod \
        --selector=app=metallb,component=controller \
        --timeout=300s

    log "Waiting for MetalLB speaker to be ready..."
    kubectl wait --namespace metallb-system \
        --for=condition=ready pod \
        --selector=app=metallb,component=speaker \
        --timeout=300s

    log "Configuring MetalLB IP pool..."
    kubectl apply -f - <<-EOF
        apiVersion: metallb.io/v1beta1
        kind: IPAddressPool
        metadata:
          name: first-pool
          namespace: metallb-system
        spec:
          addresses:
            - ${ADDR_RANGE}
        ---
        apiVersion: metallb.io/v1beta1
        kind: L2Advertisement
        metadata:
          name: example
          namespace: metallb-system
        spec:
          ipAddressPools:
            - first-pool
EOF

    log "Verifying complete system readiness..."
    kubectl wait --for=condition=ready pods --all --all-namespaces --timeout=300s


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
