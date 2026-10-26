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

readonly CRUN_BIN_DIR=${BIN_DIR:-/usr/bin}

if ! "${CRUN_BIN_DIR}/crun_" --version 2>/dev/null | grep -q ^crun; then
    logger "crun not available, skipped"
    exit 0
fi

cp -a "${CRUN_BIN_DIR}/crun_" "${CRUN_BIN_DIR}/crun"
sed -i -E 's~default_runtime_name = ".+"~default_runtime_name = "crun"~' ../etc/config.toml

logger "init crun success"
