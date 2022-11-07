#!/bin/bash
#################################
#set variables
##IP Address of your ControlPlane
CPIP=192.168.20.60
## Name of your ControlPlane server (Match DNS, eg kube-1.lab.local)
CPNAME=kmaster
## POD NETWORK SUBNET (this is a /16 but you do not need specify a CIDR as part of the variable)
### Make sure whatever range you choose does not overlap with your node range(in my case 192.168.20.0/24) or the service range (10.96.0.0/12)
PODSUBNET=10.244.0.0
## Specify kubernetes version
VERSION=1.23.13-00
#################################

#Update and upgrade
apt-get -y update
apt-get -y upgrade

#Disable swap
swapoff -a
sed -i 's/\/swap.img/#\/swap.img/' /etc/fstab

#Forwarding IPv4 and letting iptables see bridged traffic
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl params without reboot
sysctl --system

#install containerd

sudo apt update

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list

apt update
apt install -y containerd.io ca-certificates curl gnupg lsb-release nfs-common apt-transport-https net-tools


cat <<EOF | tee -a /etc/containerd/config.toml
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
SystemdCgroup = true
EOF

sed -i 's/^disabled_plugins \=/\#disabled_plugins \=/g' /etc/containerd/config.toml

systemctl restart containerd


#####################################################
#add Google Cloud Public Signing Key
curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg

#Add Kubernetes apt Repo
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list

#Add Helm apt Repo
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | tee /etc/apt/sources.list.d/helm-stable-debian.list

#Install the required packages, if needed we can request a specific version.
apt-get  -y update 
apt-get install -y kubelet=$VERSION kubeadm=$VERSION kubectl=$VERSION helm 
apt-mark hold kubelet kubeadm kubectl 

#Ensure both are set to start when the system starts up.
systemctl enable kubelet.service
systemctl enable containerd.service

#modify Cluster config
kubeadm config print init-defaults | tee ClusterConfiguration.yaml > /dev/null

#Change the address of the localAPIEndpoint.advertiseAddress to the Control Plane Node's IP address
sed -i "s/  advertiseAddress: 1.2.3.4/  advertiseAddress: $CPIP/" ClusterConfiguration.yaml

#UPDATE: Added configuration to set the node name for the control plane node to the actual hostname
sed -i "s/  name: node/  name: $CPNAME/" ClusterConfiguration.yaml

sed -i "/^networking:/a \  podSubnet: $PODSUBNET\/16" ClusterConfiguration.yaml

#Set the CRI Socket to point to containerd
sed -i 's/  criSocket: \/var\/run\/dockershim\.sock/  criSocket: \/run\/containerd\/containerd\.sock/' ClusterConfiguration.yaml

#initalize Master Node
kubeadm init --config=ClusterConfiguration.yaml

#Create directory and copy kube config so root can run calico config
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

#sleep
sleep 60

#untaint master node
kubectl taint nodes --all node-role.kubernetes.io/master-
##kubectl taint nodes --all node-role.kubernetes.io/control-plane-

#install Calico operator
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.24.4/manifests/tigera-operator.yaml

#Download Calico Custom resources
curl https://raw.githubusercontent.com/projectcalico/calico/v3.24.4/manifests/custom-resources.yaml -O

#Change to PODSUBNET
sed -i "s/      cidr: 192.168.0.0\/16/      cidr: ${PODSUBNET}\/16/" custom-resources.yaml

#Configure custom resources
kubectl create -f custom-resources.yaml