# Kubernetes 1.37.1 离线部署操作手册（Sealos + 独立 Cilium Helm）

适用：**新建单节点 linux/amd64 集群**，且已授权在该节点安装 Kubernetes；允许保留现有 Docker 服务/容器。当前 `node01` **已经部署完毕，不能再执行本手册的 `sealos apply` 或 `helm install`**；只需使用末尾的验收命令。已执行的命令与故障处理记录见 [node01 实测记录](DEPLOYMENT_NODE01_K8S_ONLY.md)。多节点需另行规划 registry 可达性、Pod CIDR、跨节点网络与故障恢复。

本手册使用补丁版 Sealos 5.1.1、`bbzhu/kubernetes:v1.37.1-k8s-only`、独立 `containerd-v137`（默认 runc）、本地 Zot registry、kube-proxy/CoreDNS，以及独立的 Cilium 1.20.4 离线包。Cilium **不在** Sealos `spec.image` 中；必须使用 `helm install`，不得用旧版 `deploy/cilium-install.sh`/`kubectl apply` 替代。

## 1. 准备离线制品和工具

在已构建的 node01，制品路径是 `/mnt/data/k8s-artifacts`。**远端离线传输需两份归档、一份 Clusterfile 模板和一份校验文件**：`kubernetes-v1.37.1-k8s-only.tar`（约 1.7 GB）、`cilium-1.20.4-helm-images-tools-linux-amd64.tar`（约 758 MB）、`Clusterfile.cilium.yaml`、`OFFLINE-ARCHIVES-SHA256SUMS`。第二份 tar 是未压缩包，内含 Cilium Helm Chart、values、agent/operator/Envoy 的 OCI 镜像、Helm 3.21.3、补丁版 Sealos CLI 和备用 skopeo 工具镜像；它**不依赖 Docker Hub 才能安装**。

| 文件 | 用途 / 校验 |
| --- | --- |
| `kubernetes-v1.37.1-k8s-only.tar` | Sealos rootfs Docker archive；SHA256 `5fafec7b70c821220f9fcced1767601c69c67e61db748e503cc7f105af2c2917`，导入后的镜像 ID `sha256:de57e834d9388ecc913c228dcfb724d0886bf1b60d7c5e54f05e673c92086183` |
| `cilium-1.20.4-amd64/` | Chart、values、3 个 OCI 镜像、导入脚本、`VERSION`、`SHA256SUMS`；Chart SHA256 `505abff8385811df1a949776fc42e9f10697989a332acc86d6e8933efcb855ed` |
| `tools/sealos-v5.1.1-isolated` | 支持已有 Docker + 独立 CRI 的补丁版 Sealos CLI；`tools/SHA256SUMS` 校验 |
| `tools/helm-v3.21.3` | 用于离线安装 Cilium；`tools/SHA256SUMS` 校验 |
| `tools/skopeo-stable-v1.21.0.tar` | 本机无原生 skopeo 时，可 `docker load` 的离线工具镜像；`tools/SHA256SUMS` 校验 |
| `sealos-cluster-image/deploy/Clusterfile.cilium.yaml` | 部署清单模板；需根据实际测试节点改 SSH IP、唯一集群名和网段 |

将上述**四个文件**复制到目标节点（U 盘、内网 scp 等），不需要目标节点访问外网。下文约定制品仍在 `/mnt/data/k8s-artifacts`；其他目录请替换路径，**目标节点无需 Git 仓库**。**在目标节点**先校验归档再解包，随后校验包内文件；失败就停下，不要部署损坏制品：

```bash
KIT=/mnt/data/k8s-artifacts
(cd "$KIT" && sha256sum -c OFFLINE-ARCHIVES-SHA256SUMS)
tar -xf "$KIT/cilium-1.20.4-helm-images-tools-linux-amd64.tar" -C "$KIT"
printf '%s  %s\n' 5fafec7b70c821220f9fcced1767601c69c67e61db748e503cc7f105af2c2917 \
  "$KIT/kubernetes-v1.37.1-k8s-only.tar" | sha256sum -c -
(cd "$KIT/tools" && sha256sum -c SHA256SUMS)
(cd "$KIT/cilium-1.20.4-amd64" && sha256sum -c SHA256SUMS)
# 新节点上安装离线工具；如果已有其他 Sealos CLI，先备份，不要影响其集群。
sudo install -m 755 "$KIT/tools/sealos-v5.1.1-isolated" /usr/local/bin/sealos
sudo install -m 755 "$KIT/tools/helm-v3.21.3" /usr/local/bin/helm
/usr/local/bin/sealos version
helm version --short
```

若缺少 `tools/`，可根据 [主 README 的构建章节](../README.md#准备-sealos-511-cli) 在**有网络的构建机**预先准备 CLI；部署时不能指望现查网络下载。目标节点还需要 root SSH、Docker（仅当采用 Docker 版 skopeo 导入时）、`kubectl`（K8s rootfs 将安装）、Python 3（Docker 版导入脚本），或事先离线安装的原生 `skopeo`。

## 2. 部署前安全检查（不要跳过）

```bash
hostname; uname -m; df -h / /mnt/data
ss -lntp | grep -E ':(6443|2379|2380|5000|10250)\b' || true
systemctl is-active docker.service containerd.service
# 若需保留 Docker，记录运行容器的完整 ID，部署后 diff：
docker ps -q --no-trunc | sort > /tmp/k8s-deploy-docker-before.txt
ls -ld /etc/kubernetes /var/lib/etcd /var/lib/containerd-v137 \
  /root/.sealos/kubernetes-v137-k8sonly 2>&1 || true
```

- 先确认 Pod 网段 `10.244.0.0/16`、Service 网段 `10.120.0.0/16` **与现有 Docker 网络和主机路由不重叠**（`ip -4 route`、`docker network ls`）；根分区留足空间，**避免 DiskPressure**。node01 曾因根分区仅剩约 30 GB 而无法调度，迁走旧构建临时文件后约剩 37 GB 才恢复；不要清理 Docker 数据来腾空间。
- **若 6443 已占用、存在有效 `/etc/kubernetes/admin.conf` 或目标集群记录已存在，停下确认归属，不要重跑 `sealos apply`。** 旧 Sealos `default` 记录指向 `192.168.0.35`，**不得对它执行 reset**。node01 旧隔离 CRI 的遗留 Pod/shim 已在获授权后按 cgroup 精确清理；其他节点不得照搬 PID 或执行无范围的 `pkill`、`kubeadm reset`、`iptables -F`、`docker prune`。
- 可用 `ssh -o BatchMode=yes root@<目标 IP> hostname` 确认免密 SSH。**`sealos gen` 会探测目标 SSH/架构**，若探测失败，不要只依据“默认 amd64”的警告继续部署。先 `gen`，再修改生成的多文档 Clusterfile，最后 `apply`；不要把旧 `default` 当新集群名。下面命令**只用于新节点**：

```bash
read -r -p '新节点 IP（不要填旧 default 集群 IP）: ' MASTER_IP
read -r -p '唯一新集群名（不要填 default）: ' CLUSTER_NAME
sealos gen bbzhu/kubernetes:v1.37.1-k8s-only \
  --cluster "$CLUSTER_NAME" --masters "$MASTER_IP" \
  -e SEALOS_ISOLATED_CRI=true -e SEALOS_OCI_RUNTIME=runc \
  -o /tmp/Clusterfile.k8s-only.yaml
${EDITOR:-vi} /tmp/Clusterfile.k8s-only.yaml
```

`gen` 生成的默认值**不适合直接用于本隔离 CRI 部署**。修改其**已有**的 YAML 文档（不要重复追加同 kind 对象），对照随离线包交付且已验证的 `$KIT/Clusterfile.cilium.yaml`：

- `Cluster`：`metadata.name`、`spec.hosts`、`spec.image`（离线 tar 标签必须是 `bbzhu/kubernetes:v1.37.1-k8s-only`），以及 `SEALOS_ISOLATED_CRI=true`、`SEALOS_OCI_RUNTIME=runc`。
- `InitConfiguration`：`nodeRegistration.criSocket: unix:///run/containerd-v137/containerd.sock`。
- `ClusterConfiguration`：选择不冲突的 `networking.podSubnet` 和 `networking.serviceSubnet`；node01 已验收的值分别为 `10.244.0.0/16` 和 `10.120.0.0/16`。
- `KubeletConfiguration`：`cgroupDriver: systemd`、`containerRuntimeEndpoint: unix:///run/containerd-v137/containerd.sock`、`imageServiceEndpoint: unix:///run/image-cri-shim-v137.sock`。实测 `sealos gen` 默认输出的是 `cgroupfs` 和共享 `/run/containerd/containerd.sock`，不修改会选错运行时。
- `KubeProxyConfiguration`：本次验证使用 kube-proxy，建议将生成文件的 `mode: ipvs` 改为 `mode: iptables`，与已验收配置保持一致。

若不需要保留 `gen` 自动生成的其他配置，也可以直接复制 `$KIT/Clusterfile.cilium.yaml`，**只**修改新节点 IP、唯一集群名及网段；不要在已有部分初始化记录上重复 apply。

## 3. 离线导入 Kubernetes 镜像并执行 Sealos

```bash
sudo /usr/local/bin/sealos load -i "$KIT/kubernetes-v1.37.1-k8s-only.tar"
sudo /usr/local/bin/sealos images | grep -F 'v1.37.1-k8s-only'
# 必须确认此时是新节点、目标集群名尚未存在：
sudo /usr/local/bin/sealos apply -f /tmp/Clusterfile.k8s-only.yaml
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl get nodes -o wide
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" podCIDR="}{.spec.podCIDR}{"\n"}{end}'
kubectl -n kube-system get pods -o wide
kubectl get --raw=/readyz
kubectl -n kube-system get ds kube-proxy
systemctl is-active registry.service containerd-v137.service image-cri-shim-v137.service kubelet.service
```

此时 API/kube-proxy 应可用且 node 有 PodCIDR；**尚无 CNI，node `NotReady`、CoreDNS Pending 是预期状态**。镜像是经 `sealos load` 进入 Sealos 存储的，Docker 本地有同名镜像不足以替代此步骤。若 apply 中途失败，不要直接再次 apply（失败的记录可能被当作已有集群协调而跳过初始化）：先查 `journalctl -u containerd-v137 -u image-cri-shim-v137 -u kubelet -n 100 --no-pager`，检查目标集群记录。**仅当确认是这次失败的新集群、记录只指向本测试节点且允许清理时**，才能 `sealos reset --cluster <这次的新集群名> --force`，排除原因后重新 load/apply；不要 reset `default`。本镜像的 `scripts/isolated-init.bash` 已针对 shim socket 就绪竞态增加等待。

## 4. 向新 registry 导入 Cilium 镜像

```bash
kubectl get daemonsets -A   # 必须没有 Flannel/其他 CNI 和旧 Cilium
helm list -n kube-system     # 不得已存在 cilium release
(cd "$KIT/cilium-1.20.4-amd64" && sha256sum -c SHA256SUMS >/dev/null)
getent hosts sealos.hub
curl -fsS http://sealos.hub:5000/v2/ >/dev/null
```

在**目标节点**准备仅当前会话可读的 authfile。向管理员取得此**新集群**的 registry 用户名和密码，以下交互输入不会出现在 shell history 或命令参数中；不要照搬旧集群凭据：

```bash
export REGISTRY_AUTHFILE=/run/sealos-cilium-auth.json
python3 - <<'PY'
from getpass import getpass
import os, json, base64
u=input('本集群 registry 用户名: ')
p=getpass('本集群 registry 密码: ')
cred=base64.b64encode(f'{u}:{p}'.encode()).decode()
fd=os.open('/run/sealos-cilium-auth.json',os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
with os.fdopen(fd,'w') as f:
    json.dump({'auths': {'sealos.hub:5000': {'auth': cred}}},f)
PY
export CILIUM_REGISTRY=sealos.hub:5000
# 若目标机已离线安装原生 skopeo：
bash "$KIT/cilium-1.20.4-amd64/import-images.sh"
# 或者，若没有原生 skopeo，使用离线工具镜像（两种方式选其一）：
# docker load -i "$KIT/tools/skopeo-stable-v1.21.0.tar"
# bash "$KIT/cilium-1.20.4-amd64/import-images-docker.sh"
rm -f "$REGISTRY_AUTHFILE"  # 导入完成后删除 tmpfs 凭据
```

Docker 备用脚本只启动临时 skopeo 容器，逐个确认 registry manifest 的 SHA256 与源 OCI 相同、所有 layer/config 可访问后才移除**它自己创建的临时容器**；不会停 Docker 服务或其他容器。node01 上的 Docker 版 skopeo 曾在 Zot 已接受 manifest（HTTP 201）后未正常退出，所以不能仅凭命令超时认定镜像导入失败；该脚本以 digest 和 blob 校验作为成功条件。验证 CRI 会从本地而非上游取镜像（仅需拉取一个较小镜像）：

```bash
/opt/sealos-v137/bin/crictl \
  --runtime-endpoint unix:///run/containerd-v137/containerd.sock \
  --image-endpoint unix:///run/image-cri-shim-v137.sock \
  pull quay.io/cilium/operator-generic:v1.20.4
/opt/sealos-v137/bin/crictl --runtime-endpoint unix:///run/containerd-v137/containerd.sock images \
  | grep 'sealos.hub:5000/cilium/operator-generic'
```

如本地映射未生效，先检查 `journalctl -u image-cri-shim-v137 -n 100 --no-pager` 和 registry manifest；**不要在尚未确认离线镜像可用时安装 Helm release**。

## 5. Helm 安装 Cilium（独立于 Sealos image）

```bash
helm lint "$KIT/cilium-1.20.4-amd64/charts/cilium.tgz" \
  -f "$KIT/cilium-1.20.4-amd64/values.yaml"
helm --kubeconfig "$KUBECONFIG" install cilium \
  "$KIT/cilium-1.20.4-amd64/charts/cilium.tgz" \
  -n kube-system -f "$KIT/cilium-1.20.4-amd64/values.yaml" \
  --wait --timeout 10m
helm list -n kube-system
# Helm 返回 deployed 并不等于所有 Pod 已 Ready；逐一等待：
kubectl -n kube-system rollout status ds/cilium --timeout=10m
kubectl -n kube-system rollout status ds/cilium-envoy --timeout=10m
kubectl -n kube-system rollout status deploy/cilium-operator --timeout=10m
kubectl -n kube-system rollout status deploy/coredns --timeout=10m
kubectl wait nodes --all --for=condition=Ready --timeout=10m
kubectl get --raw=/readyz
kubectl get nodes -o wide
kubectl -n kube-system get pods -o wide
kubectl -n kube-system exec ds/cilium -- cilium status --brief
```

若 operator/CoreDNS 因 `DiskPressure` Pending，先检查 `kubectl describe node`、`df -h /`，按归属安全迁走**旧构建临时文件**；kubelet 压力解除有数分钟缓冲时间。不要清理 Docker 数据或盲目移除 taint。`kube-proxy` 保持启用，values 中 `kubeProxyReplacement: false`。

## 6. Pod / DNS / Service 单节点烟测及清理

测试镜像沿用离线导入的 Cilium image，不新增外网依赖。仅单节点示例；`kubectl create` **只创建临时测试 Pod，并非安装 Cilium**：

```bash
kubectl create -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata: {name: cilium-net-smoke, namespace: default}
spec:
  restartPolicy: Never
  tolerations:
  - {key: node-role.kubernetes.io/control-plane, operator: Exists, effect: NoSchedule}
  containers:
  - name: client
    image: quay.io/cilium/cilium:v1.20.4
    imagePullPolicy: IfNotPresent
    command: ["/usr/bin/sleep", "600"]
YAML
kubectl wait pod/cilium-net-smoke --for=condition=Ready --timeout=2m
kubectl get pod cilium-net-smoke -o wide   # 应有 PodCIDR 内的 IP
kubectl exec cilium-net-smoke -- getent hosts kubernetes.default.svc.cluster.local
kubectl exec cilium-net-smoke -- bash -c \
  'timeout 8 bash -c "echo > /dev/tcp/kubernetes.default.svc.cluster.local/443"'
DNS_POD_IP=$(kubectl -n kube-system get pods -l k8s-app=kube-dns -o jsonpath='{.items[0].status.podIP}')
kubectl exec cilium-net-smoke -- bash -c \
  "timeout 8 bash -c 'echo > /dev/tcp/$DNS_POD_IP/53'"
kubectl delete pod cilium-net-smoke --wait=true --timeout=90s
# 对照部署前 Docker 容器 ID，须无差异：
docker ps -q --no-trunc | sort | diff -u /tmp/k8s-deploy-docker-before.txt -
```

若需验证服务重启恢复，可仅在维护窗口执行 `systemctl restart containerd-v137 image-cri-shim-v137 kubelet` 后重跑第 5 节验收；**不要为此重启整台保留 Docker 工作负载的宿主机**。本次已做隔离服务重启，**未做整机重启、多节点、跨版本 Helm 升级或回滚**。后续升级 Cilium 要先准备新版本 Chart/OCI 镜像并导入，再经 Helm upgrade；不能修改 Kubernetes Sealos rootfs 镜像或重用旧版 `kubectl apply` 安装脚本。兼容性与生产采用前检查见 [Cilium 离线包说明](../cilium/README.md)。
