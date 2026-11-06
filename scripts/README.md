# Sealos rootfs 生命周期脚本

以下标签命令由 Sealos 在目标节点执行。**新集群完整部署顺序**请看 [Kubernetes 1.37.1 离线部署操作手册](../deploy/OPERATIONS_K8S_1.37.1_OFFLINE.md)；不要单独运行清理脚本来“修复”未知集群。

## 本地镜像服务初始化

```bash
registry-init.bash $registryData $registryConfig
```

安装并启动本地 Zot OCI registry，默认端口为 5000。对应清理命令：

```bash
registry-clean.bash $registryData $registryConfig
```

## 节点检查

```bash
check.bash $registryData
```

检查宿主机端口、CRI 清理状态、registry 存储和 AppArmor 支持情况。

## Kubernetes / CRI 初始化

```bash
cri-init.bash $registryDomain $registryPort && bash init.bash
```

非隔离模式下，`cri-init.bash` 调用 image-cri-shim、crun 和 containerd 初始化脚本；随后启用 kubelet。**已运行 Docker 的节点必须使用隔离模式**，不能让这些非隔离操作影响共享运行时。

当 Clusterfile 设置 `SEALOS_ISOLATED_CRI=true` 时，`cri-init.bash` 改为调用 `isolated-init.bash`：将 Kubernetes 和独立运行时二进制安装到 `/opt/sealos-v137/bin`，启动 `containerd-v137` 与 `image-cri-shim-v137`，将 kubelet 指向 `/run/containerd-v137/containerd.sock`，并在独立 CRI shim 就绪后拉取离线 pause 镜像。此模式下 `init.bash` 不操作共享 Docker containerd。

镜像包含 crun 与 runc；独立 containerd 默认选择 runc。部署前可设置 `SEALOS_OCI_RUNTIME=crun` 选择 crun，其他值会被拒绝。这一设置不切换 Docker 的运行时。

## 清理（破坏性操作）

```bash
clean.bash && bash cri-clean.bash $criData
```

非隔离模式可能停止 kubelet/containerd 并删除 CRI 数据。隔离模式下 `clean.bash` 运行 `isolated-clean.bash`，停止 v1.37 的 kubelet、shim、独立 containerd 并清理**该集群**的配置和数据；`cri-clean.bash` 在此模式下不执行共享 containerd 清理。**清理会销毁目标 Kubernetes 集群，必须先确认集群名、IP、授权和 Docker 保留边界。**旧 Sealos `default` 记录指向其它节点，切勿对它执行 reset。
