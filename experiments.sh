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
FORTIO_SERVER_PORT="8080"

DURATION="60s"
INTERVAL="1s"
CONNECTIONS=100
RESULTS_DIR="./results"

# MESH=istio
MESH=linkerd
CONFIG_LOG_LEVEL=DEBUG

# function export_resource_metrics {
#     OPTIND=1
#     local OUTPUT_FILE=""
#     local MESH="" 
#     while getopts "o:m:" opt; do
#         case $opt in
#             o) OUTPUT_FILE="$OPTARG" ;;
#             m) MESH="$OPTARG" ;;
#             *) echo "Invalid option: -$OPTARG" >&2; return 1 ;;
#         esac
#     done
#     if [[ -z $OUTPUT_FILE ]] || [[ -z $MESH ]]; then
#         log_message "ERROR" "Output Directory and Mesh Configuration are required!"
#         exit 1
#     fi
#     log_message "DEBUG" "Output Directory: ${OUTPUT_FILE}"
#     log_message "DEBUG" "Mesh: ${MESH}"
#     declare -a QUERIES
#     if [[ "$MESH" == "istio" ]]; then
#         QUERIES+=("istio-system|app=istiod|")
#         QUERIES+=("istio-system|app=ztunnel|")
#         QUERIES+=("service-mesh-benchmark|app=waypoint|")
#     fi
#     if [[ "$MESH" == "linkerd" ]]; then
#         QUERIES+=("service-mesh-benchmark|linkerd.io/proxy-version|linkerd-proxy")
#         QUERIES+=("linkerd|linkerd.io/control-plane-component=destination|")
#     fi
#     log_message "DEBUG" "Write CSV headers"
#     echo "timestamp,namespace,pod,container,cpu(millicores),memory(Mi)" > "$OUTPUT_FILE"
#     log_message "DEBUG" "Collecting CPU/memory metrics every ${INTERVAL}s..."
#     while true; do
#         TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
#         for QUERY in "${QUERIES[@]}"; do
#             IFS='|' read -r NS_FILTER LABEL_FILTER CONTAINER_FILTER <<< "$QUERY"
#             PODS=$(kubectl get pods -n "$NS_FILTER" -l "$LABEL_FILTER" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{end}')
#             for POD in $PODS; do
#                 log_message "DEBUG" "Collecting container-level metrics for pod $POD in namespace $NS_FILTER"
#                 log_message "TECH" "kubectl top pod $POD -n $NS_FILTER --containers --no-headers"
#                 METRICS=$(kubectl top pod "$POD" -n "$NS_FILTER" --containers --no-headers 2>/dev/null)
#                 if [[ -n "$METRICS" ]]; then
#                     while read -r line; do
#                         POD_NAME=$(echo "$line" | awk '{print $1}')
#                         CONTAINER=$(echo "$line" | awk '{print $2}')
#                         CPU=$(echo "$line" | awk '{print $3}' | sed 's/m//')
#                         MEMORY=$(echo "$line" | awk '{print $4}' | sed 's/Mi//')
#                         # If a container filter is set, skip non-matching container names
#                         if [[ -n "$CONTAINER_FILTER" && "$CONTAINER" != "$CONTAINER_FILTER" ]]; then
#                             continue
#                         fi
#                         echo "$TIMESTAMP,$NS_FILTER,$POD_NAME,$CONTAINER,$CPU,$MEMORY" >> "$OUTPUT_FILE"
#                     done <<< "$METRICS"
#                 else
#                     echo "$TIMESTAMP,$NS_FILTER,$POD,N/A,N/A,N/A" >> "$OUTPUT_FILE"
#                 fi
#             done
#         done
#         sleep "$INTERVAL"
#     done
# }

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
        QUERIES+=("istio-system|app=istiod|discovery")
        QUERIES+=("istio-system|app=ztunnel|istio-proxy")
        QUERIES+=("$FORTIO_SERVER_NS|service.istio.io/canonical-name=waypoint|istio-proxy")
    fi
    if [[ "$MESH" == "linkerd" ]]; then
        QUERIES+=("linkerd|linkerd.io/control-plane-component=destination|destination")
        QUERIES+=("linkerd|linkerd.io/control-plane-component=destination|policy")
        QUERIES+=("linkerd|linkerd.io/control-plane-component=destination|linkerd-proxy")
        QUERIES+=("linkerd|linkerd.io/control-plane-component=destination|sp-validator")
        QUERIES+=("linkerd|linkerd.io/control-plane-component=identity|identity")
        QUERIES+=("linkerd|linkerd.io/control-plane-component=identity|linkerd-proxy")
        QUERIES+=("linkerd|linkerd.io/control-plane-component=proxy-injector|proxy-injector")
        QUERIES+=("linkerd|linkerd.io/control-plane-component=proxy-injector|linkerd-proxy")
        QUERIES+=("$FORTIO_CLIENT_NS|app=fortio-client|linkerd-proxy")
        QUERIES+=("$FORTIO_SERVER_NS|app=fortio-server|linkerd-proxy")
    fi
    log_message "DEBUG" "Write CSV headers"
    echo "timestamp,namespace,pod,container,cpu(n),memory(Ki)" > "$OUTPUT_FILE"
    log_message "DEBUG" "Collecting CPU/memory metrics every ${INTERVAL}..."
    while true; do
        TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        RAW_JSON=$(kubectl get --raw "/apis/metrics.k8s.io/v1beta1/pods")
        for QUERY in "${QUERIES[@]}"; do
            IFS='|' read -r NS_FILTER LABEL_FILTER CONTAINER_FILTER <<< "$QUERY"
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
                    echo "$TIMESTAMP,$POD_NAMESPACE,$POD_NAME,$CONTAINER_NAME,$CPU_NANO,$MEM_KI" >> "$OUTPUT_FILE"
                done
            done <<< "$MATCHING_ITEMS"
        done
        sleep "$INTERVAL"
    done
}

function http_load_test {
    OPTIND=1
    local OUTPUT_DIR="${RESULTS_DIR}"
    local MESH=""
    local QUERY_PER_SECOND="0" # 0 means MAX
    local UNIFORM_DISTRIBUTION="on"
    local NO_CATCHUP="on"
    local PAYLOAD_SIZE="0"
    while getopts "o:m:q:d:c:p:" opt; do
        case $opt in
            o) OUTPUT_DIR="$OPTARG" ;;
            m) MESH="$OPTARG" ;;
            q) QUERY_PER_SECOND="$OPTARG" ;;
            d) UNIFORM_DISTRIBUTION="$OPTARG" ;;
            c) NO_CATCHUP="$OPTARG" ;;
            p) PAYLOAD_SIZE="$OPTARG" ;;
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
    TARGET="http://${FORTIO_SERVER_SVC}.${FORTIO_SERVER_NS}.svc.${CLUSTER_DOMAIN}:${FORTIO_SERVER_PORT}"
    log_message "DEBUG" "Target URL: ${TARGET}"
    NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    METRICS_FILE="${OUTPUT_DIR}/metrics_${MESH}_${QUERY_PER_SECOND}_${PAYLOAD_SIZE}_${NOW}.csv"
    LATENCY_FILE="${OUTPUT_DIR}/latencies_${MESH}_${QUERY_PER_SECOND}_${PAYLOAD_SIZE}_${NOW}.json"
    log_message "DEBUG" "Start collecting metrics..."
    export_resource_metrics -m "$MESH" -o "$METRICS_FILE" &
    METRICS_PID=$!
    log_message "TECH" "kubectl exec -n $FORTIO_CLIENT_NS fortio-client -c fortio -- fortio load -c $CONNECTIONS -qps $QUERY_PER_SECOND -t $DURATION -payload-size $PAYLOAD_SIZE -json - $TARGET"
    kubectl exec -n $FORTIO_CLIENT_NS fortio-client -c fortio -- fortio load -c $CONNECTIONS -qps $QUERY_PER_SECOND -t $DURATION -payload-size $PAYLOAD_SIZE -json - "$TARGET" > "$LATENCY_FILE" 2>/dev/null
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Error connecting to ${URL}"
        kill $METRICS_PID
        exit 1
    fi
    kill $METRICS_PID
}

log_message "INFO" "Checking if the required tools are installed..."
if [ -z "$MESH" ] || { [ "$MESH" != "istio" ] && [ "$MESH" != "linkerd" ]; }; then
    log_message "ERROR" "Invalid or missing mesh type. Please set the MESH variable to 'istio' or 'linkerd'."
    exit 1
fi
if ! kubectl get pods -n $FORTIO_CLIENT_NS | grep -q "fortio-client"; then
    log_message "ERROR" "Fortio client is not deployed in namespace $FORTIO_CLIENT_NS"
    exit 1
fi
if ! kubectl get pods -n $FORTIO_SERVER_NS | grep -q "fortio-server"; then
    log_message "ERROR" "Fortio server is not deployed in namespace $FORTIO_SERVER_NS"
    exit 1
fi
if ! kubectl get pods -n "istio-system" | grep -q "istio"; then
    log_message "ERROR" "Istio is not deployed in namespace istio-system"
    exit 1
fi
if ! kubectl get pods -n "istio-system" | grep -q "ztunnel"; then
    log_message "ERROR" "ztunnel is not deployed in namespace istio-system"
    exit 1
fi
if ! kubectl get pods -n "linkerd" | grep -q "linkerd"; then
    log_message "ERROR" "Linkerd is not deployed in namespace linkerd"
    exit 1
fi
log_message "INFO" "All required tools are installed"
log_message "INFO" "Starting the experiment..."
log_message "DEBUG" "Deleting existing waypoints in $FORTIO_CLIENT_NS and $FORTIO_SERVER_NS"
istioctl waypoint delete --all -n $FORTIO_CLIENT_NS
istioctl waypoint delete --all -n $FORTIO_SERVER_NS
kubectl label ns $FORTIO_CLIENT_NS istio.io/dataplane-mode-
kubectl label ns $FORTIO_SERVER_NS istio.io/dataplane-mode-
log_message "DEBUG" "Wait for waypoint to be deleted in $FORTIO_CLIENT_NS and $FORTIO_SERVER_NS"
kubectl wait --for=delete pod -l service.istio.io/canonical-name=waypoint -n $FORTIO_CLIENT_NS --timeout=300s
log_message "DEBUG" "Deleting existing linkerd annotations in $FORTIO_CLIENT_NS and $FORTIO_SERVER_NS"
kubectl annotate ns $FORTIO_CLIENT_NS linkerd.io/inject-
kubectl annotate ns $FORTIO_SERVER_NS linkerd.io/inject-
kubectl rollout restart deploy -n $FORTIO_CLIENT_NS
if [[ $FORTIO_CLIENT_NS != "$FORTIO_SERVER_NS" ]]; then
    kubectl rollout restart deploy -n $FORTIO_SERVER_NS
fi
log_message "DEBUG" "Wait for fortio-client and fortio-server to be ready in $FORTIO_CLIENT_NS and $FORTIO_SERVER_NS"
kubectl wait --for=condition=ready pod -l app=fortio-client -n $FORTIO_CLIENT_NS --timeout=300s
kubectl wait --for=condition=ready pod -l app=fortio-server -n $FORTIO_SERVER_NS --timeout=300s
if [ "$MESH" == "linkerd" ]; then
    log_message "INFO" "Injecting Linkerd proxy into Fortio client and server"
    kubectl annotate ns $FORTIO_CLIENT_NS linkerd.io/inject=enabled
    kubectl rollout restart deploy -n $FORTIO_CLIENT_NS
    if [[ $FORTIO_CLIENT_NS != "$FORTIO_SERVER_NS" ]]; then
        kubectl annotate ns $FORTIO_SERVER_NS linkerd.io/inject=enabled
        kubectl rollout restart deploy -n $FORTIO_SERVER_NS
    fi
fi
if [ "$MESH" == "istio" ]; then
    log_message "INFO" "Deploying Waypoint into Fortio client and server"
    kubectl label ns $FORTIO_CLIENT_NS istio.io/dataplane-mode=ambient
    istioctl waypoint apply -n $FORTIO_CLIENT_NS --enroll-namespace --overwrite
    if [[ $FORTIO_CLIENT_NS != "$FORTIO_SERVER_NS" ]]; then
        kubectl label ns $FORTIO_SERVER_NS istio.io/dataplane-mode=ambient
        istioctl waypoint apply -n $FORTIO_SERVER_NS --enroll-namespace --overwrite
    fi
    sleep 5
    log_message "DEBUG" "Waiting for waypoint to be ready in $FORTIO_CLIENT_NS and $FORTIO_SERVER_NS"
    kubectl wait --for=condition=ready pod -l service.istio.io/canonical-name=waypoint -n $FORTIO_CLIENT_NS --timeout=300s
    if [[ $FORTIO_CLIENT_NS != "$FORTIO_SERVER_NS" ]]; then
        kubectl wait --for=condition=ready pod -l service.istio.io/canonical-name=waypoint -n $FORTIO_SERVER_NS --timeout=300s
    fi
fi
log_message "DEBUG" "Starting HTTP Max Throughput test"
OUTPUT_DIR="${RESULTS_DIR}/01_http_max_throughput"
if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR"
fi
http_load_test -o $OUTPUT_DIR -m $MESH -q "0" -d "off" -c "off"
log_message "DEBUG" "Wait 5 seconds to clean up the metrics"
sleep 5
log_message "DEBUG" "Starting HTTP Constant Throughput test"
OUTPUT_DIR="${RESULTS_DIR}/02_http_constant_throughput"
if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR"
fi
QUERY_PER_SECOND_LIST=(1 1000 10000)
for QUERY_PER_SECOND in "${QUERY_PER_SECOND_LIST[@]}"; do
    log_message "INFO" "Running experiment with ${QUERY_PER_SECOND} queries per second"
    http_load_test -o $OUTPUT_DIR -m $MESH -q $QUERY_PER_SECOND -d "on" -c "on"
    log_message "DEBUG" "Wait 5 seconds to clean up the metrics"
    sleep 5
done
log_message "DEBUG" "Starting HTTP Payload test"
OUTPUT_DIR="${RESULTS_DIR}/03_http_payload"
if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR"
fi
PAYLOAD_SIZE_LIST=(0 1000 10000)
for PAYLOAD_SIZE in "${PAYLOAD_SIZE_LIST[@]}"; do
    log_message "INFO" "Running experiment with ${PAYLOAD_SIZE} bytes payload"
    http_load_test -o $OUTPUT_DIR -m $MESH -q "100" -d "on" -c "on" -p $PAYLOAD_SIZE
    log_message "DEBUG" "Wait 5 seconds to clean up the metrics"
    sleep 5
done
# log_message "DEBUG" "Starting GRPC Max Throughput test"
# OUTPUT_DIR="${RESULTS_DIR}/04_grpc_max_throughput"
# if [ ! -d "$OUTPUT_DIR" ]; then
#     mkdir -p "$OUTPUT_DIR"
# fi
# grpc_load_test -o $OUTPUT_DIR -m $MESH -q "-1" -d "off" -c "off"
log_message "SUCCESS" "Experiment completed successfully!"