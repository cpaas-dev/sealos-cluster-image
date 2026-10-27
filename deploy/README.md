# Cilium deployment for the Kubernetes v1.37.1 image

The rootfs image includes Cilium 1.20.4, its Helm chart, rendered manifest, and
offline images for the agent, operator and Envoy. Install Cilium after the API
server and kube-proxy are available, before scheduling ordinary workloads.

```bash
export KUBECONFIG=/etc/kubernetes/admin.conf
bash <extracted-rootfs>/deploy/cilium-install.sh
```

The script applies the packaged manifest without downloading a chart. It uses
VXLAN, Kubernetes PodCIDR allocation and keeps kube-proxy enabled. The local
registry must already serve the packaged images through image-cri-shim. It stops
if Flannel is installed; migrating an existing CNI requires a separate procedure.

`Clusterfile.cilium.yaml` bootstraps the runtime on a clean host. A Cilium agent
container image is not a Sealos application image and must not appear in
`spec.image`. Install the packaged manifest after runtime initialization.

The current `node01` Kubernetes cluster was initialized with kubeadm, not
`sealos run`. Sealos 5.1.1 rejects the existing Docker containerd during host
checks, and the rootfs `check.bash` rejects Docker too. With no local `sealctl`,
Sealos should fall back to SSH directory copying for the packaged Zot OCI
layouts; that path and image-cri-shim pulling remain unverified.
Do not run `sealos reset` against the old `default` record: it targets the
previous 192.168.0.35 cluster and its cleanup scripts can remove Docker's
containerd files. A Sealos-managed deployment on this shared host still needs
runtime isolation and registry-format work.

Rebuild from the repository root:

```bash
docker build --platform linux/amd64 -t bbzhu/kubernetes:v1.37.1 .
```

Chart SHA256: `505abff8385811df1a949776fc42e9f10697989a332acc86d6e8933efcb855ed`.
Values are in `cilium/values.yaml`. Changing versions requires updating the chart
checksum and offline image list together. The Cilium 1.20 compatibility matrix
lists Kubernetes 1.33 through 1.36; Kubernetes 1.37 requires local acceptance tests.
The current host kernel also needs a separate Cilium requirements check.
