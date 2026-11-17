#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright © 2022 sealos.
# Modified by cpaas-dev.

echo "[Sealos] kubelet pre start"

# modprobe
cat <<EOF | xargs modprobe
bridge
ip_vs
EOF

# Open ipvs
cat <<EOF | xargs modprobe
ip_vs_rr
ip_vs_wrr
ip_vs_sh
EOF

# 1.20 need open br_netfilter
cat <<EOF | xargs modprobe
br_netfilter
EOF

# Kernel 4.19 has rebranded nf_conntrack_ipv4 to nf_conntrack
if ! modprobe -- nf_conntrack >/dev/null 2>&1; then
    modprobe -- nf_conntrack_ipv4
fi

sysctl --system
swapoff --all || true

if grep SELINUX=enforcing /etc/selinux/config >/dev/null 2>&1; then
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
    setenforce 0
fi
