# Cilium deployment for the Kubernetes v1.37.1 image

On 2026-10-27, `bbzhu/kubernetes:v1.37.1` (image ID
`sha256:42a7c6f9e47f20ec6406c72c3aff0d98ead27330a279992b7a53254471b79b93`)
was deployed on node01 by a patched Sealos 5.1.1 `apply`. The named cluster
`kubernetes-v137-cilium` reached `ClusterSuccess`: node Ready, API ready, Cilium
and CoreDNS Ready, and ordinary Pods passed DNS, ClusterIP and Pod-IP checks.
The test namespace was removed. Docker containers and the shared Docker
containerd process remained running with unchanged IDs/PIDs. This is a
single-node validation; restart and multi-node behavior remain untested.

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

The host uses Docker's existing containerd for Docker workloads and a separate
`containerd-v137` for Kubernetes. `Clusterfile.cilium.yaml` enables isolated
CRI mode. The image's init and clean scripts only operate on the isolated
runtime in that mode. `patches/sealos-v5.1.1-isolated-cri.patch` updates Sealos
5.1.1 host checks, CRI selection and OCI-layout registry sync. Apply it to a
clean Sealos v5.1.1 checkout and build the CLI with the repository's Go tags:

```bash
git apply /path/to/sealos-cluster-image/patches/sealos-v5.1.1-isolated-cri.patch
cd lifecycle
CGO_ENABLED=1 go build -buildvcs=false \
  -tags 'containers_image_openpgp netgo exclude_graphdriver_devicemapper static osusergo exclude_graphdriver_btrfs' \
  -ldflags '-X github.com/labring/sealos/pkg/version.gitVersion=5.1.1' \
  -o /tmp/sealos-v5.1.1-isolated ./cmd/sealos
```

`sealos apply -f deploy/Clusterfile.cilium.yaml` creates the named cluster.
After the API and kube-proxy are available, run `deploy/cilium-install.sh`.
Inspect it with `sealos status --cluster kubernetes-v137-cilium` and
`KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -A`. The status command
still displays some default registry/shim configuration values; check the
Clusterfile and `/run/containerd-v137/containerd.sock` for the actual runtime.
Never reset the old `default` Sealos record: it points to 192.168.0.35 and
uses cleanup scripts that can remove Docker's containerd files.

Rebuild from the repository root:

```bash
docker build --platform linux/amd64 -t bbzhu/kubernetes:v1.37.1 .
```

Chart SHA256: `505abff8385811df1a949776fc42e9f10697989a332acc86d6e8933efcb855ed`.
Values are in `cilium/values.yaml`. Changing versions requires updating the chart
checksum and offline image list together. The Cilium 1.20 compatibility matrix
lists Kubernetes 1.33 through 1.36; Kubernetes 1.37 requires local acceptance tests.
The current host kernel also needs a separate Cilium requirements check.
