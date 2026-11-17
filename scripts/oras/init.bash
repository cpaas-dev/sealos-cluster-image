#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright © 2022 sealos.
# Modified by cpaas-dev.

set -euo pipefail

BASEDIR=$(cd "$(dirname "$0")" || exit; pwd)
source "${BASEDIR}/../common.bash"

readonly ORAS_BIN_DIR=${BIN_DIR:-/usr/bin}

install -Dm755 -t "${ORAS_BIN_DIR}/" "${ROOTFS_DIR}"/bin/oras

logger "init oras success"
