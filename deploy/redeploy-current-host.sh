#!/usr/bin/env bash
set -euo pipefail

[[ ${RESET_CURRENT_V137:-} == 1 ]] || { echo 'Set RESET_CURRENT_V137=1 to rebuild the current Kubernetes cluster.' >&2; exit 1; }
[[ $(id -u) == 0 ]] || { echo 'Run as root.' >&2; exit 1; }
[[ $(hostname) == node01 ]] || { echo 'Expected node01.' >&2; exit 1; }

stage=/opt/sealos-v137-next
cri=unix:///run/containerd-v137/containerd.sock
validation="$stage/validation"
mkdir -p "$validation"
chmod 700 "$validation"
exec > >(tee -a "$validation/redeploy.log") 2>&1
[[ -s "$stage/manifests/cilium.yaml" && -s "$stage/image-id" ]]
[[ $(docker image inspect bbzhu/kubernetes:v1.37.1 --format '{{.Id}}') == "$(cat "$stage/image-id")" ]]
[[ $(find "$stage/registry" -name index.json | wc -l) == 10 ]]
[[ $(systemctl is-active docker) == active ]]
[[ $(systemctl is-active containerd) == active ]]
[[ $(systemctl is-active containerd-v137) == active ]]
[[ $(kubectl --kubeconfig=/etc/kubernetes/admin.conf get node node01 -o jsonpath='{.status.nodeInfo.kubeletVersion}') == v1.37.1 ]]
[[ -z $(kubectl --kubeconfig=/etc/kubernetes/admin.conf get pvc -A -o name) ]]
[[ -z $(kubectl --kubeconfig=/etc/kubernetes/admin.conf -n kube-system get daemonset cilium -o name --ignore-not-found) ]] || {
  echo 'Cilium is already installed; refusing another reset.' >&2
  exit 1
}
pods=$(kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -A --no-headers)
if awk '$1 != "kube-system" && $1 != "kube-flannel" { found=1 } END { exit !found }' <<< "$pods"; then
  echo 'Found non-system Pods; refusing reset.' >&2
  exit 1
fi

docker_pid=$(systemctl show -p MainPID --value docker)
docker_containerd_pid=$(systemctl show -p MainPID --value containerd)
docker ps -q --no-trunc | sort > "$validation/docker-running-before.txt"
kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -A -o wide > "$validation/kubernetes-before.txt"
cp -a /etc/kubernetes "$validation/kubernetes-before"
if [[ -d /etc/cni/net.d ]]; then
  cp -a /etc/cni/net.d "$validation/cni-net.d-before"
fi

for image in \
  registry.k8s.io/kube-apiserver:v1.37.1 \
  registry.k8s.io/kube-controller-manager:v1.37.1 \
  registry.k8s.io/kube-scheduler:v1.37.1 \
  registry.k8s.io/kube-proxy:v1.37.1 \
  registry.k8s.io/coredns/coredns:v1.14.6 \
  registry.k8s.io/pause:3.10.2 \
  registry.k8s.io/etcd:3.7.0-0 \
  quay.io/cilium/cilium:v1.20.4 \
  quay.io/cilium/operator-generic:v1.20.4 \
  quay.io/cilium/cilium-envoy:v1.39.5-1792733054-8c73b2816bc8239e27f1fd53b271884688137459; do
  "$stage/bin/ctr" --address /run/containerd-v137/containerd.sock --namespace k8s.io images ls -q | grep -Fxq "$image" || {
    echo "Missing image in Kubernetes containerd: $image" >&2
    exit 1
  }
done

systemctl stop kubelet
"$stage/bin/kubeadm" reset --force --cri-socket "$cri"
rm -f /etc/cni/net.d/10-flannel.conflist
ip link show flannel.1 >/dev/null 2>&1 && ip link delete flannel.1
if ip -o -4 addr show cni0 | grep -q '10\.244\.0\.1/24'; then
  ip link delete cni0
fi

install -m 755 "$stage/bin/kubeadm" /usr/local/bin/kubeadm
install -m 755 "$stage/bin/kubectl" /usr/local/bin/kubectl
install -m 755 "$stage/bin/kubelet" /usr/local/bin/kubelet
"$stage/bin/kubeadm" init --config /opt/sealos-v137/kubeadm.yaml --skip-token-print
"$stage/bin/kubeadm" init phase addon all --config /opt/sealos-v137/kubeadm-addons.yaml

export KUBECONFIG=/etc/kubernetes/admin.conf
for attempt in {1..60}; do
  [[ -n $(kubectl get node node01 -o jsonpath='{.spec.podCIDR}') ]] && break
  sleep 2
done
bash "$stage/deploy/cilium-install.sh"
kubectl wait --for=condition=Ready node/node01 --timeout=5m
kubectl -n kube-system rollout status deployment/coredns --timeout=5m
kubectl get pods -A -o wide | tee "$validation/kubernetes-after.txt"
docker ps -q --no-trunc | sort > "$validation/docker-running-after.txt"
cmp "$validation/docker-running-before.txt" "$validation/docker-running-after.txt"
[[ $(systemctl show -p MainPID --value docker) == "$docker_pid" ]]
[[ $(systemctl show -p MainPID --value containerd) == "$docker_containerd_pid" ]]
echo 'Kubernetes v1.37.1 with Cilium deployed; Docker process and container IDs unchanged.'
