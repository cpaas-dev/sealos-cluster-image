#!/usr/bin/env bash
set -euo pipefail

: "${KUBECONFIG:=/etc/kubernetes/admin.conf}"
export KUBECONFIG
rootfs_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
manifest="${CILIUM_MANIFEST:-${rootfs_dir}/manifests/cilium.yaml}"

command -v kubectl >/dev/null || { echo 'kubectl is required' >&2; exit 1; }
[[ -s "$manifest" ]] || { echo "Packaged Cilium manifest not found: $manifest" >&2; exit 1; }

flannel=$(kubectl get daemonsets --all-namespaces -l app=flannel -o name)
[[ -z "$flannel" ]] || { echo 'Flannel is installed; complete the CNI migration before installing Cilium.' >&2; exit 1; }
kubectl -n kube-system get daemonset kube-proxy >/dev/null
pod_cidrs=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"="}{.spec.podCIDR}{"\n"}{end}')
while IFS='=' read -r node cidr; do
  [[ -n "$cidr" ]] || { echo "PodCIDR is not assigned for node: $node" >&2; exit 1; }
done <<< "$pod_cidrs"

kubectl apply --server-side --field-manager=sealos-cilium -f "$manifest"

kubectl -n kube-system rollout status daemonset/cilium --timeout=5m
kubectl -n kube-system rollout status daemonset/cilium-envoy --timeout=5m
kubectl -n kube-system rollout status deployment/cilium-operator --timeout=5m
kubectl -n kube-system get pods -l k8s-app=cilium -o wide
