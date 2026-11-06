#!/usr/bin/env bash
set -euo pipefail

[[ ${SEALOS_ISOLATED_CRI:-} == true ]] || { echo 'isolated CRI mode required' >&2; exit 1; }
oci_runtime=${SEALOS_OCI_RUNTIME:-runc}
[[ $oci_runtime == crun || $oci_runtime == runc ]] || { echo "Unsupported OCI runtime: $oci_runtime" >&2; exit 1; }
base=$(cd "$(dirname "$0")/.." && pwd)
bin=/opt/sealos-v137/bin
install -d -m 755 "$bin" /etc/containerd-v137/certs.d/sealos.hub:5000 /var/lib/kubelet
for name in containerd containerd-shim-runc-v2 ctr crun runc crictl kubeadm kubectl kubelet image-cri-shim; do
    install -m 755 "$base/bin/$name" "$bin/$name"
done
install -m 644 "$base/etc/containerd-v137.toml" /etc/containerd-v137/config.toml
if [[ $oci_runtime == crun ]]; then
    sed -i 's/default_runtime_name = "runc"/default_runtime_name = "crun"/' /etc/containerd-v137/config.toml
fi
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
# systemctl may report success before the CRI shim has created its socket.
ready=false
for attempt in $(seq 1 30); do
    if [[ -S /run/image-cri-shim-v137.sock ]] &&
       "$bin/crictl" --runtime-endpoint unix:///run/containerd-v137/containerd.sock \
         --image-endpoint unix:///run/image-cri-shim-v137.sock info >/dev/null 2>&1; then
        ready=true
        break
    fi
    sleep 1
done
[[ $ready == true ]] || { echo 'isolated CRI shim not ready after 30 seconds' >&2; exit 1; }
"$bin/crictl" --runtime-endpoint unix:///run/containerd-v137/containerd.sock --image-endpoint unix:///run/image-cri-shim-v137.sock pull "${registryDomain:-sealos.hub}:${registryPort:-5000}/${sandboxImage:-pause:3.10.2}"
