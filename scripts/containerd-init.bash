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

readonly REG_DOMAIN=${1:-sealos.hub}
readonly REG_PORT=${2:-5000}
readonly CTD_BIN_DIR=${BIN_DIR:-/usr/bin}
readonly CTD_CONF_DIR=/etc/containerd
readonly CTD_LIB_DIR=/opt/containerd

install -d -m 755 "$CTD_CONF_DIR" "$CTD_LIB_DIR" "${CTD_CONF_DIR}/certs.d/${REG_DOMAIN}:${REG_PORT}"

tar -zxf ../cri/libseccomp.tar.gz -C "$CTD_LIB_DIR"
echo "${CTD_LIB_DIR}/lib" >/etc/ld.so.conf.d/containerd.conf
ldconfig

tar -zxf ../cri/cri-containerd.tar.gz --strip-components 2 -C "$CTD_BIN_DIR"
tar -tf ../cri/cri-containerd.tar.gz | while read -r entry; do
    name="${entry##*/}"
    [[ -n "$name" ]] && chmod a+x "${CTD_BIN_DIR}/${name}"
done

declare -a INSTALL_FILES=(
    "644 ../etc/containerd.service /etc/systemd/system/"
    "644 ../etc/config.toml        ${CTD_CONF_DIR}/"
    "644 ../etc/hosts.toml         ${CTD_CONF_DIR}/certs.d/${REG_DOMAIN}:${REG_PORT}/"
)

for entry in "${INSTALL_FILES[@]}"; do
    read -r mode src dest <<< "$entry"
    install -Dm"${mode}" -t "$dest" "$src"
done

check_service start containerd
check_status containerd

logger "init containerd success"
