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

if systemctl list-unit-files image-cri-shim.service &>/dev/null; then
    check_service stop image-cri-shim
fi

declare -a CLEAN_FILES=(
    "${SHIM_BIN_DIR}/image-cri-shim"
    /etc/systemd/system/image-cri-shim.service
    /etc/image-cri-shim.yaml
    /var/lib/image-cri-shim
)

rm -f "${CLEAN_FILES[@]}"

logger "clean shim success"
