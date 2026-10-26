#!/usr/bin/env bash

# Copyright © 2022 sealos.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

BASEDIR=$(cd "$(dirname "$0")" || exit; pwd)
source "${BASEDIR}/common.bash"

readonly REG_DATA_DIR=${1:-/var/lib/registry}

# port
check_port_inuse() {
    command_exists ss || error "ss command not found, please install iproute2"
    logger "Check port kubelet port 10249..10259, reserved port 5050..5054 inuse. Please wait..."
    for port in {10249..10259} {5050..5054}; do
        if ss -tlnp "sport = :${port}" | grep -q LISTEN; then
            error "Port: $port occupied. Please turn off port service."
        fi
    done
}
check_port_inuse
logger "check port success"


# cri
if command_exists docker; then
    error "docker already exist, uninstall docker and retry"
fi
check_cmd_exits docker
check_file_exits /var/run/docker.sock
logger "check cri success"

# registry
check_dir_exits "${REG_DATA_DIR}"
logger "check registry success"

# apparmor
if ! command_exists apparmor_parser; then
    sed -i 's/disable_apparmor = false/disable_apparmor = true/g' "${BASEDIR}/../etc/config.toml"
    warn "Replace disable_apparmor = false to disable_apparmor = true"
fi
logger "check apparmor success"
