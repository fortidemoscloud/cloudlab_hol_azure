#!/bin/bash
# -------------------------------------------------------------------------------------------------------------
# User-data script to configure a K8S node master and populate parameters
#
# jvigueras@fortinet.com
# -------------------------------------------------------------------------------------------------------------

# Variables
K8S_VERSION="v${k8s_version}"
LINUX_USER="${linux_user}"
K8S_SA_NAME="cicd-access"

#--------------------------------------------------------------------------------------------------------------
# Install K8S (master node)
#--------------------------------------------------------------------------------------------------------------
# Install Kubernetes
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/$K8S_VERSION/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$K8S_VERSION/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
apt update -y
apt install -y kubeadm kubelet kubectl

apt install -y watch ipset tcpdump
          
cat <<EOF | tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Setup required sysctl params, these persist across reboots.
cat <<EOF | tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

# Apply sysctl params without reboot
sysctl --system

# Install containerd
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y containerd.io

# Configure containerd
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# Restart containerd
systemctl restart containerd
swapoff -a
kubeadm config images pull

# Initialize the Kubernetes cluster
kubeadm init \
    --pod-network-cidr=192.168.0.0/16 \
    --apiserver-cert-extra-sans=127.0.0.1
   #--skip-phases=addon/kube-proxy

# Export KUBECONFIG for linux_user
mkdir -p /home/$LINUX_USER/.kube
cp -i /etc/kubernetes/admin.conf /home/$LINUX_USER/.kube/config
chown $LINUX_USER /home/$LINUX_USER/.kube/config

# Export KUBECONFIG for root user
export KUBECONFIG="/etc/kubernetes/admin.conf"

# Install Calico
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.24.5/manifests/tigera-operator.yaml
curl https://raw.githubusercontent.com/projectcalico/calico/v3.24.5/manifests/custom-resources.yaml -O
sed -i 's/encapsulation: VXLANCrossSubnet/encapsulation: VXLAN/g' custom-resources.yaml
kubectl apply -f ./custom-resources.yaml

#--------------------------------------------------------------------------------------------------------------
# Create a service account and secret with a permanent cluster token
#--------------------------------------------------------------------------------------------------------------
kubectl create sa $K8S_SA_NAME -n default

# Create non expiring SA token
cat << EOF > new-sa.yaml
apiVersion: v1
kind: Secret
type: kubernetes.io/service-account-token
metadata:
  name: $K8S_SA_NAME
  annotations:
    kubernetes.io/service-account.name: $K8S_SA_NAME
EOF
kubectl apply -f new-sa.yaml

# Create a ClusterRoleBinding for the service account
kubectl create clusterrolebinding $K8S_SA_NAME --clusterrole cluster-admin --serviceaccount default:$K8S_SA_NAME

#--------------------------------------------------------------------------------------------------------------
# Deploy applications
#--------------------------------------------------------------------------------------------------------------
cat << EOF > app-deployment.yaml
${k8s_deployment}
EOF
kubectl apply -f app-deployment.yaml

#--------------------------------------------------------------------------------------------------------------
# Disable Ubuntu OCI iptables default
#--------------------------------------------------------------------------------------------------------------
iptables -F
netfilter-persistent save

#--------------------------------------------------------------------------------------------------------------
# Remove taints in master node
#--------------------------------------------------------------------------------------------------------------
kubectl taint node --all node-role.kubernetes.io/master-
kubectl taint node --all node-role.kubernetes.io/control-plane-

#--------------------------------------------------------------------------------------------------------------
# Set TimeZone
#--------------------------------------------------------------------------------------------------------------
timedatectl set-timezone Europe/Madrid
