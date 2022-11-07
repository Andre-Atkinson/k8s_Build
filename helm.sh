helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
    --set nfs.server=192.168.10.6 \
    --set nfs.path=/volume1/nfs

#make your NFS share the default storage class
kubectl patch storageclass nfs-client -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'    

helm repo add metallb https://metallb.github.io/metallb
helm install metallb metallb/metallb --create-namespace --namespace metallb-system

sleep 30
cat <<EOF | tee -a IPAddressPool.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: prod
  namespace: metallb-system
spec:
  addresses:
  - 192.168.20.150-192.168.20.170
EOF

kubectl create -f IPAddressPool.yaml

cat <<EOF | tee -a l2advertisement.yml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: prodadvertisement
  namespace: metallb-system
spec:
  ipAddressPools:
  - prod
EOF

kubectl create -f l2advertisement.yml 