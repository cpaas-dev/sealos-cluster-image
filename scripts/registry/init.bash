#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright © 2022 sealos.
# Modified by cpaas-dev.

set -euo pipefail

BASEDIR=$(cd "$(dirname "$0")" || exit; pwd)
source "${BASEDIR}/../common.bash"

# Runs on registry hosts only. Before this, sealos has linked REG_DATA_DIR to
# <rootfs>/registry and written <rootfs>/etc/registry_htpasswd.
readonly REG_DATA_DIR=$1
readonly REG_CONF_DIR=$2
readonly REG_BIN_DIR=${BIN_DIR:-/usr/bin}

[[ -d "${REG_DATA_DIR}" ]] || error "registry data dir not found: ${REG_DATA_DIR} (sealos should have linked it to the rootfs registry/)"

install -d -m 755 "${REG_CONF_DIR}"

declare -a INSTALL_FILES=(
    "755 ${ROOTFS_DIR}/bin/registry                         ${REG_BIN_DIR}/"
    "644 ${ROOTFS_DIR}/etc/registry/registry.service        /etc/systemd/system/"
    "644 ${ROOTFS_DIR}/etc/registry/registry_config.yml     ${REG_CONF_DIR}/"
    "600 ${ROOTFS_DIR}/etc/registry_htpasswd                ${REG_CONF_DIR}/"
)

for entry in "${INSTALL_FILES[@]}"; do
    read -r mode src dest <<< "$entry"
    install -Dm"${mode}" -t "$dest" "$src"
done

if [[ -s /etc/selinux/config ]] && grep -q 'SELINUX=enforcing' /etc/selinux/config; then
    sed -i 's#SELINUX=enforcing#SELINUX=disabled#g' /etc/selinux/config
fi
# setenforce fails when SELinux is already disabled or permissive at runtime,
# so only switch it when the running mode is actually Enforcing.
if command_exists getenforce && [[ "$(getenforce)" == "Enforcing" ]]; then
    setenforce 0
fi

check_service start registry
check_status registry

logger "init registry success"
