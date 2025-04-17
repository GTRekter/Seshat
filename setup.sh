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
# AZURE_SUBSCRIPTION_NAME="Microsoft VSES"
AZURE_SUBSCRIPTION_NAME="Visual Studio Enterprise Subscription"
RESOURCE_GROUP_NAME=rg-training-krc
REGION="koreacentral"
AKS_INSTANCE=001
AKS_CLUSTER_NAME="aks-training-krc-$AKS_INSTANCE"
AKS_KUBERNETES_VERSION="1.30.10"
AKS_NODE_SIZE="Standard_D4_v5"
AKS_NODE_COUNT=2

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
        log_message "ERROR" "Failed to create AKS cluster: $AKS_CLUSTER_NAME"
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
        echo "Failed to get AKS credentials for cluster: $AKS_CLUSTER_NAME"
        exit 1
    fi
    log_message "DEBUG" "AKS credentials retrieved successfully"
}

function fortio_taint_node {
    log_message "INFO" "Tainting one node for Fortio"
    FORTIO_NODE=$(kubectl get nodes -o name | head -n 1 | cut -d'/' -f2)
    log_message "DEBUG" "Selected node for Fortio: $FORTIO_NODE"
    kubectl label node $FORTIO_NODE dedicated=fortio --overwrite
    kubectl taint node $FORTIO_NODE dedicated=fortio:NoSchedule --overwrite
}

# ---------------------------------------------------------
# Main script execution
# ---------------------------------------------------------
azure_create_resources
azure_get_credentials
fortio_taint_node