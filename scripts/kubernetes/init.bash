#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright © 2022 sealos.
# Modified by cpaas-dev.

set -euo pipefail

BASEDIR=$(cd "$(dirname "$0")" || exit; pwd)
source "${BASEDIR}/../common.bash"

readonly KUBE_BIN_DIR=${BIN_DIR:-/usr/bin}

ensure_localhost_hosts() {
    grep 127.0.0.1 <(grep localhost /etc/hosts) || echo "127.0.0.1 localhost" >>/etc/hosts
    grep ::1 <(grep localhost /etc/hosts) || echo "::1 localhost" >>/etc/hosts
}

apply_sealos_sysctl() {
    # Drop lines from a previous run first so re-running init stays idempotent
    if [[ -f /etc/sysctl.conf ]]; then
        sed -i '/ # sealos$/d' /etc/sysctl.conf
    fi
    sort -u "${ROOTFS_DIR}"/etc/kubernetes/sysctl.d/*.conf | grep -vE '^(#|$)' | while read -r str; do
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
        grep -hvE '^#|^$' "${ROOTFS_DIR}"/etc/kubernetes/limits.d/*.conf | awk '{print $1,$2,$3,$4}'
        echo '### sealos end ###'
    } >>/etc/security/limits.conf
}

ensure_localhost_hosts
disable_firewalld

# Keep NetworkManager off CNI / kube-proxy interfaces; reload only if NM runs.
install -Dm644 -t /etc/NetworkManager/conf.d/ \
    "${ROOTFS_DIR}"/etc/kubernetes/NetworkManager/conf.d/99-sealos-unmanaged-devices.conf
if systemctl is-active --quiet NetworkManager; then
    systemctl reload NetworkManager
fi

declare -a INSTALL_FILES=(
    "755 ${ROOTFS_DIR}/bin/kubeadm                    ${KUBE_BIN_DIR}/"
    "755 ${ROOTFS_DIR}/bin/kubectl                    ${KUBE_BIN_DIR}/"
    "755 ${ROOTFS_DIR}/bin/kubelet                    ${KUBE_BIN_DIR}/"
    "755 ${ROOTFS_DIR}/scripts/kubernetes/kubelet-pre-start.sh  ${KUBE_BIN_DIR}/"
    "755 ${ROOTFS_DIR}/scripts/kubernetes/kubelet-post-stop.sh  ${KUBE_BIN_DIR}/"
    "644 ${ROOTFS_DIR}/etc/kubernetes/kubelet.service /etc/systemd/system/"
    # sealos upgrade (>= 1.27) seds this exact path
    "644 ${ROOTFS_DIR}/etc/kubernetes/kubelet.service.d/10-kubeadm.conf /etc/systemd/system/kubelet.service.d/"
)

for entry in "${INSTALL_FILES[@]}"; do
    read -r mode src dest <<< "$entry"
    install -Dm"${mode}" -t "$dest" "$src"
done

apply_sealos_sysctl
apply_sealos_limits

install -d -m 755 /var/lib/kubelet

readonly WAIT_INTERVAL=10
readonly WAIT_RETRIES=20

# The pause image is pulled through image-cri-shim, which may still be starting.
# `crictl images` goes through the shim's image API (image-endpoint in
# /etc/crictl.yaml), so success means the shim is actually serving.
wait_for_image_cri_shim() {
    local shim_sock="$1" i
    for ((i = 1; i <= WAIT_RETRIES; i++)); do
        if crictl --image-endpoint "unix://${shim_sock}" images >/dev/null 2>&1; then
            logger "image-cri-shim is ready at ${shim_sock}"
            return 0
        fi
        warn "waiting for image-cri-shim at ${shim_sock}, attempt ${i}/${WAIT_RETRIES}"
        sleep "${WAIT_INTERVAL}"
    done
    error "timed out after $((WAIT_INTERVAL * WAIT_RETRIES))s waiting for image-cri-shim at ${shim_sock} (check: systemctl status image-cri-shim)"
}

# shellcheck disable=SC2154
wait_for_image_cri_shim "${SEALOS_SYS_IMAGE_ENDPOINT}"

# shellcheck disable=SC2154
logger "pull pause image ${registryDomain}:${registryPort}/${sandboxImage}"
crictl pull "${registryDomain}:${registryPort}/${sandboxImage}"

systemctl daemon-reload
systemctl enable kubelet

logger "init kubelet success"
