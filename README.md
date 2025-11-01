# k8s_Build

A zero-interaction script for building a fully featured Kubernetes cluster on Ubuntu systems. The script automatically handles all configurations and ensures both root and normal user access is properly set up.

## Versions & Components
- Kubernetes: v1.33
- Container Runtime: CRI-O v1.33
- CNI Plugin: Calico v3.30.3
- Storage Provider: Longhorn v1.10.0
- Load Balancer: MetalLB v0.15.2

## Features
- 🔒 Fully automated, non-interactive installation
- 🔑 Automatic configuration for both root and sudo user
- 🛠️ Shell-aware configuration (supports both bash and zsh)
- 🔄 Automatic MetalLB configuration (default IP range: 192.168.20.150-192.168.20.160)
- 📝 Comprehensive logging
- ⚡ Performance optimized with parallel installations where possible
- 🛡️ Secure configuration with proper permissions

## Prerequisites
- Ubuntu server (20.04 or newer)
- Functioning DNS (forward and reverse lookups)
- Root/sudo access
- Internet connectivity
- Network supporting MetalLB (Layer 2 mode)
- Minimum Resources:
  - Control Plane: 2 CPU, 4GB RAM
  - Worker Nodes: 2 CPU, $GB RAM
  - 30GB disk space on each node

## Network Requirements
- MetalLB IP range accessible from your network
- No conflicts in the default MetalLB IP range (192.168.20.150-192.168.20.160)

## CONTROL PLANE SETUP
Step 1 - Install and Configure Control Plane
```bash
git clone https://github.com/Andre-Atkinson/k8s_Build.git
cd k8s_Build
chmod +x k8_Build.sh
sudo ./k8_Build.sh --control-plane
```

## Installation Process

### Control Plane Node
```bash
git clone https://github.com/Andre-Atkinson/k8s_Build.git
cd k8s_Build
chmod +x k8_Build.sh
sudo ./k8_Build.sh --control-plane
```

The script will automatically:
1. Configure system settings (swap, modules, IP forwarding)
2. Install and configure CRI-O runtime
3. Install Kubernetes components and Helm
4. Initialize the control plane
5. Configure kubectl for both root and your user
6. Remove control plane node taint (enables pod scheduling)
7. Install and configure:
   - Calico CNI
   - Longhorn Storage
   - MetalLB Load Balancer
8. Generate and save cluster join command

### Worker Node Setup
```bash
git clone https://github.com/Andre-Atkinson/k8s_Build.git
cd k8s_Build
chmod +x k8_Build.sh
sudo ./k8_Build.sh --worker
```

After worker installation completes:
1. Copy `k8s_join_cmd.sh` from control plane's home directory to worker
2. Execute: `sudo ./k8s_join_cmd.sh`

## Post-Installation

### Verify Installation
```bash
# Check node status
kubectl get nodes

# Verify all system pods
kubectl get pods -A

# Check component status
kubectl get pods -n metallb-system    # Load Balancer
kubectl get pods -n longhorn-system   # Storage
kubectl get pods -n calico-system     # Networking
```

## Customization

### MetalLB Configuration
Edit `ADDR_RANGE` in the script to match your network:
```bash
ADDR_RANGE="192.168.20.150-192.168.20.160"
```

### Version Configuration
Modify version variables as needed:
```bash
KUBERNETES_VERSION=v1.33
CRIO_VERSION=v1.33
CALICO_VERSION=v3.30.3
LONGHORN_VERSION=v1.10.0
METALLB_VERSION=v0.15.2
```

## Troubleshooting

### Common Checks
1. Verify node status: `kubectl get nodes`
2. Check system pods: `kubectl get pods -A`
3. View logs: `kubectl logs -n <namespace> <pod-name>`

### Known Solutions
- If kubectl commands fail, source your shell config:
  ```bash
  source ~/.bashrc  # for bash
  source ~/.zshrc   # for zsh
  ```
- If pods are stuck in pending, check:
  ```bash
  kubectl describe pod <pod-name> -n <namespace>
  ```

## Security Notes
- The script automatically sets secure permissions (600) for kubeconfig files
- MetalLB is configured in Layer 2 mode by default
- Control plane node is made schedulable for single-node clusters
- All components use RBAC for access control 
