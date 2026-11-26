#!/usr/bin/env bash

# 创建 GitHub Release（同时创建同名 tag）。
#
# 用法：create_release.bash VERSION IMAGE_REF
#
# 参数：
#   VERSION     Kubernetes 版本，也是 tag 名，如 v1.37.3
#   IMAGE_REF   已推送的镜像，如 ghcr.io/cpaas-dev/sealos-cluster-image:v1.37.3
#
# 环境变量：
#   GH_TOKEN      gh CLI 凭据
#   GH_REPO       目标仓库
#   GITHUB_SHA    Release / tag 指向的 commit；留空则由 gh 用默认分支

set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.bash"

V="${1:-}"
REF="${2:-}"

if [[ -z "${V}" || -z "${REF}" ]]; then
    echo "usage: create_release.bash VERSION IMAGE_REF" >&2
    exit 1
fi

if gh release view "${V}" --json tagName >/dev/null 2>&1; then
    fail "${V} already released, refusing to overwrite"
fi

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

# Component versions are the first ARG defaults in the Dockerfile; Kubernetes
# comes from VERSION because CI overrides INST_KUBERNETES_V with it.
mapfile -t components < <(
    sed -n 's/^ARG INST_\([A-Z_]*\)_V=\(.*\)$/\1 \2/p' Dockerfile | awk '!seen[$1]++'
)
[[ ${#components[@]} -gt 0 ]] || fail "no INST_*_V found in Dockerfile"

{
    echo "Sealos cluster image (rootfs) for Kubernetes \`${V}\`."
    echo
    echo "## 镜像"
    echo
    echo '```bash'
    echo "sealos run ${REF} --masters <ip> --nodes <ip>"
    echo '```'
    echo
    echo "## 组件"
    echo
    echo "| 组件 | 版本 |"
    echo "| --- | --- |"
    for c in "${components[@]}"; do
        name="${c%% *}"
        ver="${c#* }"
        [[ "${name}" == "KUBERNETES" ]] && ver="${V}"
        echo "| ${name,,} | \`${ver}\` |"
    done
} > "${workdir}/notes.md"

create_args=(
    "${V}"
    --title "${V}"
    --notes-file "${workdir}/notes.md"
)

if [[ -n "${GITHUB_SHA:-}" ]]; then
    create_args+=(--target "${GITHUB_SHA}")
fi

gh release create "${create_args[@]}"

{
    echo "### Released ${V}"
    echo
    echo "- image: \`${REF}\`"
    echo "- release: ${GITHUB_SERVER_URL:-https://github.com}/${GH_REPO:-}/releases/tag/${V}"
} | emit_summary
