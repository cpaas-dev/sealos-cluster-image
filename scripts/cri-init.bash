#!/usr/bin/env bash

# Copyright © 2022 sealos.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

BASEDIR=$(cd "$(dirname "$0")" || exit; pwd)
source "${BASEDIR}/common.bash"

if [[ ${SEALOS_ISOLATED_CRI:-} == true ]]; then
    exec bash "${BASEDIR}/isolated-init.bash"
fi

readonly REG_DOMAIN=${1:-sealos.hub}
readonly REG_PORT=${2:-5000}

# install image-cri-shim
if ! bash "${BASEDIR}/image-cri-shim-init.bash" "${REG_DOMAIN}" "${REG_PORT}"; then
    error "====init image-cri-shim failed!===="
fi

# install crun
if ! bash "${BASEDIR}/crun-init.bash" "${REG_DOMAIN}" "${REG_PORT}"; then
    error "====init crun failed!===="
fi

# install containerd
if ! bash "${BASEDIR}/containerd-init.bash" "${REG_DOMAIN}" "${REG_PORT}"; then
    error "====init containerd failed!===="
fi

logger "init cri success"
