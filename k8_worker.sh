#!/bin/bash
#################################
#set variables
## Specify kubernetes version
VERSION=1.22.4-00
#################################

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

# Setup required sysctl params, these persist across reboots.
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
apt-get -y update 
apt-get install -y kubelet=$VERSION kubeadm=$VERSION kubectl=$VERSION helm containerd apt-transport-https ca-certificates curl nfs-common
apt-mark hold kubelet kubeadm kubectl containerd 

#configure containerd
mkdir -p /etc/containerd
containerd config default |  tee /etc/containerd/config.toml
sed -i 's/            SystemdCgroup = false/            SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd

#Ensure both are set to start when the system starts up.
systemctl enable kubelet.service
systemctl enable containerd.service
