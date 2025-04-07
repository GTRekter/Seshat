#!/bin/bash
###################################################################################################################
# Purpose       : Provides reusable utility functions for consistent logging with color-coded output and log levels.
#                 Designed to be sourced by other scripts to improve readability and maintainability of logs.
#
# Created on    : 12.10.24
# Updated on    : 12.10.24
# Made with ❤️  : Ivan Porta
# Version       : 1.0
###################################################################################################################
function log_message() {
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