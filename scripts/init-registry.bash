#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright © 2022 sealos.
# Modified by cpaas-dev.

set -euo pipefail

BASEDIR=$(cd "$(dirname "$0")" || exit; pwd)
source "${BASEDIR}/common.bash"

readonly REG_DATA_DIR=$1
readonly REG_CONF_DIR=$2

if ! bash "${BASEDIR}/registry/init.bash" "$REG_DATA_DIR" "$REG_CONF_DIR"; then
    error "====init registry failed!===="
fi
