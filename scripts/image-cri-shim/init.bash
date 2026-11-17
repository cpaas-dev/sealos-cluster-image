#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright © 2022 sealos.
# Modified by cpaas-dev.

set -euo pipefail

BASEDIR=$(cd "$(dirname "$0")" || exit; pwd)
source "${BASEDIR}/../common.bash"

readonly SHIM_BIN_DIR=${BIN_DIR:-/usr/bin}

declare -a INSTALL_FILES=(
    "644 ${ROOTFS_DIR}/etc/image-cri-shim/image-cri-shim.service /etc/systemd/system/"
    "644 ${ROOTFS_DIR}/etc/image-cri-shim/image-cri-shim.yaml    /etc/"
    "755 ${ROOTFS_DIR}/bin/image-cri-shim         ${SHIM_BIN_DIR}/"
)

for entry in "${INSTALL_FILES[@]}"; do
    read -r mode src dest <<< "$entry"
    install -Dm"${mode}" -t "$dest" "$src"
done

check_service start image-cri-shim
check_status image-cri-shim

logger "init shim success"
