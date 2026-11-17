#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright © 2022 sealos.
# Modified by cpaas-dev.

set -euo pipefail

BASEDIR=$(cd "$(dirname "$0")" || exit; pwd)
source "${BASEDIR}/common.bash"

if ! bash "${BASEDIR}/kubernetes/init.bash"; then
    error "====init kubelet failed!===="
fi

if ! bash "${BASEDIR}/oras/init.bash"; then
    error "====init oras failed!===="
fi

logger "init kube success"
