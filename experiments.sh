#!/bin/bash
###################################################################################################################
# Purpose       : The purpose of the script is to setup the environment for the experiment.
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
CLUSTER_DOMAIN="cluster.local"

FORTIO_CLIENT_NS="service-mesh-benchmark"
FORTIO_CLIENT_SVC="fortio-client"
FORTIO_CLIENT_HOST="${FORTIO_CLIENT_SVC}.${FORTIO_CLIENT_NS}.svc.cluster.local"
FORTIO_CLIENT_PORT="8080"
FORTIO_CLIENT_ENDPOINT="http://${FORTIO_CLIENT_HOST}:${FORTIO_CLIENT_PORT}/fortio/rest/run"

FORTIO_SERVER_NS="service-mesh-benchmark"
FORTIO_SERVER_SVC="fortio-server"
FORTIO_SERVER_HTTP_PORT="8080"
FORTIO_SERVER_GRPC_PORT="8079"

DURATION="180s"
INTERVAL="1s"
CONNECTIONS=50
RESOLUTION="0.0001"
METRICS_INITIAL_DELAY=30
RESULTS_DIR="./results"

MESH="istio" # baseline, istio, linkerd
ISTIO_VERSION="1.25.1"
ISTIO_WAYPOINT_PLACEMENT="same" # same, different
LINKERD_VERSION="edge-25.4.1"

CONFIG_LOG_LEVEL=DEBUG

# ---------------------------------------------------------
# Functions
# ---------------------------------------------------------
function export_resource_metrics {
    OPTIND=1
    local OUTPUT_FILE=""
    local MESH="" 
    while getopts "o:m:" opt; do
        case $opt in
            o) OUTPUT_FILE="$OPTARG" ;;
            m) MESH="$OPTARG" ;;
            *) echo "Invalid option: -$OPTARG" >&2; return 1 ;;
        esac
    done
    if [[ -z $OUTPUT_FILE ]] || [[ -z $MESH ]]; then
        log_message "ERROR" "Output Directory and Mesh Configuration are required!"
        exit 1
    fi
    log_message "DEBUG" "Output Directory: ${OUTPUT_FILE}"
    log_message "DEBUG" "Mesh: ${MESH}"
    declare -a QUERIES
    if [[ "$MESH" == "istio" ]]; then
        QUERIES+=("control-plane|istio-system|app=istiod|discovery")
        QUERIES+=("data-plane|istio-system|app=ztunnel|istio-proxy")
        QUERIES+=("data-plane|$FORTIO_SERVER_NS|service.istio.io/canonical-name=waypoint|istio-proxy")
    fi
    if [[ "$MESH" == "linkerd" ]]; then
        QUERIES+=("control-plane|linkerd|linkerd.io/control-plane-component=destination|destination")
        QUERIES+=("control-plane|linkerd|linkerd.io/control-plane-component=destination|policy")
        QUERIES+=("control-plane|linkerd|linkerd.io/control-plane-component=destination|linkerd-proxy")
        QUERIES+=("control-plane|linkerd|linkerd.io/control-plane-component=destination|sp-validator")
        QUERIES+=("control-plane|linkerd|linkerd.io/control-plane-component=identity|identity")
        QUERIES+=("control-plane|linkerd|linkerd.io/control-plane-component=identity|linkerd-proxy")
        QUERIES+=("control-plane|linkerd|linkerd.io/control-plane-component=proxy-injector|proxy-injector")
        QUERIES+=("control-plane|linkerd|linkerd.io/control-plane-component=proxy-injector|linkerd-proxy")
        QUERIES+=("data-plane|$FORTIO_CLIENT_NS|app=fortio-client|linkerd-proxy")
        QUERIES+=("data-plane|$FORTIO_SERVER_NS|app=fortio-server|linkerd-proxy")
    fi
    log_message "DEBUG" "Write CSV headers"
    echo "timestamp,group,namespace,pod,container,cpu(n),memory(Ki)" > "$OUTPUT_FILE"
    log_message "DEBUG" "Sleeping for ${METRICS_INITIAL_DELAY} seconds to allow the load test to ramp up..."
    sleep "${METRICS_INITIAL_DELAY}"
    log_message "DEBUG" "Collecting CPU/memory metrics every ${INTERVAL}..."
    while true; do
        TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        RAW_JSON=$(kubectl get --raw "/apis/metrics.k8s.io/v1beta1/pods")
        for QUERY in "${QUERIES[@]}"; do
            IFS='|' read -r GROUP NS_FILTER LABEL_FILTER CONTAINER_FILTER <<< "$QUERY"
            KEY="${LABEL_FILTER%%=*}"
            VALUE="${LABEL_FILTER#*=}"
            MATCHING_ITEMS=$(echo "$RAW_JSON" | jq -c --arg ns "$NS_FILTER" --arg key "$KEY" --arg value "$VALUE" '.items[] | select(.metadata.namespace == $ns and (.metadata.labels[$key] == $value))')
            while IFS= read -r ITEM; do
                POD_NAME=$(echo "$ITEM" | jq -r '.metadata.name')
                POD_NAMESPACE=$(echo "$ITEM" | jq -r '.metadata.namespace')
                echo "$ITEM" | jq -c '.containers[]' | while IFS= read -r CONTAINER_ITEM; do
                    CONTAINER_NAME=$(echo "$CONTAINER_ITEM" | jq -r '.name')
                    if [[ -n "$CONTAINER_FILTER" && "$CONTAINER_NAME" != "$CONTAINER_FILTER" ]]; then
                        continue
                    fi
                    CPU_NANO=$(echo "$CONTAINER_ITEM" | jq -r '.usage.cpu')
                    MEM_KI=$(echo "$CONTAINER_ITEM" | jq -r '.usage.memory')
                    echo "$TIMESTAMP,$GROUP,$POD_NAMESPACE,$POD_NAME,$CONTAINER_NAME,$CPU_NANO,$MEM_KI" >> "$OUTPUT_FILE"
                done
            done <<< "$MATCHING_ITEMS"
        done
        sleep "$INTERVAL"
    done
}

function terminate_export_resource_metrics_process {
    if [[ -n "${METRICS_PID:-}" ]]; then
        echo "Cleaning up background metrics process $METRICS_PID..."
        kill "$METRICS_PID" 2>/dev/null || true
    fi
}

function fortio_load_test {
    OPTIND=1
    local OUTPUT_DIR="${RESULTS_DIR}"
    local MESH=""
    local QUERY_PER_SECOND="0" # 0 means MAX
    local UNIFORM_DISTRIBUTION="true"
    local NO_CATCHUP="true"
    local PAYLOAD_SIZE="0"
    local RESOLUTION="0.0001"
    local RUNNER="http"
    while getopts "o:m:q:d:c:p:r:u:" opt; do
        case $opt in
            o) OUTPUT_DIR="$OPTARG" ;;
            m) MESH="$OPTARG" ;;
            q) QUERY_PER_SECOND="$OPTARG" ;;
            d) UNIFORM_DISTRIBUTION="$OPTARG" ;;
            c) NO_CATCHUP="$OPTARG" ;;
            p) PAYLOAD_SIZE="$OPTARG" ;;
            r) RESOLUTION="$OPTARG" ;;
            u) RUNNER="$OPTARG" ;;
            *) echo "Invalid option: -$OPTARG" >&2; return 1 ;;
        esac
    done
    if [[ -z $OUTPUT_DIR ]] || [[ -z $MESH ]] || [[ -z $QUERY_PER_SECOND ]]; then
        log_message "ERROR" "Output Directory, Mesh Configuration, and Queries Per Second are required!"
        exit 1
    fi 
    log_message "DEBUG" "Output Directory: ${OUTPUT_DIR}"
    log_message "DEBUG" "Mesh: ${MESH}"
    log_message "DEBUG" "Query per second: ${QUERY_PER_SECOND}"
    log_message "DEBUG" "Uniform Distribution: ${UNIFORM_DISTRIBUTION}"
    log_message "DEBUG" "No Catchup: ${NO_CATCHUP}"
    log_message "DEBUG" "Connections: ${CONNECTIONS}"
    log_message "DEBUG" "Duration: ${DURATION}"
    log_message "DEBUG" "Payload Size: ${PAYLOAD_SIZE}"
    log_message "DEBUG" "Resolution: ${RESOLUTION}"
    log_message "DEBUG" "Runner: ${RUNNER}"
    if [[ "$RUNNER" == "http" ]]; then
        TARGET="http://${FORTIO_SERVER_SVC}.${FORTIO_SERVER_NS}.svc.${CLUSTER_DOMAIN}:${FORTIO_SERVER_HTTP_PORT}"
    else
        TARGET="${FORTIO_SERVER_SVC}.${FORTIO_SERVER_NS}.svc.${CLUSTER_DOMAIN}:${FORTIO_SERVER_GRPC_PORT}"
    fi
    log_message "DEBUG" "Target URL: ${TARGET}"
    NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    METRICS_FILE="${OUTPUT_DIR}/metrics_${MESH}_${QUERY_PER_SECOND}_${PAYLOAD_SIZE}_${NOW}.csv"
    LATENCY_FILE="${OUTPUT_DIR}/latencies_${MESH}_${QUERY_PER_SECOND}_${PAYLOAD_SIZE}_${NOW}.json"
    if [[ "$MESH" != "baseline" ]]; then
        log_message "DEBUG" "Start collecting metrics..."
        export_resource_metrics -m "$MESH" -o "$METRICS_FILE" &
        METRICS_PID=$!
        log_message "DEBUG" "Background metrics PID: $METRICS_PID"
    fi
    ARGUMENTS=("-c" "$CONNECTIONS" "-qps" "$QUERY_PER_SECOND" "-t" "$DURATION" "-r" "$RESOLUTION"  "-payload-size" "$PAYLOAD_SIZE")
    if [[ "$NO_CATCHUP" == "true" ]]; then
        ARGUMENTS+=( "-nocatchup" )
    fi
    if [[ "$UNIFORM_DISTRIBUTION" == "true" ]]; then
        ARGUMENTS+=( "-uniform" )
    fi
    if [[ "$RUNNER" != "http" ]]; then
        ARGUMENTS+=( "-grpc" )
    fi
    log_message "TECH" "kubectl exec -n \"$FORTIO_CLIENT_NS\" deploy/fortio-client -c fortio -- fortio load \"${ARGUMENTS[@]}\" -json - \"$TARGET\""
    kubectl exec -n "$FORTIO_CLIENT_NS" deploy/fortio-client -c fortio -- fortio load "${ARGUMENTS[@]}" -json - "$TARGET" > "$LATENCY_FILE"
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Error connecting to ${URL}"
        if [[ "$MESH" != "baseline" ]]; then
            kill $METRICS_PID
        fi
        exit 1
    fi
    if [[ "$MESH" != "baseline" ]]; then
        kill $METRICS_PID
    fi
}

function gateway_api_install {
    log_message "DEBUG" "Installing Gateway API"
    log_message "TECH" "kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml"
    kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to install Gateway API"
        exit 1
    fi
    log_message "DEBUG" "Gateway API installed successfully"
}

function istio_cli_install {
    log_message "INFO" "Installing Istio CLI"
    log_message "DEBUG" "Istio Version: $ISTIO_VERSION"
    if ! command -v istioctl >/dev/null 2>&1; then
        log_message "DEBUG" "Installing Istio CLI"
        log_message "TECH" "curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$ISTIO_VERSION sh"
        curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$ISTIO_VERSION sh
        if [ $? -ne 0 ]; then
            log_message "ERROR" "Failed to install Istio CLI"
            exit 1
        fi
        # cd istio-$ISTIO_VERSION
        # export PATH=$PWD/bin:$PATH
        export PATH=istio-$ISTIO_VERSION/bin:$PATH
    fi
    log_message "DEBUG" "Istio CLI installed successfully"
}

function istio_install {
    log_message "DEBUG" "Installing Istio (Ambient) Control Plane"
    log_message "TECH" "istioctl install --set profile=ambient --skip-confirmation"
    istioctl install --set profile=ambient --skip-confirmation
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to install Istio"
        exit 1
    fi
    log_message "DEBUG" "Istio Control Plane (Ambient) installed successfully"
}

function istio_uninstall {
    log_message "DEBUG" "Removing all Istio Waypoints"
    log_message "TECH" "istioctl waypoint delete --all"
    istioctl waypoint delete --all
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to delete Istio waypoint"
        exit 1
    fi
    log_message "DEBUG" "Istio waypoint removed successfully"

    log_message "DEBUG" "Uninstalling Istio Control Plane"
    log_message "TECH" "istioctl uninstall --skip-confirmation --purge"
    istioctl uninstall --skip-confirmation --purge
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to uninstall Istio Control Plane"
        exit 1
    fi
    log_message "DEBUG" "Istio Control Plane uninstalled successfully"
}

function linkerd_cli_install {
    log_message "INFO" "Installing Linkerd CLI"
    log_message "DEBUG" "Linkerd Version: $LINKERD_VERSION"
    if ! command -v linkerd >/dev/null 2>&1; then
        log_message "DEBUG" "Installing Linkerd CLI"
        log_message "TECH" "curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install-edge | LINKERD_VERSION=$LINKERD_VERSION sh"
        curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install-edge | LINKERD_VERSION=$LINKERD_VERSION sh
        if [ $? -ne 0 ]; then
            log_message "ERROR" "Failed to install Linkerd CLI"
            exit 1
        fi
        export PATH=$PATH:$HOME/.linkerd2/bin
    else
        log_message "DEBUG" "Linkerd CLI installed successfully"
    fi
}

function linkerd_install {
    log_message "DEBUG" "Installing Linkerd CRDs"
    log_message "TECH" "linkerd check --crds | kubectl apply -f -"
    linkerd install --crds | kubectl apply -f -
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to install Linkerd CRDs"
        exit 1
    fi
    log_message "DEBUG" "Linkerd CRDs installed successfully"

    log_message "DEBUG" "Installing Linkerd Control Plane"
    log_message "TECH" "linkerd install | kubectl apply -f -"
    linkerd install | kubectl apply -f -
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to install Linkerd"
        exit 1
    fi
    log_message "DEBUG" "Waiting for Linkerd pods to be ready in namespace 'linkerd'"
    log_message "TECH"  "kubectl wait --for=condition=Ready pod --all -n linkerd --timeout=300s"
    if ! kubectl wait --for=condition=Ready pod --all -n linkerd --timeout=300s; then
        log_message "ERROR" "Some Linkerd pods failed to become ready within 5m"
        exit 1
    fi
    log_message "DEBUG" "Linkerd Control Plane installed successfully"
}

function linkerd_uninstall {
    log_message "DEBUG" "Uninstalling Linkerd Control Plane"
    log_message "TECH" "linkerd uninstall | kubectl delete -f -"
    linkerd uninstall | kubectl delete -f -
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to uninstall Linkerd Control Plane"
        exit 1
    fi
    log_message "DEBUG" "Linkerd Control Plane uninstalled successfully"
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

function fortio_uninstall {
    log_message "INFO" "Uninstall Fortio"
    log_message "TECH" "kubectl delete -f ./manifests/fortio.yaml --ignore-not-found"
    kubectl delete -f ./manifests/fortio.yaml --ignore-not-found
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to uninstall Fortio"
        exit 1
    fi
    log_message "DEBUG" "Fortio installed successfully"
}

# ---------------------------------------------------------
# Check if the required tools are installed
# ---------------------------------------------------------
trap terminate_export_resource_metrics_process EXIT INT TERM
istio_cli_install
linkerd_cli_install
gateway_api_install
fortio_uninstall
istio_uninstall
linkerd_uninstall
fortio_install

log_message "INFO" "Checking if the required tools are installed..."
if [ -z "$MESH" ] || { [ "$MESH" != "istio" ] && [ "$MESH" != "linkerd" ] && [ "$MESH" != "baseline" ]; }; then
    log_message "ERROR" "Invalid or missing mesh type. Please set the MESH variable to 'istio', 'linkerd' or 'baseline'."
    exit 1
fi
if [ "$MESH" == "istio" ]; then
    istio_install
    if ! kubectl get pods -n "istio-system" | grep -q "istio"; then
        log_message "ERROR" "Istio is not deployed in namespace istio-system"
        exit 1
    fi
    if ! kubectl get pods -n "istio-system" | grep -q "ztunnel"; then
        log_message "ERROR" "ztunnel is not deployed in namespace istio-system"
        exit 1
    fi

    log_message "INFO" "Deploying Waypoint into Fortio client and server"
    kubectl label ns $FORTIO_CLIENT_NS istio.io/dataplane-mode=ambient
    istioctl waypoint apply -n $FORTIO_CLIENT_NS --enroll-namespace --overwrite
    if [[ $FORTIO_CLIENT_NS != "$FORTIO_SERVER_NS" ]]; then
        kubectl label ns $FORTIO_SERVER_NS istio.io/dataplane-mode=ambient
        istioctl waypoint apply -n $FORTIO_SERVER_NS --enroll-namespace --overwrite
    fi
    sleep 5
    if [[ "$ISTIO_WAYPOINT_PLACEMENT" == "same" ]]; then
        log_message "DEBUG" "Patching Istio Waypoint to nodeSelector dedicated=fortio"
        log_message "TECH" "kubectl -n $FORTIO_CLIENT_NS patch deployment waypoint --type='json' -p='[{\"op\":\"add\",\"path\":\"/spec/template/spec/nodeSelector\",\"value\":{\"dedicated\":\"fortio\"}}]'"
        kubectl -n "$FORTIO_CLIENT_NS" patch deployment waypoint --type='json' -p='[{"op":"add","path":"/spec/template/spec/nodeSelector","value":{"dedicated":"fortio"}}]'
        log_message "TECH" "kubectl -n $FORTIO_CLIENT_NS patch deployment waypoint --type='json' -p='[{\"op\":\"add\",\"path\":\"/spec/template/spec/tolerations\",\"value\":[{\"key\":\"dedicated\",\"operator\":\"Equal\",\"value\":\"fortio\",\"effect\":\"NoSchedule\"}]}]'"
        kubectl -n "$FORTIO_CLIENT_NS" patch deployment waypoint --type='json' -p='[{"op":"add","path":"/spec/template/spec/tolerations","value":[{"key":"dedicated","operator":"Equal","value":"fortio","effect":"NoSchedule"}]}]'
        if [[ $FORTIO_CLIENT_NS != "$FORTIO_SERVER_NS" ]]; then
            log_message "TECH" "kubectl -n $FORTIO_SERVER_NS patch deployment waypoint --type='json' -p='[{\"op\":\"add\",\"path\":\"/spec/template/spec/nodeSelector\",\"value\":{\"dedicated\":\"fortio\"}}]'"
            kubectl -n "$FORTIO_SERVER_NS" patch deployment waypoint --type='json' -p='[{"op":"add","path":"/spec/template/spec/nodeSelector","value":{"dedicated":"fortio"}}]'
            log_message "TECH" "kubectl -n $FORTIO_SERVER_NS patch deployment waypoint --type='json' -p='[{\"op\":\"add\",\"path\":\"/spec/template/spec/tolerations\",\"value\":[{\"key\":\"dedicated\",\"operator\":\"Equal\",\"value\":\"fortio\",\"effect\":\"NoSchedule\"}]}]'"
            kubectl -n "$FORTIO_SERVER_NS" patch deployment waypoint --type='json' -p='[{"op":"add","path":"/spec/template/spec/tolerations","value":[{"key":"dedicated","operator":"Equal","value":"fortio","effect":"NoSchedule"}]}]'
        fi
    fi
    
    log_message "DEBUG" "Waiting for waypoint to be ready in $FORTIO_CLIENT_NS and $FORTIO_SERVER_NS"
    kubectl wait --for=condition=ready pod -l service.istio.io/canonical-name=waypoint -n $FORTIO_CLIENT_NS --timeout=300s
    if [[ $FORTIO_CLIENT_NS != "$FORTIO_SERVER_NS" ]]; then
        kubectl wait --for=condition=ready pod -l service.istio.io/canonical-name=waypoint -n $FORTIO_SERVER_NS --timeout=300s
    fi
fi
if [ "$MESH" == "linkerd" ]; then
    linkerd_install
    if ! kubectl get pods -n "linkerd" | grep -q "linkerd"; then
        log_message "ERROR" "Linkerd is not deployed in namespace linkerd"
        exit 1
    fi
    log_message "INFO" "Injecting Linkerd proxy into Fortio client and server"
    kubectl annotate ns $FORTIO_CLIENT_NS linkerd.io/inject=enabled
    kubectl rollout restart deploy -n $FORTIO_CLIENT_NS
    if [[ $FORTIO_CLIENT_NS != "$FORTIO_SERVER_NS" ]]; then
        kubectl annotate ns $FORTIO_SERVER_NS linkerd.io/inject=enabled
        kubectl rollout restart deploy -n $FORTIO_SERVER_NS
    fi
fi
if ! kubectl get pods -n $FORTIO_CLIENT_NS | grep -q "fortio-client"; then
    log_message "ERROR" "Fortio client is not deployed in namespace $FORTIO_CLIENT_NS"
    exit 1
fi
if ! kubectl get pods -n $FORTIO_SERVER_NS | grep -q "fortio-server"; then
    log_message "ERROR" "Fortio server is not deployed in namespace $FORTIO_SERVER_NS"
    exit 1
fi
log_message "INFO" "All required tools are installed"
sleep 20

# ---------------------------------------------------------
# Run the experiments
# ---------------------------------------------------------
log_message "DEBUG" "Starting HTTP Max Throughput test"
OUTPUT_DIR="${RESULTS_DIR}/01_http_max_throughput"
if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR"
fi
fortio_load_test -o $OUTPUT_DIR -m $MESH -q "0" -d "false" -c "false" -r $RESOLUTION
log_message "DEBUG" "Wait 5 seconds to clean up the metrics"
sleep 20
log_message "DEBUG" "Starting HTTP Constant Throughput test"
OUTPUT_DIR="${RESULTS_DIR}/02_http_constant_throughput"
if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR"
fi
QUERY_PER_SECOND_LIST=(1 1000 10000 100000 1000000)
for QUERY_PER_SECOND in "${QUERY_PER_SECOND_LIST[@]}"; do
    log_message "INFO" "Running experiment with ${QUERY_PER_SECOND} queries per second"
    fortio_load_test -o $OUTPUT_DIR -m $MESH -q $QUERY_PER_SECOND -d "true" -c "true" -r $RESOLUTION
    log_message "DEBUG" "Wait 5 seconds to clean up the metrics"
     sleep 20
done
log_message "DEBUG" "Starting HTTP Payload test"
OUTPUT_DIR="${RESULTS_DIR}/03_http_payload"
if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR"
fi
QUERY_PER_SECOND=1000
PAYLOAD_SIZE_LIST=(10000 100000 1000000)
for PAYLOAD_SIZE in "${PAYLOAD_SIZE_LIST[@]}"; do
    log_message "INFO" "Running experiment with ${PAYLOAD_SIZE} bytes payload"
    fortio_load_test -o $OUTPUT_DIR -m $MESH -q $QUERY_PER_SECOND -d "true" -c "true" -r $RESOLUTION -p $PAYLOAD_SIZE
    log_message "DEBUG" "Wait 5 seconds to clean up the metrics"
    sleep 20
done
log_message "DEBUG" "Starting GRPC Max Throughput test"
OUTPUT_DIR="${RESULTS_DIR}/04_grpc_max_throughput"
if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR"
fi
fortio_load_test -o $OUTPUT_DIR -m $MESH -q "0" -d "false" -c "false" -r $RESOLUTION -u "grpc"
log_message "SUCCESS" "Experiment completed successfully!"