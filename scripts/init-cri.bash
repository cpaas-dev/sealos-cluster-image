#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright © 2022 sealos.
# Modified by cpaas-dev.

set -euo pipefail

BASEDIR=$(cd "$(dirname "$0")" || exit; pwd)
source "${BASEDIR}/common.bash"

readonly REG_DOMAIN=${1:-sealos.hub}
readonly REG_PORT=${2:-5000}

# install image-cri-shim
if ! bash "${BASEDIR}/cri-tools/init.bash"; then
    error "====init cri-tools failed!===="
fi

if ! bash "${BASEDIR}/image-cri-shim/init.bash" "${REG_DOMAIN}" "${REG_PORT}"; then
    error "====init image-cri-shim failed!===="
fi

# install crun
if ! bash "${BASEDIR}/crun/init.bash" "${REG_DOMAIN}" "${REG_PORT}"; then
    error "====init crun failed!===="
fi

# install containerd
if ! bash "${BASEDIR}/runc/init.bash"; then
    error "====init runc failed!===="
fi

if ! bash "${BASEDIR}/containerd/init.bash" "${REG_DOMAIN}" "${REG_PORT}"; then
    error "====init containerd failed!===="
fi

logger "init cri success"
