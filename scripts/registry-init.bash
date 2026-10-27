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
readonly REG_CONF_DIR=${2:-/etc/registry}
readonly REG_BIN_DIR=${BIN_DIR:-/usr/bin}

install -d -m 755 "${REG_DATA_DIR}" "${REG_CONF_DIR}"

declare -a INSTALL_FILES=(
    "755 ${BASEDIR}/../bin/zot            ${REG_BIN_DIR}/"
    "644 ${BASEDIR}/../etc/registry.service    /etc/systemd/system/"
    "644 ${BASEDIR}/../etc/registry_config.yml ${REG_CONF_DIR}/"
    "644 ${BASEDIR}/../etc/registry_htpasswd   ${REG_CONF_DIR}/"
    "644 ${BASEDIR}/../etc/registry/config.json ${REG_CONF_DIR}/"
)

for entry in "${INSTALL_FILES[@]}"; do
    read -r mode src dest <<< "$entry"
    install -Dm"${mode}" -t "$dest" "$src"
done

if [[ ${SEALOS_ISOLATED_CRI:-} != true ]] && [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
    sed -i 's#SELINUX=enforcing#SELINUX=disabled#g' /etc/selinux/config
    setenforce 0
fi

check_service start registry
check_status registry

logger "init registry success"
