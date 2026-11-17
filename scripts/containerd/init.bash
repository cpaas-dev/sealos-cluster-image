#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright © 2022 sealos.
# Modified by cpaas-dev.

set -euo pipefail

BASEDIR=$(cd "$(dirname "$0")" || exit; pwd)
source "${BASEDIR}/../common.bash"

readonly REG_DOMAIN=${1:-sealos.hub}
readonly REG_PORT=${2:-5000}
readonly CTD_BIN_DIR=${BIN_DIR:-/usr/bin}
readonly CTD_CONF_DIR=/etc/containerd

install -d -m 755 "$CTD_CONF_DIR" "${CTD_CONF_DIR}/certs.d/${REG_DOMAIN}:${REG_PORT}"

# Extra registries (e.g. Harbor): etc/containerd/certs.d/<host[:port]>/{hosts.toml,ca.crt,...}
# is copied as-is to /etc/containerd/certs.d/. Templates, examples and dotfiles are
# skipped; private keys get 0600. Installed before the built-in registry entry below,
# so a stray "<registryDomain>:<registryPort>" dir cannot override it.
readonly EXTRA_CERTS_DIR="${ROOTFS_DIR}/etc/containerd/certs.d"
while IFS= read -r -d '' rel; do
    mode=644
    [[ "$rel" == *.key ]] && mode=600
    install -Dm"${mode}" "${EXTRA_CERTS_DIR}/${rel}" "${CTD_CONF_DIR}/certs.d/${rel}"
done < <(find "$EXTRA_CERTS_DIR" -type f ! -name '.*' ! -name '*.tmpl' ! -name '*.example' -printf '%P\0')

declare -a INSTALL_FILES=(
    "755 ${ROOTFS_DIR}/bin/containerd              ${CTD_BIN_DIR}/"
    "755 ${ROOTFS_DIR}/bin/containerd-shim-runc-v2 ${CTD_BIN_DIR}/"
    "755 ${ROOTFS_DIR}/bin/containerd-stress       ${CTD_BIN_DIR}/"
    "755 ${ROOTFS_DIR}/bin/ctr                     ${CTD_BIN_DIR}/"
    "644 ${ROOTFS_DIR}/etc/containerd/containerd.service /etc/systemd/system/"
    "644 ${ROOTFS_DIR}/etc/containerd/config.toml        ${CTD_CONF_DIR}/"
    "644 ${ROOTFS_DIR}/etc/containerd/hosts.toml         ${CTD_CONF_DIR}/certs.d/${REG_DOMAIN}:${REG_PORT}/"
)

for entry in "${INSTALL_FILES[@]}"; do
    read -r mode src dest <<< "$entry"
    install -Dm"${mode}" -t "$dest" "$src"
done

check_service start containerd
check_status containerd

logger "init containerd success"
