#!/bin/bash
# set -euo pipefail
IFS=$'\n\t'

# Used to perform load testing experiments on a kubernetes cluster
# running Fortio (https://github.com/fortio/fortio/)
# Contains 4 Experiments:
# Experiment 1: HTTP - Max Throughput
# Experiment 2: HTTP - Constant Throughput (Set QPS)
# Experiment 3: HTTP - Payload Size
# Experiment 4: GRPC - Max Throughput

# ---------------------------------------------------------
# Configuration
# ---------------------------------------------------------

# Global Experiment settings:
# CONNECTIONS: Sets the amount of connections to use for the load testing experiment
# DURATION: Control the duration expressed in human time format (e.g. 30s/1m/3h)
# RESOLUTION: Resolution of the histogram lowest buckets in seconds (default 0.001 i.e 1ms), use 1/10th of your expected typical latency
# MESH: The service mesh to use for the experiments (baseline, istio, linkerd, traefik, cilium)
# CONFIG_LOG_LEVEL: The log level to use for the experiments (ERROR, SUCCESS, TECH, WARNING, INFO, DEBUG)
CONNECTIONS=${CONNECTIONS:-"500"}
DURATION=${DURATION:-"1m"}
RESOLUTION=${RESOLUTION:-"0.0001"}
REPETITIONS=1
MESH="linkerd"
CONFIG_LOG_LEVEL="DEBUG"

# The host of the Fortio REST API which will generate the workload
LOAD_GEN_NS="default"
LOAD_GEN_SVC="load-generator-fortio"
LOAD_GEN_HOST="localhost"
LOAD_GEN_PORT="8080"
LOAD_GEN_ENDPOINT="http://${LOAD_GEN_HOST}:${LOAD_GEN_PORT}/fortio/rest/run"

# Kubernetes cluster domain
CLUSTER_DOMAIN="cluster.local"

# Configures the target of the load test
TARGET_NS="benchmark"
TARGET_SVC="target-fortio"
TARGET_PORT="8080"

# Services that fortio exposes (for load testing)
HTTP_ECHO_PORT="8080"
GRPC_PING_PORT="8079"

# Results Directory
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]:-$0}"; )" &> /dev/null && pwd 2> /dev/null; )";
RESULTS_DIR="$(cd ${SCRIPT_DIR} && cd .. && cd results && pwd 2> /dev/null)"

# ---------------------------------------------------------
# Experiment Functions
# ---------------------------------------------------------

# Runs an HTTP experiment to test maximum throughput (max QPS)
# Wrapper arround the run_http_experiment function
# Uniform distribution and nocatchup are off to maximise throughput
function run_http_experiment_max_throughput {
    OPTIND=1
    local MESH=""
    while getopts "m:" opt; do
        case $opt in
            m) MESH="$OPTARG" ;;
            *) echo "Invalid option: -$OPTARG" >&2; return 1 ;;
        esac
    done

    log_message "DEBUG" "Creating output directory for experiment results"
    OUTPUT_DIR="${RESULTS_DIR}/01_http_max_throughput"
    mkdir -p $OUTPUT_DIR
    if [[ $? -ne 0 ]]; then
        log_message "ERROR" "Failed to create output directory: $OUTPUT_DIR"
        return 1
    fi
    log_message "DEBUG" "Output Directory: $OUTPUT_DIR"
    log_message "DEBUG" "Running HTTP Max Throughput Experiment"
    http_load_test -o $OUTPUT_DIR -m $MESH -q "-1" -d "off" -c "off"
}

# Runs several HTTP experiments using pre-determined QPS values
# Wrapper arround the run_http_experiment function
# Uses a uniform distribution of request among threads
# And sets no catch up on to simulate constant throughput experiments
function run_http_experiment_set_qps {
    OPTIND=1
    local MESH=""
    while getopts "m:" opt; do
        case $opt in
            m) MESH="$OPTARG" ;;
            *) echo "Invalid option: -$OPTARG" >&2; return 1 ;;
        esac
    done

    log_message "DEBUG" "Setting up QPS values for the experiment (1, 100, 500, 1000)"
    QUERY_PER_SECOND_LIST=(1 100 500 1000)
    log_message "DEBUG" "Creating output directory for experiment results"
    OUTPUT_DIR="${RESULTS_DIR}/02_http_constant_throughput"
    mkdir -p $OUTPUT_DIR
    if [[ $? -ne 0 ]]; then
        log_message "ERROR" "Failed to create output directory: $OUTPUT_DIR"
        return 1
    fi
    log_message "DEBUG" "Output Directory: $OUTPUT_DIR"
    log_message "DEBUG" "Running HTTP Constant Throughput Experiment"
    for QUERY_PER_SECOND in "${QUERY_PER_SECOND_LIST[@]}"; do
        log_message "INFO" "Running experiment with ${QUERY_PER_SECOND} QPS"
        http_load_test -o $OUTPUT_DIR -m $MESH -q $QUERY_PER_SECOND -d "on" -c "on"
    done
}

# Runs several HTTP experiments in which the endpoint 
# will return random data of pre-determined sizes
# Wrapper arround the run_http_experiment function
# Uses a uniform distribution of request among threads
# And sets no catch up on to simulate constant throughput experiments
function run_http_experiment_payload {
    OPTIND=1
    local MESH=""
    while getopts "m:" opt; do
        case $opt in
            m) MESH="$OPTARG" ;;
            *) echo "Invalid option: -$OPTARG" >&2; return 1 ;;
        esac
    done
    
    log_message "DEBUG" "Setting up payload sizes for the experiment (0, 1000 [1KB], 10000 [10KB])"
    PAYLOAD_SIZE_LIST=(0 1000 10000)
    log_message "DEBUG" "Creating output directory for experiment results"
    OUTPUT_DIR="${RESULTS_DIR}/03_http_payload"
    mkdir -p $OUTPUT_DIR
    if [[ $? -ne 0 ]]; then
        log_message "ERROR" "Failed to create output directory: $OUTPUT_DIR"
        return 1
    fi
    log_message "DEBUG" "Output Directory: $OUTPUT_DIR"
    log_message "DEBUG" "Running HTTP Payload Experiment"
    for PAYLOAD_SIZE in "${PAYLOAD_SIZE_LIST[@]}"; do
        log_message "INFO" "Running experiment with ${PAYLOAD_SIZE} bytes payload"
        http_load_test -o $OUTPUT_DIR -m $MESH -q "100" -d "on" -c "on" -p $PAYLOAD_SIZE
    done
}

# Runs an GRPC experiment to test maximum throughput (max QPS)
# Wrapper arround the run_grpc_experiment function
# Uniform distribution and nocatchup are off to maximise throughput
function run_grpc_experiment_max_throughput {
    OPTIND=1
    local MESH=""
    while getopts "m:" opt; do
        case $opt in
            m) MESH="$OPTARG" ;;
            *) echo "Invalid option: -$OPTARG" >&2; return 1 ;;
        esac
    done

    log_message "DEBUG" "Creating output directory for experiment results"
    OUTPUT_DIR="${RESULTS_DIR}/04_grpc_max_throughput"
    mkdir -p $OUTPUT_DIR
    if [[ $? -ne 0 ]]; then
        log_message "ERROR" "Failed to create output directory: $OUTPUT_DIR"
        return 1
    fi
    log_message "DEBUG" "Output Directory: $OUTPUT_DIR"
    log_message "DEBUG" "Running GRPC Max Throughput Experiment"
    grpc_load_test -o $OUTPUT_DIR -m $MESH -q "-1" -d "off" -c "off"
}

function export_resource_metrics {
    OPTIND=1
    local OUTPUT_DIR="${RESULTS_DIR}"
    local MESH=""
    local QUERY_PER_SECOND=""
    while getopts "o:m:q:" opt; do
        case "$opt" in
            o) OUTPUT_DIR="$OPTARG" ;;
            m) MESH="$OPTARG" ;;
            q) QUERY_PER_SECOND="$OPTARG" ;;
            *) echo "Invalid option: -$OPTARG" >&2; return 1 ;;
        esac
    done

    if [[ -z $OUTPUT_DIR ]] || [[ -z $MESH ]] || [[ -z $QUERY_PER_SECOND ]]; then
        log_message "ERROR" "Output Directory, Mesh Configuration, and Queries Per Second are required!"
        exit 1
    fi

    local DURATION_SECONDS
    if [[ $DURATION == *m ]]; then
        DURATION_SECONDS=$(( ${DURATION%m} * 60 ))
    elif [[ $DURATION == *s ]]; then
        DURATION_SECONDS=${DURATION%s}
    else
        DURATION_SECONDS=$DURATION
    fi
    PROMETHEUS_URL=${PROMETHEUS_URL:-"http://localhost:9090"}
    TIMESTAMP_END=$(date +%s)
    TIMESTAMP_START=$(( TIMESTAMP_END - DURATION_SECONDS ))
    local DURATION_SEC=$(( TIMESTAMP_END - TIMESTAMP_START ))
    local STEP_SEC=$(( DURATION_SEC / 150 ))
    if (( STEP_SEC < 5 )); then
        STEP_SEC=5
    fi
    local STEP="${STEP_SEC}s"
    log_message "DEBUG" "Start timestamp: ${TIMESTAMP_START}"
    log_message "DEBUG" "End timestamp: ${TIMESTAMP_END}"
    log_message "DEBUG" "Total duration: ${DURATION_SEC} seconds"
    log_message "DEBUG" "Using a step of: ${STEP}"

    log_message "DEBUG" "Getting resource metrics for ${MESH} with ${QUERY_PER_SECOND} QPS with a step of ${STEP}"
    local PROXY_CPU_QUERY='sum(rate(container_cpu_usage_seconds_total{container!="", pod=~"(target-fortio|traefik-mesh-proxy|cilium|ztunnel|waypoint).*"}[2m])) by (pod, container)'
    local PROXY_MEMORY_QUERY='sum(rate(container_memory_working_set_bytes{container!="", pod=~"(target-fortio|traefik-mesh-proxy|cilium|ztunnel|waypoint).*"}[2m])) by (pod, container)'
    local CONTROLPLANE_CPU_QUERY='sum(rate(container_cpu_usage_seconds_total{container!="", pod=~"(linkerd-(controller|destination|identity|proxy-injector|tap|sp-validator)|istiod|cilium-operator).*"}[2m])) by (pod, container)'
    local CONTROLPLANE_MEMORY_QUERY='sum(rate(container_memory_working_set_bytes{container!="", pod=~"(linkerd-(controller|destination|identity|proxy-injector|tap|sp-validator)|istiod|cilium-operator).*"}[2m])) by (pod, container)'
        
    log_message "DEBUG" "Exporting resource metrics for ${MESH} with ${QUERY_PER_SECOND} QPS for CPU usage of Proxies"
    promtool query range -o json --start=${TIMESTAMP_START} --end=${TIMESTAMP_END} --step=${STEP} ${PROMETHEUS_URL} "${PROXY_CPU_QUERY}" | jq > "${OUTPUT_DIR}/cpu_proxy_${MESH}_${QUERY_PER_SECOND}_${NOW}.json"
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Error exporting resource metrics for ${MESH} with ${QUERY_PER_SECOND} QPS for CPU usage of Proxies"
        return 1
    fi
    log_message "DEBUG" "Exporting resource metrics for ${MESH} with ${QUERY_PER_SECOND} QPS for CPU usage of Proxies"
    log_message "DEBUG" "Exporting resource metrics for ${MESH} with ${QUERY_PER_SECOND} QPS for Memory usage of Proxies"
    promtool query range -o json --start=${TIMESTAMP_START} --end=${TIMESTAMP_END} --step=${STEP} ${PROMETHEUS_URL} "${PROXY_MEMORY_QUERY}" | jq > "${OUTPUT_DIR}/mem_proxy_${MESH}_${QUERY_PER_SECOND}_${NOW}.json"
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Error exporting resource metrics for ${MESH} with ${QUERY_PER_SECOND} QPS for Memory usage of Proxies"
        return 1
    fi
    log_message "DEBUG" "Exporting resource metrics for ${MESH} with ${QUERY_PER_SECOND} QPS for Memory usage of Proxies"
    log_message "DEBUG" "Exporting resource metrics for ${MESH} with ${QUERY_PER_SECOND} QPS for CPU usage of Control Plane"
    promtool query range -o json --start=${TIMESTAMP_START} --end=${TIMESTAMP_END} --step=${STEP} ${PROMETHEUS_URL} "${CONTROLPLANE_CPU_QUERY}" | jq > "${OUTPUT_DIR}/cpu_controlplane_${MESH}_${QUERY_PER_SECOND}_${NOW}.json"
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Error exporting resource metrics for ${MESH} with ${QUERY_PER_SECOND} QPS for CPU usage of Control Plane"
        return 1
    fi
    log_message "DEBUG" "Exporting resource metrics for ${MESH} with ${QUERY_PER_SECOND} QPS for CPU usage of Control Plane"
    log_message "DEBUG" "Exporting resource metrics for ${MESH} with ${QUERY_PER_SECOND} QPS for Memory usage of Control Plane"
    promtool query range -o json --start=${TIMESTAMP_START} --end=${TIMESTAMP_END} --step=${STEP} ${PROMETHEUS_URL} "${CONTROLPLANE_MEMORY_QUERY}" | jq > "${OUTPUT_DIR}/mem_controlplane_${MESH}_${QUERY_PER_SECOND}_${NOW}.json"
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Error exporting resource metrics for ${MESH} with ${QUERY_PER_SECOND} QPS for Memory usage of Control Plane"
        return 1
    fi
    log_message "DEBUG" "Exporting resource metrics for ${MESH} with ${QUERY_PER_SECOND} QPS for Memory usage of Control Plane"
    log_message "SUCCESS" "Resource Metrics Exported!"
}

# ---------------------------------------------------------
# General Functions
# ---------------------------------------------------------

function log_message {
    local STATUS=$1
    local MESSAGE=$2
    local NC='\033[0m'
    local RED='\033[0;31m'
    local GREEN='\033[0;32m'
    local YELLOW='\033[0;33m'
    local BLUE='\033[0;34m'
    local PURPLE='\033[0;35m'
    local CYAN='\033[0;36m'
    local DATE=$(date "+%H:%M:%S")
    local CONFIG_LOG_LEVEL="${CONFIG_LOG_LEVEL:-INFO}"
    case "$STATUS" in
        ERROR)
            if [[ "$CONFIG_LOG_LEVEL" == "ERROR" ]] ||
               [[ "$CONFIG_LOG_LEVEL" == "SUCCESS" ]] ||
               [[ "$CONFIG_LOG_LEVEL" == "TECH" ]] ||
               [[ "$CONFIG_LOG_LEVEL" == "WARNING" ]] ||
               [[ "$CONFIG_LOG_LEVEL" == "INFO" ]] ||
               [[ "$CONFIG_LOG_LEVEL" == "DEBUG" ]]; then
                echo -e "${RED}${DATE} [ERROR] ${MESSAGE}${NC}"
            fi
            ;;
        SUCCESS)
            if [[ "$CONFIG_LOG_LEVEL" == "SUCCESS" ]] ||
               [[ "$CONFIG_LOG_LEVEL" == "TECH" ]] ||
               [[ "$CONFIG_LOG_LEVEL" == "WARNING" ]] ||
               [[ "$CONFIG_LOG_LEVEL" == "INFO" ]] ||
               [[ "$CONFIG_LOG_LEVEL" == "DEBUG" ]]; then
                echo -e "${GREEN}${DATE} [SUCCESS] ${MESSAGE}${NC}"
            fi
            ;;
        TECH)
            if [[ "$CONFIG_LOG_LEVEL" == "TECH" ]] ||
               [[ "$CONFIG_LOG_LEVEL" == "INFO" ]] ||
               [[ "$CONFIG_LOG_LEVEL" == "DEBUG" ]]; then
                echo -e "${CYAN}${DATE} [TECH] ${MESSAGE}${NC}"
            fi
            ;;
        WARNING)
            if [[ "$CONFIG_LOG_LEVEL" == "WARNING" ]] ||
               [[ "$CONFIG_LOG_LEVEL" == "INFO" ]] ||
               [[ "$CONFIG_LOG_LEVEL" == "DEBUG" ]]; then
                echo -e "${YELLOW}${DATE} [WARN] ${MESSAGE}${NC}"
            fi
            ;;
        INFO)
            if [[ "$CONFIG_LOG_LEVEL" == "INFO" ]] ||
               [[ "$CONFIG_LOG_LEVEL" == "DEBUG" ]]; then
                echo -e "${BLUE}${DATE} [INFO] ${MESSAGE}${NC}"
            fi
            ;;
        DEBUG)
            if [[ "$CONFIG_LOG_LEVEL" == "DEBUG" ]]; then
                echo -e "${PURPLE}${DATE} [DEBUG] ${MESSAGE}${NC}"
            fi
            ;;
        *)
            echo -e "${NC}${DATE} [UNKNOWN] ${MESSAGE}${NC}"
            ;;
    esac
}

function check_dependency {
    OPTIND=1
    local COMMAND=""
    while getopts "c:" opt; do
        case "$opt" in
            c) COMMAND="$OPTARG" ;;
            *) echo "Invalid option: -$OPTARG" >&2; return 1 ;;
        esac
    done

    if [[ -z "$COMMAND" ]]; then
        echo "No command specified with -c option" >&2
        return 1
    fi

    log_message "DEBUG" "Checking if '$COMMAND' is installed..."
    if ! command -v "$COMMAND" &> /dev/null; then
        log_message "ERROR" "'$COMMAND' not found, exiting..."
        return 1
    fi
    log_message "DEBUG" "'$COMMAND' is installed."
}

function port_forward_fortio {
    log_message "INFO" "Port forward to Fortio load generator REST API"
    log_message "DEBUG" "Creating temporary file to store output"
    output=$(mktemp "${TMPDIR:-/tmp/}$(basename $0)-fortio.XXX")
    log_message "DEBUG" "Output file: $output"
    log_message "DEBUG" "Start the port forwarding process"
    kubectl port-forward -n ${LOAD_GEN_NS} svc/${LOAD_GEN_SVC} ${LOAD_GEN_PORT}:${LOAD_GEN_PORT} &> $output &
    pid=$!
    log_message "DEBUG" "Port forwarding process PID: $pid"
    log_message "DEBUG" "Wait until the port forwarding process is ready to accept connections"
    until grep -q -i "Forwarding from" $output
    do       
        # Check if port forwarding process is still runningj
        if ! ps $pid > /dev/null 
        then
            echo "Port Forwarding stopped" >&2
            exit 1
        fi
        sleep 1
    done
    sleep 1
    log_message "INFO" "Port Forwarding Fortio load generator REST API Done!"
}

function port_forward_prometheus {
    log_message "INFO" "Port forward to Prometheus REST API"
    log_message "DEBUG" "Creating temporary file to store output"
    output=$(mktemp "${TMPDIR:-/tmp/}$(basename $0)-prom.XXX")
    log_message "DEBUG" "Output file: $output"
    log_message "DEBUG" "Start the port forwarding process"
    kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090 &> $output &
    pid=$!
    log_message "DEBUG" "Port forwarding process PID: $pid"
    log_message "DEBUG" "Wait until the port forwarding process is ready to accept connections"
    until grep -q -i "Forwarding from" $output
    do       
        # Check if port forwarding process is still runningj
        if ! ps $pid > /dev/null 
        then
            echo "Port Forwarding stopped" >&2
            exit 1
        fi

        sleep 1
    done
    sleep 1
    log_message "INFO" "Port Forwarding Prometheus REST API Done!"
}

# Run an HTTP experiment 
# arg1: Output Directory for experiment results
# arg2: Mesh Configuration e.g. "linkerd"
# arg3: Queries Per Second e.g. 3000 (use -1 for unlimited)
# arg4 (optional): Uniform Distribution of requests among threads (default: on)
# arg5 (optional): Do not try to catch up to QPS is falling behind (default: on)
# arg6 (optional): Payload Size in bytes (default: 0)
function http_load_test {
    OPTIND=1
    local OUTPUT_DIR="${RESULTS_DIR}"
    local MESH=""
    local QUERY_PER_SECOND=""
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
    if [[ $QUERY_PER_SECOND -lt 0 ]]; then
        QUERY_PER_SECOND="MAX"
    fi

    # In order to used traefik meshed services it has to use .traefik.mesh DNS
    TARGET="http://${TARGET_SVC}.${TARGET_NS}.svc.${CLUSTER_DOMAIN}:${HTTP_ECHO_PORT}"
    if [[ $MESH == *"traefik"* ]]; then
        TARGET="http://${TARGET_SVC}.${TARGET_NS}.traefik.mesh:${HTTP_ECHO_PORT}"
    fi

    # If it is a payload experiment, let the echo server return a payload of
    # the specified size in bytes
    if [[ $MESH != *"traefik"* ]]; then
        TARGET="${TARGET}?size=${PAYLOAD_SIZE}"
    fi

    log_message "INFO" "-----------------------------"
    log_message "INFO" "Query per secord: ${QUERY_PER_SECOND}"
    log_message "INFO" "Uniform Distribution: ${UNIFORM_DISTRIBUTION}"
    log_message "INFO" "No Catchup: ${NO_CATCHUP}"
    log_message "INFO" "Connections: ${CONNECTIONS}"
    log_message "INFO" "Duration: ${DURATION}"
    log_message "INFO" "Payload Size: ${PAYLOAD_SIZE}"
    log_message "INFO" "-----------------------------"

    log_message "DEBUG" "Setting up Fortio REST API URL with query parameters to control the experiment settings"
    URL="${LOAD_GEN_ENDPOINT}?url=${TARGET}&qps=${QUERY_PER_SECOND}&t=${DURATION}&c=${CONNECTIONS}&uniform=${UNIFORM_DISTRIBUTION}&nocatchup=${NO_CATCHUP}&r=${RESOLUTION}&labels=${MESH};${PAYLOAD_SIZE}"
    log_message "DEBUG" "Fortio REST API URL: $URL"
    log_message "DEBUG" "Running experiments and saving results to output json"
    for REPETITION in $(seq ${REPETITIONS}); do
        NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        FILE_NAME="http_${MESH}_${QUERY_PER_SECOND}_${PAYLOAD_SIZE}_${REPETITION}_${NOW}.json"
        log_message "INFO" "Running experiment #${REPETITION} @ ${NOW}"
        log_message "DEBUG" "Connecting to ${URL}"
        RESPONSE=$(curl -s "$URL")
        log_message "DEBUG" "Save and export resource metrics"
        export_resource_metrics -o $OUTPUT_DIR -m $MESH -q $QUERY_PER_SECOND
        if [ $? -eq 0 ]; then
            echo $RESPONSE > "${OUTPUT_DIR}/${FILE_NAME}"
        else
            log_message "ERROR" "Error connecting to ${URL}"
            exit 1
        fi
    done
    log_message "SUCCESS" "HTTP Experiment Done!"
}

# Run a GPRC experiment 
# arg1: Output Directory for experiment results
# arg2: Mesh Configuration e.g. "linkerd"
# arg3: Queries Per Second e.g. 3000 (use -1 for unlimited)
# arg4 (optional): Uniform Distribution of requests among threads (default: on)
# arg5 (optional): Do not try to catch up to QPS is falling behind (default: on)
function grpc_load_test {
    OPTIND=1
    local OUTPUT_DIR="${RESULTS_DIR}"
    local MESH=""
    local QUERY_PER_SECOND=""
    local UNIFORM_DISTRIBUTION="on"
    local NO_CATCHUP="on"
    while getopts "o:m:q:d:c" opt; do
        case $opt in
            o) OUTPUT_DIR="$OPTARG" ;;
            m) MESH="$OPTARG" ;;
            q) QUERY_PER_SECOND="$OPTARG" ;;
            d) UNIFORM_DISTRIBUTION="$OPTARG" ;;
            c) NO_CATCHUP="$OPTARG" ;;
            *) echo "Invalid option: -$OPTARG" >&2; return 1 ;;
        esac
    done

    if [[ -z $OUTPUT_DIR ]] || [[ -z $MESH ]] || [[ -z $QUERY_PER_SECOND ]]; then
        log_message "ERROR" "Output Directory, Mesh Configuration, and Queries Per Second are required!"
        exit 1
    fi
    if [[ $QUERY_PER_SECOND -lt 0 ]]; then
        QUERY_PER_SECOND="MAX"
    fi

    # In order to used traefik meshed services it has to use .traefik.mesh DNS
    TARGET="http://${TARGET_SVC}.${TARGET_NS}.svc.${CLUSTER_DOMAIN}:${GRPC_PING_PORT}"
    if [[ $MESH == *"traefik"* ]]
    then
        TARGET="http://${TARGET_SVC}.${TARGET_NS}.traefik.mesh:${GRPC_PING_PORT}"
    fi

    log_message "INFO" "-----------------------------"
    log_message "INFO" "Query per secord: ${QUERY_PER_SECOND}"
    log_message "INFO" "Uniform Distribution: ${UNIFORM_DISTRIBUTION}"
    log_message "INFO" "No Catchup: ${NO_CATCHUP}"
    log_message "INFO" "Connections: ${CONNECTIONS}"
    log_message "INFO" "Duration: ${DURATION}"
    log_message "INFO" "Payload Size: ${PAYLOAD_SIZE}"
    log_message "INFO" "-----------------------------"

    log_message "DEBUG" "Setting up Fortio REST API URL with query parameters to control the experiment settings"
    URL="${LOAD_GEN_ENDPOINT}?url=${TARGET}&qps=${QPS}&t=${DURATION}&c=${CONNECTIONS}&uniform=${UNIFORM}&nocatchup=${NOCATCHUP}&r=${RESOLUTION}&runner=grpc&labels=${MESH};${PAYLOAD_SIZE}"
    log_message "DEBUG" "Fortio REST API URL: $URL"
    log_message "DEBUG" "Running experiments and saving results to output json"

    for REPETITION in $(seq ${REPETITIONS}); do
        NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        FILE_NAME="grpc_${MESH}_${QUERY_PER_SECOND}_${REPETITION}_${NOW}.json"
        log_message "INFO" "Running experiment #${REPETITION} @ ${NOW}"
        log_message "DEBUG" "Connecting to ${URL}"
        RESPONSE=$(curl -s "$URL")
        log_message "DEBUG" "Save and export resource metrics"
        export_resource_metrics -o $OUTPUT_DIR -m $MESH -q $QUERY_PER_SECOND
        if [ $? -eq 0 ]; then
            echo $RESPONSE > "${OUTPUT_DIR}/${FILE_NAME}"
        else
            log_message "ERROR" "Error connecting to ${URL}"
            exit 1
        fi
    done
    log_message "SUCCESS" "GRPC Experiment Done!"
}

function main {
    OPTIND=1
    local MESH=""
    while getopts "m:" opt; do
        case $opt in
            m) MESH="$OPTARG" ;;
            *) echo "Invalid option: -$OPTARG" >&2; return 1 ;;
        esac
    done

    log_message "DEBUG" "Mesh: $MESH"
    if [[ -z $MESH ]] || [[ $MESH != "baseline" ]] && [[ $MESH != "istio" ]] && [[ $MESH != "linkerd" ]] && [[ $MESH != "traefik" ]] && [[ $MESH != "cilium" ]]; then
        log_message "ERROR" "Invalid Mesh: $MESH"
        return 1
    fi

    log_message "INFO" "-----------------------------"
    log_message "INFO" "+++ Configurations +++"
    log_message "INFO" "-----------------------------"
    log_message "INFO" "Mesh: ${MESH}"
    log_message "INFO" "Connections: ${CONNECTIONS}"
    log_message "INFO" "Duration: ${DURATION}"
    log_message "INFO" "Resolution: ${RESOLUTION}"
    log_message "INFO" "Repetitions: ${REPETITIONS}"
    log_message "INFO" "-----------------------------"

    log_message "INFO" "Checking Requirements..."
    check_dependency -c curl
    check_dependency -c kubectl
    check_dependency -c grep
    check_dependency -c promtool
    log_message "SUCCESS" "Requirements installed!"

    log_message "INFO" "Setting up experiments..."
    port_forward_fortio
    port_forward_prometheus
    log_message "SUCCESS" "Experiments setup!"

    # ------------------
    # Actual experiments
    # ------------------
    log_message "INFO" "Stopping all running experiments..."
    curl -s "http://${LOAD_GEN_HOST}:${LOAD_GEN_PORT}/fortio/rest/stop" &>/dev/null
    sleep 5

    # # 1: HTTP - Max Throughput
    log_message "INFO" "Running HTTP Max Throughput Experiment"
    run_http_experiment_max_throughput -m $MESH
    sleep 30

    # # 2: HTTP - Set QPS
    log_message "INFO" "Running HTTP Constant Throughput Experiment"
    run_http_experiment_set_qps -m $MESH
    sleep 30

    # # 3: HTTP - Payload
    log_message "INFO" "Running HTTP Payload Experiment"
    run_http_experiment_payload -m $MESH
    sleep 30

    # # 4: GRPC - Max Throughput
    log_message "INFO" "Running GRPC Max Throughput Experiment"
    run_grpc_experiment_max_throughput -m $MESH
    log_message "SUCCESS" "All Experiments Done!"
}

# Kill backbground jobs (port forwarding on exit)
trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT

main -m $MESH