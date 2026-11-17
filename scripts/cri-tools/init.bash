#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright © 2022 sealos.
# Modified by cpaas-dev.

set -euo pipefail

BASEDIR=$(cd "$(dirname "$0")" || exit; pwd)
source "${BASEDIR}/../common.bash"

readonly CRICTL_BIN_DIR=${BIN_DIR:-/usr/bin}

# sealos itself calls crictl (cgroup driver detection, kubeadm image pre-pull).
# Removal is done by containerd/clean.bash, which owns crictl and /etc/crictl.yaml.
declare -a INSTALL_FILES=(
    "755 ${ROOTFS_DIR}/bin/crictl                ${CRICTL_BIN_DIR}/"
    "644 ${ROOTFS_DIR}/etc/cri-tools/crictl.yaml /etc/"
)

for entry in "${INSTALL_FILES[@]}"; do
    read -r mode src dest <<< "$entry"
    install -Dm"${mode}" -t "$dest" "$src"
done

logger "init cri-tools success"
