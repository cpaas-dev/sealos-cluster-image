#!/usr/bin/env bash

# 断言已推送的镜像确实是含指定平台的 manifest list。
#
# 防止构建静默退化成单架构（例如 platforms 配错、QEMU 没装上）。
#
# 用法：verify_manifest.bash IMAGE_REF [PLATFORM...]
#
# 参数：
#   IMAGE_REF   完整镜像引用，如 ghcr.io/foo/bar:v2.3.4
#   PLATFORM    要求存在的平台，如 linux/amd64；可给多个，默认 linux/amd64 linux/arm64

set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.bash"

ref="${1:-}"
if [[ -z "${ref}" ]]; then
    echo "usage: verify_manifest.bash IMAGE_REF [PLATFORM...]" >&2
    exit 1
fi
shift

platforms=("$@")
if [[ ${#platforms[@]} -eq 0 ]]; then
    platforms=(linux/amd64 linux/arm64)
fi

docker buildx imagetools inspect "${ref}"

raw="$(docker buildx imagetools inspect --raw "${ref}")"

for want in "${platforms[@]}"; do
    os="${want%%/*}"
    arch="${want##*/}"
    if ! jq -e --arg os "${os}" --arg arch "${arch}" \
        'any(.manifests[]?; .platform.os == $os and .platform.architecture == $arch)' \
        <<<"${raw}" >/dev/null; then
        fail "manifest list of ${ref} is missing ${want}"
    fi
done

echo "manifest list contains: ${platforms[*]}"
