#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright © 2022 sealos.
# Modified by cpaas-dev.

set -euo pipefail

BASEDIR=$(cd "$(dirname "$0")" || exit; pwd)
source "${BASEDIR}/../common.bash"

readonly SHIM_BIN_DIR=${BIN_DIR:-/usr/bin}

if systemctl list-unit-files image-cri-shim.service &>/dev/null; then
    check_service stop image-cri-shim
fi

declare -a CLEAN_FILES=(
    "${SHIM_BIN_DIR}/image-cri-shim"
    /etc/systemd/system/image-cri-shim.service
    /etc/image-cri-shim.yaml
)

declare -a CLEAN_DIRS=(
    /var/lib/image-cri-shim
)

rm -f "${CLEAN_FILES[@]}"
rm -rf "${CLEAN_DIRS[@]}"

logger "clean shim success"
