# Kubernetes 1.37.1 Sealos 集群镜像

本仓库的 `bbzhu-1.37` 分支构建 `bbzhu/kubernetes:v1.37.1`。镜像包含 Kubernetes 1.37.1、独立的 containerd 2.3.4、Cilium 1.20.4 的安装清单和离线镜像。已在 `node01` 使用补丁版 Sealos 5.1.1 完成单节点部署和网络烟测；详细结果见 [进展记录](SEALOS_V1.37_PROGRESS.md)。

## 构建准备

- Linux `amd64` 构建主机，Docker 和 BuildKit 可用，并有足够空间保存构建缓存、约 2.18 GB 的成品镜像和导出归档。
- 能读取 Docker Hub、`ghcr.io/cpaas-dev` 的 vendor 镜像、`quay.io`、`registry.k8s.io` 和 `helm.cilium.io`。私有 GHCR 镜像需要先完成 `docker login ghcr.io`。
- 在本仓库的 `bbzhu-1.37` 分支执行命令。Dockerfile 固定 Kubernetes 1.37.1、Sealos vendor 5.1.1、Cilium 1.20.4；不要只改版本参数，校验脚本、Cilium Chart 校验和及离线镜像列表也必须同步修改。

Dockerfile 使用 `ghcr.io/cpaas-dev/kluster-vendor-kubernetes:v1.37.1`、`kluster-vendor-containerd:v2.3.4`、`kluster-vendor-crun:v1.29.1`、`kluster-vendor-zot:v2.1.20`、`kluster-vendor-sealos:v5.1.1`、`kluster-vendor-cri-tools:v1.36.0`，并在构建时下载 `images/shim/AddonImageList` 列出的镜像。Sealos CLI 本身需按下文单独构建；镜像内的 Sealos vendor 提供 `image-cri-shim` 和 `sealctl`。

## 构建与检查

```bash
cd /path/to/sealos-cluster-image
git switch bbzhu-1.37
DOCKER_BUILDKIT=1 docker build --platform linux/amd64 --progress=plain \
  -t bbzhu/kubernetes:v1.37.1 .

docker run --rm --network none --entrypoint bash \
  bbzhu/kubernetes:v1.37.1 /scripts/verify-image.bash
docker image inspect bbzhu/kubernetes:v1.37.1 --format '{{.Id}} {{.Os}}/{{.Architecture}}'
```

构建时 Dockerfile 会先运行同一个 `verify-image.bash`；单独的 `--network none` 检查进一步确认包内 Zot 可以离线读取 Kubernetes 和 Cilium 镜像。成功标志是 `Image verification passed`。已验收的本地镜像 ID 是 `sha256:42a7c6f9e47f20ec6406c72c3aff0d98ead27330a279992b7a53254471b79b93`；重新构建的 ID 可能不同，应以校验结果和版本为准。

若构建主机必须使用 HTTP 代理，先在 shell 中设置 `HTTP_PROXY`、`HTTPS_PROXY`、`NO_PROXY`，再在 `docker build` 命令中增加 `--build-arg HTTP_PROXY --build-arg HTTPS_PROXY --build-arg NO_PROXY`。这些参数用于构建阶段拉取 Chart 和 addon 镜像；不要把代理凭据写入 Dockerfile。

## 准备 Sealos 5.1.1 CLI

本镜像的 `SEALOS_ISOLATED_CRI=true` 模式依赖 [Sealos 5.1.1 补丁](patches/sealos-v5.1.1-isolated-cri.patch)。普通未打补丁的 5.1.1 CLI 会因宿主机已有 Docker/containerd 而拒绝创建，且不能正确同步包内 OCI layout。准备干净的 Sealos `v5.1.1` 源码、Go 1.23.7 和 C 编译器，执行：

```bash
CLUSTER_IMAGE_DIR=/path/to/sealos-cluster-image
git clone --branch v5.1.1 --depth 1 https://github.com/labring/sealos.git /tmp/sealos-v5.1.1
cd /tmp/sealos-v5.1.1
git apply --check "$CLUSTER_IMAGE_DIR/patches/sealos-v5.1.1-isolated-cri.patch"
git apply "$CLUSTER_IMAGE_DIR/patches/sealos-v5.1.1-isolated-cri.patch"
cd lifecycle
CGO_ENABLED=1 go build -buildvcs=false \
  -tags 'containers_image_openpgp netgo exclude_graphdriver_devicemapper static osusergo exclude_graphdriver_btrfs' \
  -ldflags '-X github.com/labring/sealos/pkg/version.gitVersion=5.1.1' \
  -o /tmp/sealos-v5.1.1-isolated ./cmd/sealos
sudo install -m 755 /tmp/sealos-v5.1.1-isolated /usr/local/bin/sealos
/usr/local/bin/sealos version
```

`sealos version` 应显示 `gitVersion: 5.1.1`。本次宿主机安装的补丁版 CLI SHA256 为 `0941d1c4e106e6e165f92f9e197bebfe1e971fb109f08eeb494c5bde4957208e`。

## 导入与部署

以下命令针对**全新、可安装的节点**。当前 `node01` 已在运行目标集群，不要在它上面重复执行 `sealos apply`。先把 [Clusterfile](deploy/Clusterfile.cilium.yaml) 中的 `192.168.0.96:22` 改成目标节点 SSH 地址；示例假设可用 root SSH 登录。Pod 网段 `10.244.0.0/16`、Service 网段 `10.120.0.0/16` 不应与现有网络重叠。

```bash
cd /path/to/sealos-cluster-image
docker save -o /tmp/kubernetes-v1.37.1.tar bbzhu/kubernetes:v1.37.1
sudo /usr/local/bin/sealos load -i /tmp/kubernetes-v1.37.1.tar
sudo /usr/local/bin/sealos images
sudo /usr/local/bin/sealos apply -f deploy/Clusterfile.cilium.yaml

sudo env KUBECONFIG=/etc/kubernetes/admin.conf bash \
  /var/lib/sealos/data/kubernetes-v137-cilium/rootfs/deploy/cilium-install.sh
```

`sealos apply` 创建控制面、独立 CRI、镜像服务和 kube-proxy；Cilium 在 API 可用后由镜像内脚本安装。`sealos load` 导入的是 Sealos 自己的镜像存储，Docker 中有同名镜像并不足以执行 `sealos apply`。安装脚本检测到 Flannel 时会退出，因此此流程适用于空集群，不能作为原地 CNI 迁移命令。旧 `default` Sealos 记录指向 `192.168.0.35`，不要对它执行 `sealos reset`。

## 验收

```bash
sudo /usr/local/bin/sealos status --cluster kubernetes-v137-cilium
sudo env KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes -o wide
sudo env KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -A -o wide
sudo env KUBECONFIG=/etc/kubernetes/admin.conf kubectl get daemonsets -A
sudo env KUBECONFIG=/etc/kubernetes/admin.conf kubectl get --raw=/readyz
```

预期节点为 `Ready`、版本 `v1.37.1`，Cilium、Envoy、operator 和 CoreDNS 为 Ready，`/readyz` 返回 `ok`，且没有 Flannel DaemonSet。`sealos status` 的 registry/shim 配置详情仍可能展示默认路径；实际 CRI socket 是 `/run/containerd-v137/containerd.sock`。生产采用前仍需重启恢复、多节点和 Cilium/Kubernetes 1.37 兼容性验收。

部署细节、网络设置和已知限制见 [deploy/README.md](deploy/README.md)。
