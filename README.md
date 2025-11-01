# k8s_Build
This script enables building a fully featured Kubernetes cluster on Ubuntu systems.

This script will:
- Install Kubernetes v1.33
- Configure CRI-O v1.33 as the container runtime
- Install Calico v3.30.3 for networking (on control plane)
- Install Longhorn v1.10.0 for storage (on control plane)
- Install MetalLB v0.15.2 for load balancing (on control plane)
- Configure IP address pool for MetalLB (default: 192.168.20.150-192.168.20.160)

## Pre-Requirements
- Ubuntu server (recommended 20.04 or newer)
- Functioning DNS (both forward and reverse lookups)
- Root/sudo access
- Internet connectivity
- Network supporting MetalLB (Layer 2 mode)

## CONTROL PLANE NODE SETUP
Step 1 - Install and Configure Control Plane
```bash
git clone https://github.com/Andre-Atkinson/k8s_Build.git
cd k8s_Build
chmod +x k8_Build.sh
sudo ./k8_Build.sh --control-plane
```

The script will:
1. Configure system settings (swap, modules, IP forwarding)
2. Install all required packages and repositories
3. Initialize the Kubernetes control plane
4. Remove control plane node taint (allows pod scheduling on control plane)
5. Install and configure:
   - Calico CNI for networking
   - Longhorn CSI for persistent storage
   - MetalLB for load balancing
6. Set up kubectl with bash completion
7. Generate the cluster join command

The join command will be automatically saved to your home directory as `~/k8s_join_cmd.sh`

Note: The script includes appropriate pauses between steps to ensure proper initialization of components.

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
kubectl get nodes                # Check node status
kubectl get pods -A              # Check all pods across namespaces
kubectl get pods -n metallb-system  # Verify MetalLB installation
kubectl get pods -n longhorn-system # Verify Longhorn installation
```

## Features
- Automated installation of all components
- CRI-O container runtime
- Calico networking with automatic setup
- Longhorn distributed storage system
- MetalLB load balancer with preconfigured IP pool
- Helm package manager
- Bash completion for kubectl
- Control plane scheduling enabled
- Automated pause intervals for reliable initialization
- User-friendly logging and error handling

## Customization
To modify the MetalLB IP address range, edit the `ADDR_RANGE` variable in the script before running:
```bash
ADDR_RANGE="192.168.20.150-192.168.20.160"  # Change to match your network
``` 
