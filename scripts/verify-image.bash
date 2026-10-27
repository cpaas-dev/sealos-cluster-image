#!/usr/bin/env bash
set -euo pipefail

[[ $(kubelet --version) == 'Kubernetes v1.37.1' ]]
[[ $(kubeadm version -o short) == 'v1.37.1' ]]
containerd --config /etc/config.toml config dump > /tmp/verified-containerd.toml
grep -q "default_runtime_name = 'crun'" /tmp/verified-containerd.toml
grep -q "sandbox = 'registry.k8s.io/pause:3.10.2'" /tmp/verified-containerd.toml

# Exercise the registry from the packaged files without an upstream registry.
config='{"storage":{"rootDirectory":"/registry","gc":false,"dedupe":false},"http":{"address":"127.0.0.1","port":15000},"log":{"level":"error"}}'
printf '%s\n' "$config" > /tmp/verify-zot.json
zot serve /tmp/verify-zot.json > /tmp/verify-zot.log 2>&1 &
zot_pid=$!
trap 'kill "$zot_pid" 2>/dev/null || true; wait "$zot_pid" 2>/dev/null || true; rm -f /tmp/verified-containerd.toml /tmp/verify-zot.json /tmp/verify-zot.log' EXIT
for attempt in {1..30}; do
  if curl --noproxy '*' --silent --fail http://127.0.0.1:15000/v2/ > /dev/null; then
    break
  fi
  sleep 1
done
while read -r image; do
  [[ -n "$image" ]] || continue
  repo_tag=${image#*/}
  repo=${repo_tag%:*}
  tag=${repo_tag##*:}
  test -s "/registry/${repo}/index.json"
  curl --noproxy '*' --silent --show-error --fail --max-time 15 \
    -H 'Accept: application/vnd.oci.image.manifest.v1+json, application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.docker.distribution.manifest.list.v2+json' \
    "http://127.0.0.1:15000/v2/${repo}/manifests/${tag}" > /dev/null
  printf 'Verified offline manifest: %s\n' "$image"
done < <(kubeadm config images list --kubernetes-version v1.37.1; cat /images/shim/AddonImageList)
test -s /manifests/cilium.yaml
for image in $(cat /images/shim/AddonImageList); do
  repo_tag=${image#*/}
  repo=${repo_tag%:*}
  tag=${repo_tag##*:}
  test -s "/registry/${repo}/index.json"
  printf 'Verified addon layout: %s\n' "$image"
done
echo 'Image verification passed'
