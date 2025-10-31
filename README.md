# k8s_Build
This script enables building a working Kubernetes cluster on Ubuntu systems.

This script will:
- Install Kubernetes v1.33
- Configure CRI-O v1.33 as the container runtime
- Install Calico v3.30.3 for networking (on control plane)
- Install Longhorn v1.10.0 for storage (on control plane)

## Pre-Requirements
- Ubuntu server (recommended 20.04 or newer)
- Functioning DNS (both forward and reverse lookups)
- Root/sudo access
- Internet connectivity

## CONTROL PLANE NODE SETUP
Step 1 - Install and Configure Control Plane
```bash
git clone https://github.com/Andre-Atkinson/k8s_Build.git
cd k8s_Build
chmod +x k8_Build.sh
sudo ./k8_Build.sh --control-plane
```

The script will:
- Configure system settings
- Install all required packages
- Initialize the Kubernetes control plane
- Install Calico CNI and Longhorn CSI
- Set up kubectl with bash completion
- Generate the cluster join command

The join command will be automatically saved to your home directory as `~/k8s_join_cmd.sh`

## WORKER NODE SETUP
To add worker nodes to your cluster:

Step 1 - Install Required Packages
```bash
git clone https://github.com/Andre-Atkinson/k8s_Build.git
cd k8s_Build
chmod +x k8_Build.sh
sudo ./k8_Build.sh --worker
```

Step 2 - Join the Cluster
1. Copy the `k8s_join_cmd.sh` file from your control plane node's home directory to the worker node
2. Make it executable and run it:
```bash
chmod +x k8s_join_cmd.sh
sudo ./k8s_join_cmd.sh
```

## Verifying the Cluster
On the control plane node, you can verify your cluster status:
```bash
kubectl get nodes
kubectl get pods -A
```

## Features
- Automated installation of all components
- CRI-O container runtime
- Calico networking
- Longhorn storage
- Helm package manager
- Bash completion for kubectl 
