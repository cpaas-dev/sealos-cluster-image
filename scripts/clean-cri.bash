#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright © 2022 sealos.
# Modified by cpaas-dev.

set -euo pipefail

BASEDIR=$(cd "$(dirname "$0")" || exit; pwd)
source "${BASEDIR}/common.bash"

readonly CTD_STORAGE=${1:-/var/lib/containerd}

if ! bash "${BASEDIR}/containerd/clean.bash" "$CTD_STORAGE"; then
    error "====clean containerd failed!===="
fi

if ! bash "${BASEDIR}/image-cri-shim/clean.bash"; then
    error "====clean image-cri-shim failed!===="
fi

logger "clean cri success"
