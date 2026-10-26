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

readonly KUBE_BIN_DIR=${BIN_DIR:-/usr/bin}

if systemctl list-unit-files kubelet.service &>/dev/null; then
    check_service stop kubelet
fi

declare -a CLEAN_FILES=(
    "${KUBE_BIN_DIR}/conntrack"
    "${KUBE_BIN_DIR}/kubelet-pre-start.sh"
    "${KUBE_BIN_DIR}/kubelet-post-stop.sh"
    "${KUBE_BIN_DIR}/kubeadm"
    "${KUBE_BIN_DIR}/kubectl"
    "${KUBE_BIN_DIR}/kubelet"
    /etc/systemd/system/kubelet.service
)

declare -a CLEAN_DIRS=(
    /etc/systemd/system/kubelet.service.d
    /var/lib/kubelet
)

rm -f "${CLEAN_FILES[@]}"
rm -rf "${CLEAN_DIRS[@]}"

clean_sealos_sysctl() {
    sed -i '/ # sealos/d' /etc/sysctl.conf

    local marker='### sealos begin ###|### sealos end ###'
    if grep -qE "$marker" /etc/security/limits.conf 2>/dev/null; then
        local first last
        first=$(grep -nE "$marker" /etc/security/limits.conf | head -n 1 | cut -d: -f1)
        last=$(grep -nE "$marker" /etc/security/limits.conf | tail -n 1 | cut -d: -f1)
        sed -i "${first},${last}d" /etc/security/limits.conf
    fi
}
clean_sealos_sysctl

logger "clean kubelet success"
