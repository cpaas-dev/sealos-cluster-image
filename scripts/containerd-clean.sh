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

readonly CTD_STORAGE=${1:-/var/lib/containerd}
readonly CTD_BIN_DIR=${BIN_DIR:-/usr/bin}

if systemctl list-unit-files containerd.service &>/dev/null; then
    check_service stop containerd
fi

declare -a CLEAN_FILES=(
    "${CTD_BIN_DIR}/containerd"
    "${CTD_BIN_DIR}/containerd-stress"
    "${CTD_BIN_DIR}/containerd-shim"
    "${CTD_BIN_DIR}/containerd-shim-runc-v1"
    "${CTD_BIN_DIR}/containerd-shim-runc-v2"
    "${CTD_BIN_DIR}/crictl"
    "${CTD_BIN_DIR}/ctr"
    "${CTD_BIN_DIR}/ctd-decoder"
    "${CTD_BIN_DIR}/runc"
    "${CTD_BIN_DIR}/crun"
    "${CTD_BIN_DIR}/crun_"
    /etc/systemd/system/containerd.service
    /etc/crictl.yaml
    /etc/ld.so.conf.d/containerd.conf
)

declare -a CLEAN_DIRS=(
    /etc/containerd
    /opt/containerd
    /run/containerd
    "$CTD_STORAGE"
)

rm -f "${CLEAN_FILES[@]}"
rm -rf "${CLEAN_DIRS[@]}"

ldconfig

logger "clean containerd success"
