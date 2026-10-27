#!/usr/bin/env bash
set -euo pipefail

[[ ${SEALOS_ISOLATED_CRI:-} == true ]] || { echo 'isolated CRI mode required' >&2; exit 1; }
systemctl disable --now kubelet.service image-cri-shim-v137.service containerd-v137.service
rm -f /etc/systemd/system/kubelet.service /etc/systemd/system/kubelet.service.d/90-sealos-v137.conf /etc/systemd/system/image-cri-shim-v137.service /etc/systemd/system/containerd-v137.service /etc/image-cri-shim-v137.yaml /etc/crictl.yaml
rm -rf /etc/containerd-v137 /var/lib/image-cri-shim-v137 /var/lib/containerd-v137 /run/containerd-v137 /opt/sealos-v137/bin
systemctl daemon-reload
