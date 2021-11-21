# k8s_Build
This script enables to build a working Kubernetes cluster on ubuntu 2004.

There are two scripts, one that needs to be run on your ControlPlane and another for any worker nodes you plan to join to the cluster

Pre Reqs
- Ubuntu 2004 (tested)

CONTROL PLANE STEPS
Step 1
    Copy script to ControlPlane node
    sudo chmod 775 k8_ControlPlane.sh
    sudo ./k8_ControlPlane.sh

Make note of the join command in the final output (It should look like the below)

kubeadm join xxx.xxx.xx.xxx:6443 --token abcdef.xxxxxxxxxx \
        --discovery-token-ca-cert-hash sha256:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx 

step 2 - Run as your normal user
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    alias k=kubectl
    complete -F __start_kubectl k

WORKER NODE STEPS
If you wish to add any worker nodes then you will need to copy the k8_worker.sh script to the host you wish to use

Step 1
    Copy script to worker node
    sudo chmod 775 k8_worker.sh
    sudo ./k8_worker.sh

step 2 - Join to cluster using hte join token from the ControlPlane
    sudo kubeadm join xxx.xxx.xx.xxx:6443 --token abcdef.xxxxxxxxxx \
        --discovery-token-ca-cert-hash sha256:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx 