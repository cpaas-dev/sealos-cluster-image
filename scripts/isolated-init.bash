#!/usr/bin/env bash
set -euo pipefail

[[ ${SEALOS_ISOLATED_CRI:-} == true ]] || { echo 'isolated CRI mode required' >&2; exit 1; }
base=$(cd "$(dirname "$0")/.." && pwd)
bin=/opt/sealos-v137/bin
install -d -m 755 "$bin" /etc/containerd-v137/certs.d/sealos.hub:5000 /var/lib/kubelet
for name in containerd containerd-shim-runc-v2 ctr crun crictl kubeadm kubectl kubelet image-cri-shim; do
    install -m 755 "$base/bin/$name" "$bin/$name"
done
install -m 644 "$base/etc/containerd-v137.toml" /etc/containerd-v137/config.toml
install -m 644 "$base/etc/hosts.toml" /etc/containerd-v137/certs.d/sealos.hub:5000/hosts.toml
install -m 644 "$base/etc/containerd-v137.service" /etc/systemd/system/containerd-v137.service
install -m 644 "$base/etc/image-cri-shim-v137.yaml" /etc/image-cri-shim-v137.yaml
install -m 644 "$base/etc/image-cri-shim-v137.service" /etc/systemd/system/image-cri-shim-v137.service
install -m 644 "$base/etc/kubelet-v137.service" /etc/systemd/system/kubelet.service
install -d -m 755 /etc/systemd/system/kubelet.service.d
install -m 644 "$base/etc/kubelet-v137-override.conf" /etc/systemd/system/kubelet.service.d/90-sealos-v137.conf
install -m 644 "$base/etc/crictl.yaml" /etc/crictl.yaml
sed -i 's#/run/containerd/containerd.sock#/run/containerd-v137/containerd.sock#g; s#/var/run/image-cri-shim.sock#/run/image-cri-shim-v137.sock#g' /etc/crictl.yaml
for name in kubeadm kubectl kubelet; do
    install -m 755 "$bin/$name" "/usr/local/bin/$name"
done
systemctl daemon-reload
systemctl enable --now containerd-v137.service
systemctl enable --now image-cri-shim-v137.service
systemctl enable kubelet.service
"$bin/crictl" --runtime-endpoint unix:///run/containerd-v137/containerd.sock --image-endpoint unix:///run/image-cri-shim-v137.sock pull "${registryDomain:-sealos.hub}:${registryPort:-5000}/${sandboxImage:-pause:3.10.2}"
