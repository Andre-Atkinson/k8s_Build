# Variables
KUBERNETES_VERSION=v1.33
CRIO_VERSION=v1.33
CALICO_VERSION=v3.30.3
NODE_NAME=$(hostname)

#make some changes
sudo swapoff -a
modprobe br_netfilter
sysctl -w net.ipv4.ip_forward=1

#Install common requirements
apt-get -y update
apt-get -y upgrade
apt-get install -y software-properties-common curl

#Kuberenetes repo
curl -fsSL https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/Release.key |  gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list

# Install CR-IO
curl -fsSL https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/deb/ /" | tee /etc/apt/sources.list.d/cri-o.list

sudo apt-get install curl gpg apt-transport-https --yes
curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm

#Install Kuberenetes
apt-get update
apt-get install -y cri-o kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl #Version 1.33

#Start CR-IO
systemctl start crio.service
