#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright © 2022 sealos.
# Modified by cpaas-dev.

set -euo pipefail

BASEDIR=$(cd "$(dirname "$0")" || exit; pwd)
source "${BASEDIR}/common.bash"

if ! bash "${BASEDIR}/oras/clean.bash"; then
    error "====clean oras failed!===="
fi

if ! bash "${BASEDIR}/kubernetes/clean.bash"; then
    error "====clean kubelet failed!===="
fi

logger "clean kube success"
