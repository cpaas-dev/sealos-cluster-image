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

readonly SHIM_BIN_DIR=${BIN_DIR:-/usr/bin}

declare -a INSTALL_FILES=(
    "644 ${BASEDIR}/../etc/image-cri-shim.service /etc/systemd/system/"
    "644 ${BASEDIR}/../etc/image-cri-shim.yaml    /etc/"
    "755 ${BASEDIR}/../bin/image-cri-shim         ${SHIM_BIN_DIR}/"
)

for entry in "${INSTALL_FILES[@]}"; do
    read -r mode src dest <<< "$entry"
    install -Dm"${mode}" -t "$dest" "$src"
done

[[ -f ${BASEDIR}/../etc/crictl.yaml ]] && install -Dm644 -t /etc/ "${BASEDIR}/../etc/crictl.yaml"

check_service start image-cri-shim
check_status image-cri-shim

logger "init shim success"
