# 独立 Cilium 1.20.4 离线包（linux/amd64）

完整的 **Kubernetes 1.37.1 + Cilium 离线部署操作顺序**见 [部署手册](../deploy/OPERATIONS_K8S_1.37.1_OFFLINE.md)；已完成的 node01 部署证据见 [实际记录](../deploy/DEPLOYMENT_NODE01_K8S_ONLY.md)。

与 `bbzhu/kubernetes:v1.37.1-k8s-only` 分开版本化、导入和升级；Cilium **不是** Sealos application image。只有新建且无 Flannel/其他 CNI 的集群可以走下面的安装步骤，已有 `kubectl apply` 安装的 Cilium 不能直接由 Helm 接管。

从源码联网构建：

```bash
DOCKER_BUILDKIT=1 docker build --platform linux/amd64 \
  -f cilium/Offline.Dockerfile \
  --output type=local,dest=/path/to/cilium-1.20.4-amd64 .
```

在无法访问上游 registry 的构建机上，可**仅首次**从已验证的本地旧镜像提取同一版本制品（不能用于升级到新版本）：

```bash
DOCKER_BUILDKIT=1 docker build --platform linux/amd64 \
  -f cilium/Offline.cached.Dockerfile \
  --output type=local,dest=/path/to/cilium-1.20.4-amd64 .
sha256sum /path/to/cilium-1.20.4-amd64/charts/cilium.tgz
# 预期 505abff8385811df1a949776fc42e9f10697989a332acc86d6e8933efcb855ed
```

在**构建主机**为整个包生成文件校验清单（下例中的路径需替换为实际导出目录），并将其一并传输：

```bash
(cd /path/to/cilium-1.20.4-amd64 && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
# 在部署主机：
(cd /path/to/cilium-1.20.4-amd64 && sha256sum -c SHA256SUMS)
```

传输整个导出目录到新集群可访问 Sealos registry 的主机；导入步骤使用 `skopeo` 和事先准备好的 registry authfile，不联网下载镜像，也不在命令行放明文密码。**先检查目标 registry/节点及 kubeconfig 指向新集群，切勿在旧 default 集群上执行。**

```bash
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl --kubeconfig "$KUBECONFIG" get nodes -o wide
kubectl --kubeconfig "$KUBECONFIG" get daemonsets -A # 必须没有 Flannel 或已有 Cilium
export REGISTRY_AUTHFILE=/path/to/sealos-registry-auth.json
export CILIUM_REGISTRY=sealos.hub:5000
bash /path/to/cilium-1.20.4-amd64/import-images.sh
# 如无原生 skopeo：先 docker load -i /path/to/tools/skopeo-stable-v1.21.0.tar，
# 再改用 bash /path/to/cilium-1.20.4-amd64/import-images-docker.sh；两种方式二选一。
helm --kubeconfig "$KUBECONFIG" install cilium \
  /path/to/cilium-1.20.4-amd64/charts/cilium.tgz \
  -n kube-system -f /path/to/cilium-1.20.4-amd64/values.yaml \
  --wait --timeout 10m
kubectl --kubeconfig "$KUBECONFIG" -n kube-system rollout status ds/cilium --timeout=5m
kubectl --kubeconfig "$KUBECONFIG" -n kube-system rollout status ds/cilium-envoy --timeout=5m
kubectl --kubeconfig "$KUBECONFIG" -n kube-system rollout status deploy/cilium-operator --timeout=5m
```

在安装前应核对 kube-proxy 正常和每个 node 的 `spec.podCIDR` 已分配；CNI 安装前节点尚未 Ready 是正常现象。离线镜像采用 `quay.io/cilium/...` 的原始引用；本地 registry 必须由 Sealos 的 image-cri-shim 提供镜像映射，安装前确认 shim、registry 和 DNS 配置，否则 Pods 会触网拉取并失败。完成后检查节点 Ready、CoreDNS、跨节点 Pod/Service/DNS 网络，并做重启和 Helm 升级测试。Kubernetes 1.37 尚未列在当前使用的 Cilium 1.20 兼容矩阵内，需单独验收。Helm 升级前核对由 Chart 创建的证书 Secret，避免误重置 CA。
