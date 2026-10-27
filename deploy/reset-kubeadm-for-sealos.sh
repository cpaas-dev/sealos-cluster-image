#!/usr/bin/env bash
set -euo pipefail

[[ ${RESET_CURRENT_V137:-} == 1 ]] || { echo 'Set RESET_CURRENT_V137=1.' >&2; exit 1; }
[[ $(id -u) == 0 && $(hostname) == node01 ]] || { echo 'Expected root on node01.' >&2; exit 1; }
export KUBECONFIG=/etc/kubernetes/admin.conf
[[ $(kubectl get node node01 -o jsonpath='{.status.nodeInfo.kubeletVersion}') == v1.37.1 ]]
[[ -z $(kubectl get pvc -A -o name) ]]
[[ -z $(kubectl get pods -A --field-selector=status.phase!=Running -o name) ]]
if kubectl get pods -A --no-headers | awk '$1 != "kube-system" { found=1 } END { exit !found }'; then
    echo 'Non-system Pods found; reset aborted.' >&2
    exit 1
fi
[[ $(systemctl is-active docker) == active && $(systemctl is-active containerd) == active ]]
[[ $(systemctl is-active containerd-v137) == active ]]
kubeadm_bin=/opt/sealos-v137-next/bin/kubeadm
[[ -x $kubeadm_bin ]] || { echo "Missing $kubeadm_bin" >&2; exit 1; }

evidence=/opt/sealos-v137-next/validation/sealos-reset
mkdir -p "$evidence"
chmod 700 "$evidence"
docker ps -q --no-trunc | sort > "$evidence/docker-before.txt"
systemctl show docker containerd -p MainPID > "$evidence/docker-pids-before.txt"
kubectl get pods -A -o wide > "$evidence/kubernetes-before.txt"
cp -a /etc/kubernetes "$evidence/kubernetes-before"
[[ ! -d /etc/cni/net.d ]] || cp -a /etc/cni/net.d "$evidence/cni-before"

systemctl stop kubelet
"$kubeadm_bin" reset --force --cri-socket unix:///run/containerd-v137/containerd.sock
rm -f /etc/cni/net.d/05-cilium.conflist /etc/cni/net.d/10-flannel.conflist
rm -f /root/.kube/config
rm -f /etc/systemd/system/kubelet.service.d/20-v137.conf
systemctl daemon-reload

docker ps -q --no-trunc | sort > "$evidence/docker-after-reset.txt"
cmp "$evidence/docker-before.txt" "$evidence/docker-after-reset.txt"
systemctl show docker containerd -p MainPID > "$evidence/docker-pids-after-reset.txt"
cmp "$evidence/docker-pids-before.txt" "$evidence/docker-pids-after-reset.txt"
echo 'Kubeadm cluster reset; Docker baseline preserved.'
