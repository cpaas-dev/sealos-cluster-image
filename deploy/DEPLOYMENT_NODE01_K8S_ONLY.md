# node01 实际部署记录：Sealos K8s 1.37.1 + 独立 Cilium Helm 1.20.4

执行日期：2026-11-05；目标：`192.168.0.96`，Sealos 集群名 `kubernetes-v137-k8sonly`。用户授权清理旧 Kubernetes，**要求保留 Docker 工作负载**。旧 `default` Sealos 记录指向 `192.168.0.35`，全程未对它执行 reset/apply。

## 操作与构建

- 旧 `containerd-v137` 服务已停止但留下 18 个 `/kubepods.slice` 进程和 10 个专用 shim（包括占用 6443 的 apiserver）。只对这些明确归属于独立 CRI 的进程发送 TERM；未清理共享 containerd、Docker 或全局 iptables。Docker 运行容器前后均为原来的 **26 个 ID**，`docker.service` 和共享 `containerd.service` 均为 active。
- `sealos load` 导入 `bbzhu/kubernetes:v1.37.1-k8s-only`，最终镜像 ID `sha256:de57e834d9388ecc913c228dcfb724d0886bf1b60d7c5e54f05e673c92086183`，镜像内离线校验通过。构建时上游 `registry.k8s.io` 超时，因此从本地旧镜像**只**复用了 kube-proxy/CoreDNS OCI 布局，未复制 Cilium。镜像现保存在 node01 的 Docker、Sealos 存储和 `/mnt/data/k8s-artifacts/kubernetes-v1.37.1-k8s-only.tar`；尝试推送同标签到 Docker Hub 返回 `denied: requested access to the resource is denied`，**远端镜像尚未发布**，离线安装须用 tar 执行 `sealos load`。
- 首次 `sealos apply -f deploy/Clusterfile.cilium.yaml` 因独立 `image-cri-shim-v137.sock` 尚未创建就执行 CRI pull 而失败。仅 `sealos reset --cluster kubernetes-v137-k8sonly --force` 清理了这次失败的新集群。`scripts/isolated-init.bash` 加入 CRI 就绪等待后重建、重新 load 并 apply，第二次成功。
- K8s `v1.37.1`，独立 containerd `2.3.4` 默认 runc；API `/readyz` 为 `ok`，kube-proxy Running，PodCIDR `10.244.0.0/24`，ServiceCIDR `10.120.0.0/16`。

## 独立 Cilium 离线交付与 Helm

- 离线包：`/mnt/data/k8s-artifacts/cilium-1.20.4-amd64`，chart SHA256 `505abff8385811df1a949776fc42e9f10697989a332acc86d6e8933efcb855ed`；包内 `VERSION`、`README.md` 和 `SHA256SUMS` 齐全，31 个文件逐项校验成功；Helm lint 和离线 template 成功（25 个资源）。
- 本机没有原生 `skopeo` 可执行文件，因此使用已缓存的 `quay.io/skopeo/stable:v1.21.0` Docker 镜像将三个 OCI 镜像导入 Sealos 的 `sealos.hub:5000`。Zot 对三个 manifest 的 PUT 均返回 201；逐一核对 registry manifest SHA256 与离线包源 manifest 相同，所有 config/layer 的 HEAD 为 200。Docker 启动的一次性 skopeo 容器在写完 manifest 后未自行退出，核实 registry 数据完整后**只**移除了这些一次性容器；原 26 个 Docker 容器 ID 保持不变。
- 通过隔离 CRI 拉取 `quay.io/cilium/operator-generic:v1.20.4` 成功，`image-cri-shim-v137` 日志证实重写为 `sealos.hub:5000/cilium/operator-generic:v1.20.4`；Cilium/Envoy 的 Pod 镜像也从本地成功拉取。
- `helm install cilium /mnt/data/k8s-artifacts/cilium-1.20.4-amd64/charts/cilium.tgz -n kube-system -f /mnt/data/k8s-artifacts/cilium-1.20.4-amd64/values.yaml --wait --timeout 10m` 成功：release `cilium`、chart `cilium-1.20.4`、revision 1、status `deployed`。未使用 `kubectl apply` 安装 Cilium。

## 验收与限制

- 初始节点根分区仅约 30 GB 可用，触发 `DiskPressure=True`，operator 和 CoreDNS 一度无法调度。将**旧 Sealos 构建临时目录**（`/tmp/v137-final*`、`/tmp/v137-registry-check` 和三组 `/tmp/sealos*-go*-cache`）完整迁到 `/mnt/data/k8s-artifacts/prior-sealos-build-tmp` 后，根分区约 37 GB 可用，节点压力解除。首次跨文件系统 `mv` 中途被系统终止，随后用 `rsync --remove-source-files` 完成迁移并确认源目录无文件；未清理 Docker 数据。
- 节点 `Ready`；Cilium agent、Envoy、operator、CoreDNS 两个副本和 kube-proxy 都 Ready；Cilium CLI `status --brief` 返回 `OK`，API `/readyz` 返回 `ok`。
- 使用离线已有的 Cilium 镜像创建临时非 hostNetwork 测试 Pod，获得 `10.244.0.169`，成功解析 `kubernetes.default.svc.cluster.local` 为 `10.120.0.1`，成功连接 Kubernetes Service 的 TCP 443、CoreDNS Pod IP 的 TCP 53；完成后删除该 Pod。
- 仅重启隔离的 `containerd-v137`、`image-cri-shim-v137` 和 kubelet 服务，再次确认节点 Ready、所有 Cilium/CoreDNS rollout 完成、Helm release 保持 revision 1、API `/readyz=ok`；Docker 26 个容器保持不变。**未重启宿主机**（会影响用户要求保留的 Docker 工作负载），未测试多节点网络，也未执行跨版本 Cilium Helm 升级或回滚；Kubernetes 1.37 与该 Cilium 版本的长期兼容性仍需额外验证。

构建、导入和首次失败日志留在本机 `/tmp/k8s-only-build-retry.log`、`/tmp/sealos-k8sonly-apply.log`、`/tmp/sealos-k8sonly-apply-retry.log`、`/tmp/cilium-helm-install.log`。
