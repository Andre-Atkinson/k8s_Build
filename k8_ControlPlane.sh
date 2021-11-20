#!/bin/bash
sudo apt-get -y update
sudo apt-get -y upgrade

#Disable swap
swapoff -a
sudo sed -i 's/\/swap.img/#\/swap.img/' /etc/fstab

#containerd prereqs
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

# Setup required sysctl params, these persist across reboots. test
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Apply sysctl params without reboot
sudo sysctl --system

#Install containerd
sudo apt-get  -y update 
sudo apt-get install -y containerd apt-transport-https ca-certificates curl

#configure containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/            SystemdCgroup = false/            SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd

#add Google Cloud Public Signing Key
sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg

#Add Kubernetes apt Repo
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

#Add Helm apt Repo
curl https://baltocdn.com/helm/signing.asc | sudo apt-key add -
echo "deb https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list

#Install the required packages, if needed we can request a specific version.
sudo apt-get  -y update 
VERSION=1.22.4-00
sudo apt-get install -y kubelet=$VERSION kubeadm=$VERSION kubectl=$VERSION helm
sudo apt-mark hold kubelet kubeadm kubectl containerd helm

#Ensure both are set to start when the system starts up.
sudo systemctl enable kubelet.service
sudo systemctl enable containerd.service

#modify Cluster config
kubeadm config print init-defaults | tee ClusterConfiguration.yaml

#Change the address of the localAPIEndpoint.advertiseAddress to the Control Plane Node's IP address
sudo sed -i 's/  advertiseAddress: 1.2.3.4/  advertiseAddress: 192.168.20.2/' ClusterConfiguration.yaml

#Set the CRI Socket to point to containerd
sudo sed -i 's/  criSocket: \/var\/run\/dockershim\.sock/  criSocket: \/run\/containerd\/containerd\.sock/' ClusterConfiguration.yaml

#UPDATE: Added configuration to set the node name for the control plane node to the actual hostname
sudo sed -i 's/  name: node/  name: kube-1/' ClusterConfiguration.yaml

#initalize Master Node
sudo kubeadm init --config=ClusterConfiguration.yaml

# Not sure if the sleep is required..
sleep 180

#add autocompletion
source <(kubectl completion bash)
echo "source <(kubectl completion bash)" >> ~/.bashrc
alias k=kubectl
complete -F __start_kubectl k
echo "alias k=kubectl" >> ~/.bashrc
echo "complete -F __start_kubectl k"  >> ~/.bashrc

#Configure our account on the Control Plane Node to have admin access to the API server from a non-privileged account.
USER_HOME=$(getent passwd $SUDO_USER | cut -d: -f6)
echo $USER_HOME
mkdir -p "$USER_HOME/.kube"
sudo cp -i /etc/kubernetes/admin.conf $USER_HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config


#untaint master node
kubectl taint nodes --all node-role.kubernetes.io/master- > /dev/null

#install Calico
curl https://docs.projectcalico.org/manifests/calico.yaml -O > /dev/null

#change IP CIDR
sudo sed -i 's/            # - name: CALICO_IPV4POOL_CIDR/            - name: CALICO_IPV4POOL_CIDR/' calico.yaml > /dev/null
sudo sed -i 's/            #   value: "192.168.0.0\/16"/              value: "10.0.0.0\/16"/' calico.yaml > /dev/null

#Deploy yaml file for your pod network.
kubectl apply -f calico.yaml > /dev/null