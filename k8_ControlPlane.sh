#!/bin/bash

#set variables
##IP Address of your ControlPlane
CPIP=192.168.20.2
## Name of your ControlPlane server (Match DNS, eg kube-1.lab.local)
CPNAME=kube-1.lab.local
## POD NETWORK SUBNET (Make sure it doesnt overlap with your prod network IE use 10.0.0.0)
PODSUBNET=10.0.0.0

#Update and upgrade
apt-get -y update
apt-get -y upgrade

#Disable swap
swapoff -a
sed -i 's/\/swap.img/#\/swap.img/' /etc/fstab

#containerd prereqs
cat <<EOF |  tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

# Setup required sysctl params, these persist across reboots. test
cat <<EOF |  tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

modprobe overlay
modprobe br_netfilter

# Apply sysctl params without reboot
sysctl --system

#add Google Cloud Public Signing Key
curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg

#Add Kubernetes apt Repo
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" |  tee /etc/apt/sources.list.d/kubernetes.list

#Add Helm apt Repo
curl https://baltocdn.com/helm/signing.asc |  apt-key add -
echo "deb https://baltocdn.com/helm/stable/debian/ all main" |  tee /etc/apt/sources.list.d/helm-stable-debian.list

#Install the required packages, if needed we can request a specific version.
apt-get  -y update 
apt-get install -y containerd apt-transport-https ca-certificates curl
VERSION=1.22.4-00
apt-get install -y kubelet=$VERSION kubeadm=$VERSION kubectl=$VERSION helm nfs-common containerd apt-transport-https ca-certificates curl
apt-mark hold kubelet kubeadm kubectl containerd

#configure containerd
mkdir -p /etc/containerd
containerd config default |  tee /etc/containerd/config.toml
sed -i 's/            SystemdCgroup = false/            SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd

#Ensure both are set to start when the system starts up.
systemctl enable kubelet.service
systemctl enable containerd.service

#modify Cluster config
kubeadm config print init-defaults | tee ClusterConfiguration.yaml > /dev/null

#Change the address of the localAPIEndpoint.advertiseAddress to the Control Plane Node's IP address
sed -i "s/  advertiseAddress: 1.2.3.4/  advertiseAddress: $CPIP/" ClusterConfiguration.yaml

#Set the CRI Socket to point to containerd
sed -i 's/  criSocket: \/var\/run\/dockershim\.sock/  criSocket: \/run\/containerd\/containerd\.sock/' ClusterConfiguration.yaml

#UPDATE: Added configuration to set the node name for the control plane node to the actual hostname
sed -i "s/  name: node/  name: $CPNAME/" ClusterConfiguration.yaml

#initalize Master Node
kubeadm init --config=ClusterConfiguration.yaml

#Create directory and copy kube config so root can run calico config
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

#sleep
sleep 60

#untaint master node
kubectl taint nodes --all node-role.kubernetes.io/master- > /dev/null

#install Calico
curl https://docs.projectcalico.org/manifests/calico.yaml -O > /dev/null

#change IP CIDR
sed -i 's/            # - name: CALICO_IPV4POOL_CIDR/            - name: CALICO_IPV4POOL_CIDR/' calico.yaml
sed -i "s/            #   value: \"192.168.0.0\/16\"/              value: \"$PODSUBNET\/16\"/" calico.yaml

#Deploy yaml file for your pod network.
kubectl apply -f calico.yaml > /dev/null