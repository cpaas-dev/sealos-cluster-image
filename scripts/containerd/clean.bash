#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright © 2022 sealos.
# Modified by cpaas-dev.

set -euo pipefail

BASEDIR=$(cd "$(dirname "$0")" || exit; pwd)
source "${BASEDIR}/../common.bash"

readonly CTD_STORAGE=${1:-/var/lib/containerd}
readonly CTD_BIN_DIR=${BIN_DIR:-/usr/bin}

if systemctl list-unit-files containerd.service &>/dev/null; then
    check_service stop containerd
fi

declare -a CLEAN_FILES=(
    "${CTD_BIN_DIR}/containerd-shim-runc-v2"
    "${CTD_BIN_DIR}/containerd-stress"
    "${CTD_BIN_DIR}/containerd"
    "${CTD_BIN_DIR}/crictl"
    "${CTD_BIN_DIR}/crun"
    "${CTD_BIN_DIR}/ctr"
    "${CTD_BIN_DIR}/runc"
    /etc/crictl.yaml
    /etc/systemd/system/containerd.service
)

declare -a CLEAN_DIRS=(
    "$CTD_STORAGE"
    /etc/containerd
    /opt/containerd
    /run/containerd
)

rm -f "${CLEAN_FILES[@]}"
rm -rf "${CLEAN_DIRS[@]}"

logger "clean containerd success"
