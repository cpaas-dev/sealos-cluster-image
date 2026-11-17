#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright © 2022 sealos.
# Modified by cpaas-dev.

set -euo pipefail

BASEDIR=$(cd "$(dirname "$0")" || exit; pwd)
source "${BASEDIR}/../common.bash"

readonly KUBE_BIN_DIR=${BIN_DIR:-/usr/bin}

if systemctl list-unit-files kubelet.service &>/dev/null; then
    check_service stop kubelet
fi

declare -a CLEAN_FILES=(
    "${KUBE_BIN_DIR}/kubelet-pre-start.sh"
    "${KUBE_BIN_DIR}/kubelet-post-stop.sh"
    "${KUBE_BIN_DIR}/kubeadm"
    "${KUBE_BIN_DIR}/kubectl"
    "${KUBE_BIN_DIR}/kubelet"
    /etc/systemd/system/kubelet.service
    /etc/NetworkManager/conf.d/99-sealos-unmanaged-devices.conf
)

declare -a CLEAN_DIRS=(
    /etc/systemd/system/kubelet.service.d
    /var/lib/kubelet
)

rm -f "${CLEAN_FILES[@]}"
rm -rf "${CLEAN_DIRS[@]}"

clean_sealos_sysctl() {
    if [[ -f /etc/sysctl.conf ]]; then
        sed -i '/ # sealos/d' /etc/sysctl.conf
    fi

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
