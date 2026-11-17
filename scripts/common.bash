#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright © 2022 sealos.
# Modified by cpaas-dev.

# Absolute path of the sealos rootfs (parent of this scripts directory),
# resolved from this file's location so callers never depend on the cwd.
# shellcheck disable=SC2034 # used by the scripts that source this file
ROOTFS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd) || exit 1
readonly ROOTFS_DIR

timestamp() {
    date +"%Y-%m-%d %T"
}

error() {
    flag=$(timestamp)
    echo -e "\033[31m ERROR [$flag] >> $* \033[0m"
    exit 1
}

logger() {
    flag=$(timestamp)
    echo -e "\033[36m INFO [$flag] >> $* \033[0m"
}

warn() {
    flag=$(timestamp)
    echo -e "\033[33m WARN [$flag] >> $* \033[0m"
}

debug() {
    flag=$(timestamp)
    echo -e "\033[32m DEBUG [$flag] >> $* \033[0m"
}

check_service() {
    local action=$1
    shift
    systemctl daemon-reload
    case $action in
    start)
        systemctl enable "$@"
        ;;
    stop)
        systemctl disable "$@"
        ;;
    *)
        error "service action error, only start/stop."
        ;;
    esac
    systemctl "$action" "$@"
}

check_status() {
    for unit; do
        logger "Health check $unit!"
        if systemctl is-active --quiet "$unit"; then
            logger "$unit is running"
        else
            error "$unit status is error"
        fi
    done
}

ubuntu_dns() {
    # shellcheck disable=SC1091
    os="$(. /etc/os-release && echo "$ID")"
    if echo "$os" | grep "ubuntu" >/dev/null 2>&1; then
        if systemctl status systemd-resolved.service >/dev/null 2>&1; then
            systemctl stop systemd-resolved.service
            systemctl disable systemd-resolved.service
            rm /etc/resolv.conf
            cp /run/systemd/resolve/resolv.conf /etc/resolv.conf
        fi
        logger "steup operation_ubuntu finished"
    fi
}

version_ge() {
    test "$(echo "$@" | tr ' ' '\n' | sort -rV | head -n 1)" == "$1"
}

get_distribution() {
    lsb_dist=""
    # Every system that we officially support has /etc/os-release
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        lsb_dist="$(. /etc/os-release && echo "$ID")"
    fi
    # Returning an empty string here should be alright since the
    # case statements don't act unless you provide an actual value
    echo "$lsb_dist"
}

# Only touch the firewall tools that are actually installed on the host.
disable_firewalld() {
    if command_exists ufw; then
        ufw disable
    fi
    if systemctl list-unit-files firewalld.service &>/dev/null; then
        systemctl stop firewalld
        systemctl disable firewalld
    fi
}

command_exists() {
    command -v "$@" >/dev/null 2>&1
}

check_cmd_exits() {
    for cmd; do
        if which "$cmd"; then
            error "The machine $cmd is not clean. Please clean $cmd the system."
        fi
    done
}

check_file_exits() {
    for f; do
        if [[ -f $f ]]; then
            error "The machine $f is not clean. Please clean $f the system."
        fi
    done
}

check_dir_exits() {
    for d; do
        if [[ -d $d ]]; then
            error "The machine $d is not clean. Please clean $d the system."
        fi
    done
}
