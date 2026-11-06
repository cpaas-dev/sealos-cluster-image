# 旧版 Kubernetes 1.37.1 镜像的 Cilium 部署记录（历史资料）

**本页仅用于追溯旧部署，不是新集群操作手册。** 新镜像 `bbzhu/kubernetes:v1.37.1-k8s-only` 不包含 Cilium Chart、清单、镜像或 `deploy/cilium-install.sh`。新集群请按 [Kubernetes 1.37.1 离线部署操作手册](OPERATIONS_K8S_1.37.1_OFFLINE.md)使用独立 [Cilium Helm 离线包](../cilium/README.md)，**不要对新集群运行旧脚本**。实际完成的 node01 新部署见 [验收记录](DEPLOYMENT_NODE01_K8S_ONLY.md)。

## 旧集群背景

2026-10-27，使用补丁版 Sealos 5.1.1 将旧镜像 `bbzhu/kubernetes:v1.37.1`（当时部署的镜像 ID 为 `sha256:42a7c6f9e47f20ec6406c72c3aff0d98ead27330a279992b7a53254471b79b93`）部署至 node01。旧集群名为 `kubernetes-v137-cilium`，当时达到 `ClusterSuccess`：节点、API、Cilium、CoreDNS Ready，普通 Pod 通过 DNS、ClusterIP 和 Pod IP 单节点测试。测试命名空间已删除；Docker 容器及其共享 containerd 未受影响。**该旧集群现已清理，不可把旧记录当成当前运行状态。**

旧镜像把 Cilium 1.20.4 Chart、预渲染清单及 agent/operator/Envoy 镜像打包在 Kubernetes rootfs 内；旧 `deploy/cilium-install.sh` 使用 `kubectl apply` 安装清单，**不会创建 Helm release**。它保留 kube-proxy，使用 VXLAN 和 Kubernetes PodCIDR，遇到 Flannel 时会退出；不能用于现有 CNI 的原地迁移。新版本已经将这些 Cilium 资产从 Kubernetes 镜像移出，由独立离线包和 Helm 管理。

## 宿主机与隔离 CRI

宿主机的 Docker 工作负载继续使用共享 containerd；Kubernetes 使用独立的 `containerd-v137`。Clusterfile 通过 `SEALOS_ISOLATED_CRI=true` 启用隔离模式，相关 Sealos 5.1.1 补丁位于 `patches/sealos-v5.1.1-isolated-cri.patch`，CLI 构建说明见仓库 [README](../README.md)。新镜像的独立 CRI 默认 runc 1.3.4，可在**部署前**设置 `SEALOS_OCI_RUNTIME=crun` 选择 crun 1.29.1；Docker 运行时不随之切换。node01 的**新集群**已实际验证 runc 默认配置，不能再沿用“runc 待部署”的旧结论。

不要无参数执行 `sealos status` 或 `sealos reset`：旧 `default` Sealos 记录指向 `192.168.0.35`，其清理脚本可能影响共享 Docker containerd。新集群的操作、镜像导入、Helm 验收均以 [操作手册](OPERATIONS_K8S_1.37.1_OFFLINE.md)为准。

旧 Chart SHA256 为 `505abff8385811df1a949776fc42e9f10697989a332acc86d6e8933efcb855ed`。Cilium 1.20 与 Kubernetes 1.37 的兼容性、当前宿主机内核要求，以及多节点/整机重启仍需独立验收；单节点烟测不等于生产支持声明。
