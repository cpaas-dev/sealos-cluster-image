# Sealos Kubernetes v1.37 进展与计划

更新时间：2026-10-27

## 最新结果：Sealos 管理的 Kubernetes 1.37.1 集群

2026-10-27 已在 `node01` 上从重置后的空集群执行 Sealos 5.1.1 `apply`，目标记录 `/root/.sealos/kubernetes-v137-cilium/Clusterfile` 为 `ApplyClusterSuccess`、`ClusterSuccess`。镜像 `bbzhu/kubernetes:v1.37.1` 的本地 ID 为 `sha256:42a7c6f9e47f20ec6406c72c3aff0d98ead27330a279992b7a53254471b79b93`。随后使用镜像内脚本安装 Cilium 1.20.4。构建补丁 `patches/sealos-v5.1.1-isolated-cri.patch` 支持 Docker 共存、独立 CRI 和 OCI layout 同步；Clusterfile 使用 `SEALOS_ISOLATED_CRI=true`。

宿主机 `/usr/local/bin/sealos` 已安装补丁版 5.1.1，SHA256 为 `0941d1c4e106e6e165f92f9e197bebfe1e971fb109f08eeb494c5bde4957208e`；原 vendor 版保存在 `/tmp/sealos-v5.1.1-vendor.bin`。用正式路径再次执行 `sealos status --cluster kubernetes-v137-cilium` 成功。

实测 `node01 Ready`、Kubernetes Server `v1.37.1`、API `/readyz=ok`。`sealos status --cluster kubernetes-v137-cilium` 报告节点 1/1 Ready、系统 Pod 10/10 Running、Service 全部健康；Cilium agent、Envoy、operator、两个 CoreDNS 和控制平面均 Ready，无 Flannel DaemonSet。两个普通 `nginx:alpine` Pod 从独立 CRI 启动，客户端通过 DNS 将 `web.v137-sealos-smoke.svc.cluster.local` 解析到 `10.120.213.110`，通过 ClusterIP 和服务端 Pod IP `10.244.0.218` 均取得 nginx 页面；`kubernetes.default.svc.cluster.local` 解析到 `10.120.0.1`。测试 namespace 已删除。

Docker 容器 ID 与重置前基线完全一致，Docker PID `50997`、共享 containerd PID `2396` 未变化。Sealos status 的 registry/shim 配置详情仍显示部分旧默认值，需以目标 Clusterfile、独立 CRI 镜像列表、systemd 和实际工作负载为准。当前只完成单节点验收，尚未做宿主机重启和多节点测试；Cilium 1.20.4 官方兼容矩阵尚未列 Kubernetes 1.37。旧 `default` Clusterfile 指向 `192.168.0.35`，不得对它执行 `sealos reset`。

## 目标

基于现有 WIP Kubernetes 1.33 分支流程，构建并验证 Kubernetes `v1.37.1` 集群镜像，同时将宿主机 Sealos CLI 升级到 `v5.1.1`，完成本地部署和端到端验证。网络插件按用户要求使用 **Cilium**；下文 Flannel 的验证属于历史记录，不代表目标网络方案验收通过。

## 当前结论（2026-10-27）

Sealos `apply` 已完整经过 Check、PreProcess、MountRootfs、MirrorRegistry、Bootstrap、Init、Join 和 RunGuest，目标集群状态为 `ClusterSuccess`。离线镜像通过 Zot、image-cri-shim 和独立 containerd 拉取，普通 Pod 的 DNS、ClusterIP 与 Pod IP 访问通过。创建日志在 `/tmp/sealos-v137-apply.log`；Docker 重置前基线在 `/opt/sealos-v137-next/validation/sealos-reset/docker-before.txt`。

以下章节保留早期镜像构建、手工 kubeadm 部署和问题排查记录；其中“尚未验收”“当前 Flannel”等表述仅描述当时阶段，不代表本节的最终状态。

## 当前代码状态

- 仓库：`sealos-cluster-image`
- 分支：`bbzhu-1.37`
- 重封装前基线提交：`21b769d feat: add Kubernetes 1.37.1 cluster image runtime`

Dockerfile 当前版本参数：

```text
INST_KUBERNETES_V=v1.37.1
INST_SEALOS_V=v5.1.1
```

## 已完成

1. 参考 WIP 1.33 流程建立 `bbzhu-1.37` 分支。
2. 将镜像中的 Kubernetes 版本更新为 `v1.37.1`。
3. 将镜像中的 Sealos vendor 版本更新为 `v5.1.1`。
4. 补齐 rootfs 运行布局和初始化脚本，包括：
   - containerd、crun、zot
   - image-cri-shim
   - kubelet 配置和 systemd 服务
   - `/bin`、`/etc`、`/scripts`、`/registry` 目录
5. 使用 Docker BuildKit 构建成功：

```text
bbzhu/kubernetes:v1.37.1
```
6. 当前环境 Docker 可用，镜像 ID 为 `sha256:8d0386d4120b9380eb1ab2f930d49cbe2ebef1319683abf8cf37f075bf27118f`；离线运行镜像确认 kubelet、kubeadm 和 kubectl 均为 `v1.37.1`，`/images/shim/DefaultImageList` 与 `/registry` 均存在。
7. 宿主机 Sealos CLI 已安装至 `/usr/local/bin/sealos`，`sealos version` 显示 `gitVersion: 5.1.1`。来源为构建依赖镜像 `ghcr.io/cpaas-dev/kluster-vendor-sealos:v5.1.1`（digest `sha256:e56e885904901e1bbe0b73f103ba789a52c738cec65372b46a4e6ee6eefe1ef3`），二进制 SHA256 为 `cb4ef70ac2b5448783134ca03ba629d8e9dc3a322b7cd7ad7f860b4834107fae`，与该镜像中的 `sealos.sha256sum` 一致。旧 `/usr/bin/sealos`（5.0.0）未覆盖。

## 宿主机清理与 Docker 数据保护

宿主机 `node01` 原 Kubernetes `v1.29.9` 集群已按用户授权清理（不备份）：kubelet 停止并禁用；旧 CRI 容器和 sandbox 移除；`/etc/kubernetes`、`/var/lib/etcd`、`/var/lib/kubelet`、`/var/lib/cni` 和旧 `/root/.kube` 已删除。旧 CNI 网络状态并未清理宿主机全局 iptables/IPVS 规则。

Docker 容器、镜像、卷、网络及数据均须保留。Docker 与旧 Kubernetes 共用宿主机 containerd。全新部署采用独立运行时 `/opt/sealos-v137/bin/containerd`，socket `/run/containerd-v137/containerd.sock`，数据目录 `/var/lib/containerd-v137`；不得覆盖 `/usr/bin/containerd`、`/etc/containerd/config.toml`、`containerd.service` 或 `/var/lib/containerd`。

用户最新部署要求是直接部署到宿主机，不使用虚拟机。独立虚拟机 `sealos-v137` 曾作为错误假设创建，目前已关闭；尚未删除 VM 及其文件，以免擅自丢弃可重用测试资产。

## 已完成：宿主机部署与验证

2026-10-26 已直接在宿主机 node01 初始化 Kubernetes v1.37.1；没有使用虚拟机承载当前集群。

- 节点：`node01`，IP `192.168.0.96`，状态 `Ready`。
- Kubernetes Client/Server：均为 `v1.37.1`。API `/readyz` 返回 `ok`。
- 运行时：独立 `containerd-v137.service`，containerd `v2.3.4`；CRI socket `/run/containerd-v137/containerd.sock`，数据 `/var/lib/containerd-v137`。
- kubelet：`/usr/local/bin/kubelet`；systemd override `/etc/systemd/system/kubelet.service.d/20-v137.conf` 明确指定独立 CRI，不再访问旧 image-cri-shim socket。
- 初始化命令：`/usr/local/bin/kubeadm init --config /opt/sealos-v137/kubeadm.yaml`。配置禁用内置 DNS/proxy 初始安装，后以 `/opt/sealos-v137/kubeadm-addons.yaml` 执行 `kubeadm init phase addon all` 安装 CoreDNS 和 kube-proxy。
- 网络：Pod CIDR `10.244.0.0/16`，Service CIDR `10.120.0.0/16`；Flannel `v0.28.10`。健康端口 `18081` 避开 Docker 已占用的 8081；VXLAN UDP `8473` 避开旧 Cilium 的 8472。
- CNI：plugins `v1.9.1` 的 bridge、host-local、portmap 已安装；下载包 SHA256 `b98f74a0f8522f0a83867178729c1aa70f2158f90c45a2ca8fa791db1c76b303` 与发布校验文件一致。
- 控制平面、Flannel、kube-proxy、2 个 CoreDNS Pod 均 `Running/Ready`，最终检查重启次数均为 0。
- 实测普通 BusyBox Pod 创建、运行及删除；`nslookup kubernetes.default.svc.cluster.local` 返回 `10.120.0.1`；经 `smoke-web` ClusterIP Service 访问 HTTP 返回 `v137-ok`。测试 namespace `v137-smoke` 已删除。
- kubelet、containerd-v137 已启用开机启动；模块及 sysctl 持久化至 `/etc/modules-load.d/kubernetes-v137.conf` 和 `/etc/sysctl.d/90-kubernetes-v137.conf`。未做宿主机重启验收。

Docker 实测结果：

- 原 34 个运行容器 ID、StartedAt、RestartCount 与清理前基线完全相同；没有停止或重启 Docker/containerd。
- 原 Docker PID `50997`、原 containerd PID `2396` 保持不变；两服务为 active/enabled。
- Docker root `/var/lib/containerd/docker` 未删除或迁移；容器、镜像、卷和网络没有执行 prune/清理。最终可见 52 个 Docker volume，137 个唯一镜像 ID（无清理前完整卷/镜像清单，不能据此宣称逐项内容校验通过）。
- 比对证据：`/mnt/data/sealos-v137-validation/docker-state-before.txt` 与 `docker-state-final.txt`，diff 为空。该比对证明进程连续运行，不能代替逐业务功能或磁盘内容完整性测试。

## 重封装与 Cilium 配置验证

在现有 Dockerfile 基础上完成重新封装，构建标签为 `bbzhu/kubernetes:v1.37.1-cilium-layout-fix`，最终镜像 ID：`sha256:b231ace423e63392a894d70ad62d558915e514a149d0d41013b4ea09d2786dbf`。

关键修复：

- 将原来的 `COPY --from=kubernetes /cpaas/vendor/kubernetes-images/* /registry/` 改为逐目录复制 `etcd`、`kube-apiserver`、`kube-controller-manager`、`kube-scheduler`、`pause`，保留每个 OCI layout 的边界。
- 新增 Cilium 1.20.4 Helm chart（SHA256 `505abff8385811df1a949776fc42e9f10697989a332acc86d6e8933efcb855ed`）、渲染后的 `/manifests/cilium.yaml`、`cilium/values.yaml` 和三个 Cilium 离线镜像 layout。
- AddonImageList 包含 kube-proxy v1.37.1、CoreDNS v1.14.6、Cilium agent/operator/Envoy；构建时通过 Skopeo 导入 OCI layout。BuildKit 构建需要显式传入当前环境代理参数，代理未写入镜像。
- `DefaultImageList` 与 AddonImageList 通过 awk 去重合并，最终 10 行唯一镜像。
- 新增 `deploy/cilium-install.sh`：只应用打包的 Cilium manifest；发现现有 Flannel 时拒绝继续，要求先执行单独 CNI 迁移，避免双 CNI；`deploy/Clusterfile.cilium.yaml` 只引导 rootfs，Cilium 以打包 manifest 安装，不作为 Sealos application image。
- Cilium values 当前使用 Kubernetes IPAM、VXLAN，`kubeProxyReplacement: false`（保留 kube-proxy）；Cilium 1.20 对 Kubernetes 1.37 的兼容性需独立验收，不能仅凭 chart 渲染视为运行验证。

验证结果：

- `/registry` 根目录：`cilium,coredns,etcd,kube-apiserver,kube-controller-manager,kube-proxy,kube-scheduler,pause`。
- OCI layout 数量：10；`index.json` 数量：10；每个 layout 独立存在，没有被压平。
- 镜像内 `/scripts/verify-image.bash` 通过，离线 Zot manifest 检查覆盖 Kubernetes 核心镜像、kube-proxy、CoreDNS 和三个 Cilium 镜像。
- `kubelet/kubeadm/kubectl` 均为 `v1.37.1`，containerd 配置中的 sandbox image 为 `registry.k8s.io/pause:3.10.2`。
- 2026-10-26 当时 node01 集群仍为 `Ready`、v1.37.1、Flannel 网络；2026-10-27 已按下文记录重建为 Cilium。Docker 及其业务数据未参与清理或迁移。

## 镜像与 Sealos 自动化尚未验收

此次是镜像二进制与原 vendor OCI 镜像配合 kubeadm 的宿主机部署，不是 `sealos run` 全流程成功：

1. Sealos 5.1.1 对宿主机已安装 containerd 的检查拒绝继续；默认 rootfs 初始化还会覆盖共享 containerd，未强行绕过。旧 default Clusterfile 中本次误追加的 v1.37 镜像与错误记录已撤销，旧状态不能代表当前集群。当前集群不由旧 Sealos default 记录管理，禁止对其运行 reset。
2. 历史 Dockerfile 的 `COPY /cpaas/vendor/kubernetes-images/* /registry/` 将独立 OCI layout 压平；当时 zot 指向该目录时 catalogue 为空。当前控制平面镜像取自完整 vendor OCI 分目录，通过 `ctr images import --local --platform linux/amd64 --no-unpack --base-name registry.k8s.io/<repo>` 导入独立运行时。本次重封装已修复镜像布局并通过 Zot 校验；Sealos 内置 distribution registry 与 Zot OCI layout 的同步适配仍待验收。
3. 历史 vendor DefaultImageList 不包含 kube-proxy/CoreDNS，宿主机部署时通过现有代理拉取；本次重封装已将两者打包。原 pause tag 3.10 已在独立运行时及本次镜像配置中修正为 3.10.2。
4. image-cri-shim 和 zot 不参与当前集群，旧 registry/image-cri-shim 服务保持禁用。因此不能声称这两个组件验收通过。
5. kubeadm 对宿主机内核 `5.14.0-284.30.1.el9_2.x86_64` 提示不在其支持的 LTS 版本列表内；未升级内核。生产采用前需处理内核支持与重启、多节点验收。
6. 旧 Cilium 设备、BPF pin 和部分 iptables/IPVS 状态仍保留，未执行全局网络清空。当前单节点 DNS/Service 测试通过，多节点和 Docker 各业务网络未完整测试。

历史部署日志及配置：`/mnt/data/sealos-v137-validation/kubeadm-host-init.log`、`/opt/sealos-v137/kubeadm*.yaml`、`/opt/sealos-v137/kube-flannel.yml`。旧测试 VM 保持关闭。

## 验收标准

只有同时满足以下条件，才认为升级和验证完成：

```text
宿主机 Sealos CLI = v5.1.1
集群镜像 = bbzhu/kubernetes:v1.37.1
Kubernetes Server = v1.37.1
节点状态 = Ready
CNI = Cilium（没有运行的 Flannel DaemonSet）
CRI 和基础工作负载验证通过
```

## 本次重新封装：Cilium

2026-10-26 按用户要求完成重新封装，两个本地标签 `bbzhu/kubernetes:v1.37.1-cilium`、`bbzhu/kubernetes:v1.37.1` 已更新到同一最终镜像。未推送远端仓库。

已经完成的源码修改：

1. Kubernetes vendor OCI layout 按仓库名称保留目录，不再通配复制、压平为一个 layout。
2. 对齐 pause `3.10.2`；containerd `2.3.4` 使用其实际支持的 config v4、CRI images/runtime 插件名，默认运行时为包内 `crun`，启用 systemd cgroup。
3. 构建阶段使用 Skopeo 补齐 `kube-proxy:v1.37.1` 和 `coredns/coredns:v1.14.6`。
4. 封入 Cilium `1.20.4` Chart、values、渲染清单和 agent/operator/Envoy 离线镜像。Chart SHA256 为 `505abff8385811df1a949776fc42e9f10697989a332acc86d6e8933efcb855ed`，构建时校验。
5. Cilium 使用 VXLAN、Kubernetes PodCIDR 分配，保留 kube-proxy；设置 `prepend-iptables-chains=false` 兼容 lvscare。安装脚本遇到 Flannel 时停止，现有集群需单独执行迁移。Cilium init container 会安装 cilium-cni 以及缺失的 loopback 插件。
6. 添加构建校验脚本 `scripts/verify-image.bash`：检查二进制版本、解析 containerd 配置，并启动包内 Zot，从本地 Registry API 逐个读取离线镜像 manifest。

当前实测结果：

- 最终两个标签经 `docker image inspect` 确认均为 `sha256:b231ace423e63392a894d70ad62d558915e514a149d0d41013b4ea09d2786dbf`，平台 `linux/amd64`，大小 `2093116740` 字节（约 2.09 GB）。
- 在镜像列表去重前的候选镜像上执行 `docker run --rm --network none --entrypoint bash bbzhu/kubernetes:v1.37.1-cilium /scripts/verify-image.bash`，断网检查输出 `Image verification passed`；最终镜像增加列表去重，构建中的同一校验步骤也通过。此检查覆盖包内 Zot manifest 读取，不等同于 Sealos registry sync、`sealos run` 或 Cilium 集群连通性验收。
- 2026-10-27 对最终标签 `bbzhu/kubernetes:v1.37.1-cilium` 再次执行独立断网校验，输出 `Image verification passed`；所有 7 个 kubeadm 镜像及 5 个 addon 条目均能从包内 Zot 读取。

- 完整 Cilium 包已构建为 `bbzhu/kubernetes:v1.37.1-cilium-layout-fix`，ID `sha256:b231ace423e63392a894d70ad62d558915e514a149d0d41013b4ea09d2786dbf`。
- `/registry` 共 10 个独立 OCI layout：Kubernetes 核心 5 个、kube-proxy、CoreDNS、Cilium agent/operator/Envoy 3 个；每个均有独立 `oci-layout/index.json`，没有被压平。
- 镜像内 `scripts/verify-image.bash` 通过，离线 Zot Registry API manifest 检查、二进制版本、containerd config、pause 3.10.2、Cilium addon layout 全部通过。
- Cilium manifest 的三个镜像与 AddonImageList 一致；Cilium values 使用 VXLAN、Kubernetes IPAM，保留 kube-proxy，`prepend-iptables-chains=false`。
- 构建阶段 Skopeo 访问 `registry.k8s.io` 需要显式 BuildKit proxy 参数；本次使用宿主机现有代理完成，代理没有写入最终镜像。
- 2026-10-26 当时宿主机仍运行 Flannel；2026-10-27 已重建为 Cilium，详见下文。Cilium 安装脚本会主动拒绝在检测到 Flannel 时继续。

上述 Pod 网络和 Sealos 镜像同步路径已在本次 `sealos apply` 中验证。剩余验收为重启恢复、多节点和 Cilium/Kubernetes 1.37 官方兼容性确认。

Cilium `1.20.4` 官方兼容矩阵列出 Kubernetes `1.33` 至 `1.36`，未列出 `1.37`。本包以最新稳定版进行验证候选，不宣称官方支持已覆盖 `1.37`。参考：`https://github.com/cilium/cilium/blob/v1.20.4/Documentation/network/kubernetes/compatibility.rst`。

## 2026-10-27：重置现有集群并以 Cilium 重建

用户明确授权重置现有 Kubernetes 并重新部署。宿主机 Sealos `default` Clusterfile 指向旧节点 `192.168.0.35`、Kubernetes `v1.29.9` 和 Docker 共用的 containerd；当前 `node01` v1.37.1 集群由 kubeadm 创建，没有对应的 Sealos 集群记录。对 `default` 执行 `sealos reset` 会作用于错误目标，因此本次针对当前集群执行 `kubeadm reset --force --cri-socket unix:///run/containerd-v137/containerd.sock`，并保留旧 Sealos 记录。此步骤不是 Sealos CLI 端到端验收。

执行前确认当前集群仅有控制面、CoreDNS、kube-proxy 和 Flannel Pod，没有业务 Pod 或 PVC；Docker 有 42 个运行容器。新镜像 `b231ace423e6` 解包到 `/opt/sealos-v137-next`，10 个离线 OCI 镜像均已导入独立 containerd，并验证镜像引用与 Cilium manifest 一致。重建步骤保存在 `deploy/redeploy-current-host.sh`，执行前保存 `/etc/kubernetes`、旧 CNI 配置及 Docker 容器 ID 基线到 `/opt/sealos-v137-next/validation`。

已执行并验证：

- 清理独立 CRI 上的旧控制面与 Flannel CNI 文件、`flannel.1` 和旧 `cni0`；未清理 Docker 网络或共享 containerd。
- 用镜像内 `kubeadm/kubelet/kubectl v1.37.1` 重新初始化控制面，安装 kube-proxy、CoreDNS，再应用镜像内 Cilium 1.20.4 manifest。
- `node01` 为 `Ready`，API `/readyz` 返回 `ok`；Cilium、Cilium Envoy、operator、两个 CoreDNS 均 `Running/Ready`，CNI 配置为 `cilium-cni`，所有 namespace 均无 Flannel DaemonSet。
- Docker、共享 containerd、独立 containerd 和 kubelet 均为 active；脚本比对重建前后的 Docker 容器 ID 相同，Docker 与共享 containerd 的 MainPID 相同。

部署脚本本身输出成功，但第一次远程命令外层的 `tee /opt/sealos-v137-next/validation/redeploy.log` 早于脚本创建目录启动，导致外层返回码为 1，未保存该日志；随后已用独立命令复核上述部署状态。重建脚本现已改为先创建目录再在内部开启日志，且检测到 Cilium 已安装时拒绝重复重置。

网络烟测：创建普通 `network-smoke` Pod，Cilium 分配 `10.244.0.116`；Pod 内 DNS 将 `kubernetes.default.svc.cluster.local` 解析为 `10.120.0.1`，从 Pod 到 Kubernetes ClusterIP `10.120.0.1:443`、到 CoreDNS Pod `10.244.0.139:53` 的 TCP 连接均成功。测试 Pod 已删除，节点仍为 `Ready`。宿主机内核 `5.14.0-284.30.1.el9_2.x86_64` 仍有 kubeadm 支持警告；Cilium 1.20.4 官方兼容矩阵尚未列出 Kubernetes 1.37，虽此次单节点烟测通过，生产使用仍需兼容性评估及重启、多节点验证。
