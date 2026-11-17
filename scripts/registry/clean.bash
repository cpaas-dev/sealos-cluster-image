#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright © 2022 sealos.
# Modified by cpaas-dev.

set -euo pipefail

BASEDIR=$(cd "$(dirname "$0")" || exit; pwd)
source "${BASEDIR}/../common.bash"

readonly REG_DATA_DIR=$1
readonly REG_CONF_DIR=$2
readonly REG_BIN_DIR=${BIN_DIR:-/usr/bin}

if systemctl list-unit-files registry.service &>/dev/null; then
    check_service stop registry
fi

declare -a CLEAN_FILES=(
    "${REG_BIN_DIR}/registry"
    /etc/systemd/system/registry.service
)

# REG_DATA_DIR is normally a symlink to <rootfs>/registry; rm -rf on the link
# (no trailing slash) removes the link only, not the image data behind it.
declare -a CLEAN_DIRS=(
    "${REG_DATA_DIR}"
    "${REG_CONF_DIR}"
)

rm -f "${CLEAN_FILES[@]}"
rm -rf "${CLEAN_DIRS[@]}"
systemctl daemon-reload

logger "clean registry success"
