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

ensure_localhost_hosts() {
    grep 127.0.0.1 <(grep localhost /etc/hosts) || echo "127.0.0.1 localhost" >>/etc/hosts
    grep ::1 <(grep localhost /etc/hosts) || echo "::1 localhost" >>/etc/hosts
}

apply_sealos_sysctl() {
    sort -u ../etc/sysctl.d/*.conf | grep -v '^$' | while read -r str; do
        local k="${str%=*}"
        local v="${str#*=}"
        echo "${k}=${v} # sealos"
    done >>/etc/sysctl.conf
    bash "${KUBE_BIN_DIR}/kubelet-pre-start.sh"
}

apply_sealos_limits() {
    local marker='### sealos begin ###|### sealos end ###'
    if grep -qE "$marker" /etc/security/limits.conf 2>/dev/null; then
        return
    fi
    {
        echo '### sealos begin ###'
        grep -hvE '^#|^$' ../etc/limits.d/*.conf | awk '{print $1,$2,$3,$4}'
        echo '### sealos end ###'
    } >>/etc/security/limits.conf
}

ensure_localhost_hosts
disable_firewalld

declare -a INSTALL_FILES=(
    "755 ../scripts/kubelet-pre-start.sh  ${KUBE_BIN_DIR}/"
    "755 ../scripts/kubelet-post-stop.sh  ${KUBE_BIN_DIR}/"
    "644 ../etc/kubelet.service            /etc/systemd/system/"
)

for entry in "${INSTALL_FILES[@]}"; do
    read -r mode src dest <<< "$entry"
    install -Dm"${mode}" -t "$dest" "$src"
done

cp -a ../bin/* "${KUBE_BIN_DIR}/"
cp -a ../etc/systemd/system /etc/systemd

apply_sealos_sysctl
apply_sealos_limits

install -d -m 755 /var/lib/kubelet

# shellcheck disable=SC2154
logger "pull pause image ${registryDomain}:${registryPort}/${sandboxImage}"
crictl pull "${registryDomain}:${registryPort}/${sandboxImage}"

systemctl daemon-reload
systemctl enable kubelet

logger "init kubelet success"
