# sealos-cluster-image

基于 `kluster-vendor-*` 组件镜像构建的 sealos 集群镜像（rootfs），用于离线 / 内网环境部署 Kubernetes。

[![Build](https://github.com/cpaas-dev/sealos-cluster-image/actions/workflows/build.yml/badge.svg)](https://github.com/cpaas-dev/sealos-cluster-image/actions/workflows/build.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
![Platforms](https://img.shields.io/badge/platforms-linux%2Famd64%20%7C%20linux%2Farm64-informational)

```bash
sealos run ghcr.io/cpaas-dev/sealos-cluster-image:v1.36.6 \
  --masters 192.168.0.10 --nodes 192.168.0.11
```

## 这是什么

sealos 的 rootfs 类型集群镜像，镜像里自带 Kubernetes 二进制、容器运行时、控制面镜像
和安装脚本。`sealos run` 把它铺到每个节点上，然后按镜像 label 里的脚本完成安装，
不需要节点访问外网。

所有二进制和镜像都来自 `kluster-vendor-*` 仓库，本仓库只负责组装和编写安装脚本，
不从上游下载任何东西。

## 组件

| 组件 | 版本 | 来源 |
| --- | --- | --- |
| Kubernetes（kubeadm / kubelet / kubectl） | `v1.36.6` | [kluster-vendor-kubernetes](https://github.com/cpaas-dev/kluster-vendor-kubernetes) |
| containerd | `v2.4.2` | [kluster-vendor-containerd](https://github.com/cpaas-dev/kluster-vendor-containerd) |
| crun（默认运行时） | `v1.31` | [kluster-vendor-crun](https://github.com/cpaas-dev/kluster-vendor-crun) |
| runc | `v1.5.3` | [kluster-vendor-runc](https://github.com/cpaas-dev/kluster-vendor-runc) |
| crictl | `v1.37.0` | [kluster-vendor-cri-tools](https://github.com/cpaas-dev/kluster-vendor-cri-tools) |
| sealctl / image-cri-shim / lvscare | `v5.1.2` | [kluster-vendor-sealos](https://github.com/cpaas-dev/kluster-vendor-sealos) |
| distribution registry | `v3.1.2` | [kluster-vendor-registry](https://github.com/cpaas-dev/kluster-vendor-registry) |
| oras | `v1.4.0` | [kluster-vendor-oras](https://github.com/cpaas-dev/kluster-vendor-oras) |

版本由 `Dockerfile` 顶部的 `INST_*_V` 控制。

## 镜像内容

仓库目录与最终 rootfs 一一对应：

```plain
/
├── bin/                     # 所有二进制，由 scripts 安装到节点的 ${BIN_DIR:-/usr/bin}
├── opt/sealctl              # sealos 在每个节点上调用，版本必须与 sealos 一致
├── etc/
│   ├── <组件>/              # 各组件配置，*.tmpl 由 sealos 部署时渲染
│   └── registry.yml.tmpl    # sealos 读取的 registry 地址 / 认证 / 数据目录
├── scripts/                 # sealos label 入口脚本，组件脚本在 scripts/<组件>/
├── statics/audit-policy.yml # sealos 拷贝到 master 的 /etc/kubernetes/
└── registry/                # 控制面镜像 + lvscare，docker distribution 格式
```

说明：

- `registry/` 由构建阶段 `build/oci-to-registry.bash` 生成：用 `sealctl registry serve`
  把 vendor 镜像里的 OCI layout 推一遍，产出 sealos 原生的存储格式。只含目标架构，
  `linux/arm64` 的镜像里只有 arm64 的控制面镜像
- `registry/` 包含 `kubeadm config images list` 的完整列表（含 kube-proxy、coredns），
  sealos 在 `kubeadm init` 前会逐个预拉，缺一个就中止
- 部署时 master0 上用 distribution `registry` 常驻提供 `sealos.hub:5000`，配置与 sealos
  官方一致（`etc/registry/`），开启 htpasswd 认证；htpasswd 由 sealos 按
  `registryUsername` / `registryPassword` 生成
- containerd 配置为 v4 格式，同时保留一段 v2 格式的 `default_runtime_name` /
  `SystemdCgroup`，只给 sealctl 判断 cgroup 驱动用，containerd 会忽略它

## 使用

### 部署

```bash
sealos run ghcr.io/cpaas-dev/sealos-cluster-image:v1.36.6 \
  --masters 192.168.0.10,192.168.0.11,192.168.0.12 \
  --nodes 192.168.0.21,192.168.0.22
```

前提：

- 节点上不能预先装有 containerd 或 docker，`check` 阶段会直接失败
- 使用 sealos `v5.1.2`，与镜像里的 `opt/sealctl` 一致

### 可覆盖的环境变量

用 `--env` 覆盖，或写在 Clusterfile 的 `spec.env`：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `defaultVIP` | `10.103.97.2` | apiserver VIP，不能落在 Pod / Service 网段内 |
| `registryDomain` | `sealos.hub` | 集群内 registry 域名 |
| `registryPort` | `5000` | registry 端口 |
| `registryUsername` / `registryPassword` | `admin` / `passw0rd` | 写入 image-cri-shim 和 htpasswd |
| `registryData` | `/var/lib/registry` | registry 数据目录（指向 rootfs 的软链接） |
| `registryConfig` | `/etc/registry` | registry 配置和 htpasswd 目录 |
| `criData` | `/var/lib/containerd` | containerd 数据目录 |
| `disableApparmor` | `false` | 没有 apparmor 的系统由 `check` 自动改为 `true` |

### 额外的 registry（如 Harbor）

- containerd：把 `<host>/hosts.toml`、`ca.crt` 等放进 `etc/containerd/certs.d/`，
  安装时原样拷到节点的 `/etc/containerd/certs.d/`
- image-cri-shim：在 `etc/image-cri-shim/image-cri-shim.yaml.tmpl` 里打开 `registries`

image-cri-shim 只换域名、保留镜像路径，命中后用它自己配置的账号拉取，会覆盖 Pod 的
`imagePullSecrets`。

### 升级

`sealos run` 一个 `version` 更高的镜像即可。sealos 升级时只替换
`kubeadm` / `kubelet` / `kubectl` 并执行 `kubeadm upgrade`，不会重新执行 `init`，
containerd 等组件不会随之升级；每次只能升一个 minor。

> 升级到 1.33+ 需要 sealos `v5.1.2` 及以上：它带了上游修复
> [`4cf5233f6`](https://github.com/labring/sealos/commit/4cf5233f6)（#6993），`v5.1.1` 的升级流程在 1.33+ 上有已知问题。

#### 升级后的 sandbox（pause）镜像

不同 minor 的 kubeadm 期望的 pause 版本可能不同（如 1.33 是 `pause:3.10`，1.34 / 1.35 是
`pause:3.10.1`，1.36 是 `pause:3.10.2`）。containerd 在 `/etc/containerd/config.toml` 的
`pinned_images.sandbox` 里固定了 pause 镜像，这个文件只在 `init` 时生成，升级不会改它，
所以升级后节点上仍固定着旧版本：

- 已有 Pod 不受影响；新 Pod 的 sandbox 仍由 containerd 用旧 pause 创建，功能正常
- 旧 pause 镜像会一直留在节点上，`kubeadm upgrade` 可能提示 sandbox image 与期望不一致

需要对齐时，在每个节点上把 `sandbox` 改成新版本并重启 containerd（新版 pause 已随新镜像
同步进 registry；重启 containerd 不会停掉运行中的容器）：

```bash
# e.g. after upgrading to v1.36.x
sed -i -E 's#^(\s*sandbox = ").*(")#\1sealos.hub:5000/pause:3.10.2\2#' /etc/containerd/config.toml
systemctl restart containerd
crictl --image-endpoint unix:///var/run/image-cri-shim.sock pull sealos.hub:5000/pause:3.10.2
```

`sealos.hub:5000` 和 pause 版本以集群实际的 `registryDomain:registryPort` 和新镜像的
`sandboxImage` 为准。

## 构建

```bash
docker buildx build --platform linux/amd64,linux/arm64 \
  --build-arg INST_KUBERNETES_V=v1.36.6 \
  -t xxx .
```

CI（`.github/workflows/build.yml`）只能手动触发，不随 push / PR 自动运行。在对应的版本分支上
触发（1.33 用 `v1.33.x`，1.34 用 `v1.34.x`，1.35 用 `v1.35.x`，1.36 用 `v1.36.x`），用的是该分支上的 Dockerfile 和脚本：

- lint（shellcheck + Dockerfile 检查）通过后，构建并推送
  `ghcr.io/cpaas-dev/sealos-cluster-image:<版本>`，校验 manifest list 同时包含两个架构，
  再创建同名的 GitHub Release 和 tag，notes 里列出各组件版本
- 已发布的版本拒绝覆盖，要重新构建需先删除对应的 Release 和 tag
- 手动触发要求 workflow 文件存在于仓库默认分支上

```bash
gh workflow run build.yml -R cpaas-dev/sealos-cluster-image --ref v1.36.x -f kubernetes_version=v1.36.6
```

## 文档

- [安装脚本与调用关系](scripts/README.md)

## 相关仓库

- Kluster vendors 索引 <https://github.com/cpaas-dev/kluster-vendors>
- sealos <https://github.com/labring/sealos>
- sealos 集群镜像脚本 <https://github.com/labring-actions/runtime>

## 许可

本仓库以 Apache-2.0 发布。部分脚本和配置改编自 sealos（Apache-2.0），文件头部保留了
原版权声明。打包进镜像的上游产物遵循其各自的许可，详见对应的 `kluster-vendor-*` 仓库。
