#!/bin/bash
###################################################################################################################
# Purpose       : Automates the setup of an AKS (Azure Kubernetes Service) environment in Microsoft Azure.
#                 Includes creation of resource groups, AKS cluster, installation of service meshes (Istio & Linkerd),
#                 and deployment of Fortio for load testing.
# Created on    : 12.10.24
# Updated on    : 12.10.24
# Made with ❤️  : Ivan Porta
# Version       : 1.0
###################################################################################################################
set -e  
set -u 

# ---------------------------------------------------------
# Load utilities
# ---------------------------------------------------------
source "$(dirname "$0")/utilities.sh"

# ---------------------------------------------------------
# Variables
# ---------------------------------------------------------
AZURE_SUBSCRIPTION_NAME="Microsoft VSES"
RESOURCE_GROUP_NAME=rg-training-krc
REGION="koreacentral"
AKS_INSTANCE=001
AKS_CLUSTER_NAME="aks-training-krc-$AKS_INSTANCE"
AKS_KUBERNETES_VERSION="1.30.10"
AKS_NODE_SIZE="Standard_D4s_v3"
AKS_NODE_COUNT=2

ISTIO_VERSION="1.25.1"
LINKERD_VERSION="edge-25.4.1"
# ---------------------------------------------------------
# Functions
# ---------------------------------------------------------
function azure_create_resources {
    log_message "INFO" "Creating resources in Azure"
    log_message "DEBUG" "Resource Group Name: $RESOURCE_GROUP_NAME"
    log_message "DEBUG" "Region: $REGION"
    log_message "DEBUG" "AKS Cluster Name: $AKS_CLUSTER_NAME"

    if ! command -v az &> /dev/null; then
        log_message "ERROR" "Azure CLI is not installed. Please install it and try again."
        exit 1
    fi
    if ! az account show &> /dev/null; then
        log_message "ERROR" "Azure CLI is not logged in. Please log in and try again."
        exit 1
    fi
    if ! az account list --all --query "[?isDefault].name" -o tsv | grep -q "$AZURE_SUBSCRIPTION_NAME"; then
        log_message "ERROR" "Azure subscription $AZURE_SUBSCRIPTION_NAME not found. Please check your subscription."
        exit 1
    fi

    log_message "DEBUG" "Creating Resource Group..."
    log_message "TECH" "az group create --name $RESOURCE_GROUP_NAME-$AKS_INSTANCE --location $REGION"
    az group create \
        --name "$RESOURCE_GROUP_NAME-$AKS_INSTANCE" \
        --location $REGION
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to create resource group: $RESOURCE_GROUP_NAME"
        exit 1
    fi
    log_message "DEBUG" "Resource Group created successfully"

    log_message "DEBUG" "Creating AKS Cluster..."
    log_message "TECH" "az aks create --resource-group $RESOURCE_GROUP_NAME-$AKS_INSTANCE --name $AKS_CLUSTER_NAME --kubernetes-version $AKS_KUBERNETES_VERSION --node-resource-group $RESOURCE_GROUP_NAME-infra-$AKS_INSTANCE --node-vm-size $AKS_NODE_SIZE --node-count $AKS_NODE_COUNT --os-sku Ubuntu --tier free --generate-ssh-keys"
    az aks create \
        --resource-group "$RESOURCE_GROUP_NAME-$AKS_INSTANCE" \
        --name $AKS_CLUSTER_NAME \
        --kubernetes-version $AKS_KUBERNETES_VERSION \
        --node-resource-group "$RESOURCE_GROUP_NAME-infra-$AKS_INSTANCE" \
        --node-vm-size $AKS_NODE_SIZE \
        --node-count $AKS_NODE_COUNT \
        --os-sku Ubuntu \
        --tier free \
        --generate-ssh-keys
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to create AKS cluster: $MY_AKS_CLUSTER_NAME"
        exit 1
    fi
    log_message "DEBUG" "AKS Cluster created successfully"
}

function azure_get_credentials {
    log_message "DEBUG" "Getting AKS credentials..."
    log_message "TECH" "az aks get-credentials --resource-group $RESOURCE_GROUP_NAME-$AKS_INSTANCE --name $AKS_CLUSTER_NAME"
    az aks get-credentials \
        --resource-group $RESOURCE_GROUP_NAME-$AKS_INSTANCE \
        --name $AKS_CLUSTER_NAME
    if [ $? -ne 0 ]; then
        echo "Failed to get AKS credentials for cluster: $MY_AKS_CLUSTER_NAME"
        exit 1
    fi
    log_message "DEBUG" "AKS credentials retrieved successfully"
}

function istio_install {
    log_message "INFO" "Installing Istio"
    log_message "DEBUG" "Istio Version: $ISTIO_VERSION"

    log_message" DEBUG" "Installing Istio CLI"
    log_message "TECH" "curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$ISTIO_VERSION sh"
    curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$ISTIO_VERSION sh
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to install Istio CLI"
        exit 1
    fi
    log_message "DEBUG" "Istio CLI installed successfully"
    cd istio-$ISTIO_VERSION
    export PATH=$PWD/bin:$PATH

    log_message "DEBUG" "Installing Istio control plane"
    log_message "TECH" "istioctl install --set profile=ambient --skip-confirmation"
    istioctl install --set profile=ambient --skip-confirmation
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to install Istio"
        exit 1
    fi
    log_message "DEBUG" "Istio control plane installed successfully"
}

function linkerd_install {
    log_message "INFO" "Installing Linkerd"
    log_message "DEBUG" "Linkerd Version: $LINKERD_VERSION"

    log_message "DEBUG" "Installing Linkerd CLI"
    log_message "TECH" "curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install-edge | LINKERD_VERSION=$LINKERD_VERSION sh"
    curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install-edge | LINKERD_VERSION=$LINKERD_VERSION sh
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to install Linkerd CLI"
        exit 1
    fi
    log_message "DEBUG" "Linkerd CLI installed successfully"
    export PATH=$PATH:$HOME/.linkerd2/bin

    log_message "DEBUG" "Installing Gateway API"
    log_message "TECH" "kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml"
    kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to install Gateway API"
        exit 1
    fi
    log_message "DEBUG" "Gateway API installed successfully"

    log_message "DEBUG" "Installing Linkerd CRDs"
    log_message "TECH" "linkerd check --crds | kubectl apply -f -"
    linkerd install --crds | kubectl apply -f -
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to install Linkerd CRDs"
        exit 1
    fi
    log_message "DEBUG" "Linkerd CRDs installed successfully"

    log_message "DEBUG" "Installing Linkerd control plane"
    log_message "TECH" "linkerd install | kubectl apply -f -"
    linkerd install | kubectl apply -f -
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to install Linkerd"
        exit 1
    fi
    log_message "DEBUG" "Linkerd control plane installed successfully"
}

function fortio_install {
    log_message "INFO" "Installing Fortio"
    log_message "TECH" "kubectl apply -f ./manifests/fortio.yaml"
    kubectl apply -f ./manifests/fortio.yaml
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to install Fortio"
        exit 1
    fi
    log_message "DEBUG" "Fortio installed successfully"
}

function fortio_taint_node {
    log_message "INFO" "Tainting one node for Fortio"
    FORTIO_NODE=$(kubectl get nodes -o name | head -n 1 | cut -d'/' -f2)
    log_message "DEBUG" "Selected node for Fortio: $FORTIO_NODE"
    kubectl label node $FORTIO_NODE dedicated=fortio --overwrite
    kubectl taint node $FORTIO_NODE dedicated=fortio:NoSchedule --overwrite
}


# azure_create_resources
# azure_get_credentials
# fortio_taint_node
# istio_install
# linkerd_install
# fortio_install