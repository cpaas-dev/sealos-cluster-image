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

readonly REG_DATA_DIR=${1:-/var/lib/registry}
readonly REG_CONF_DIR=${2:-/etc/registry}
readonly REG_BIN_DIR=${BIN_DIR:-/usr/bin}

if systemctl list-unit-files registry.service &>/dev/null; then
    check_service stop registry
fi

declare -a CLEAN_FILES=(
    "${REG_BIN_DIR}/registry"
    /etc/systemd/system/registry.service
    /etc/registry.yml
)

declare -a CLEAN_DIRS=(
    "$REG_DATA_DIR"
    "$REG_CONF_DIR"
)

rm -f "${CLEAN_FILES[@]}"
rm -rf "${CLEAN_DIRS[@]}"

logger "clean registry success"
