#!/usr/bin/env bash

# 校验手动触发时输入的 Kubernetes 版本，产出构建用的版本号。
#
# 版本已有 Release 时直接失败，不覆盖。
#
# 用法：resolve_build.bash
#
# 环境变量：
#   INPUT_VERSION  必填，workflow_dispatch 的 kubernetes_version，如 v1.35.9
#   GH_TOKEN       gh CLI 凭据
#   GH_REPO        目标仓库，如 cpaas-dev/sealos-cluster-image
#
# 输出：
#   $GITHUB_OUTPUT 里的 version=<vX.Y.Z>

set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.bash"

: "${INPUT_VERSION:?INPUT_VERSION is required}"
version="${INPUT_VERSION}"

if [[ ! "${version}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    fail "invalid kubernetes version: '${version}' (expected vMAJOR.MINOR.PATCH)"
fi

# Each minor lives on its own branch (v1.33.x, v1.34.x, ...) whose Dockerfile
# carries minor-specific settings such as sandboxImage, so the requested
# version must belong to the minor this branch's Dockerfile defaults to.
branch_default="$(sed -n 's/^ARG INST_KUBERNETES_V=\(.*\)$/\1/p' Dockerfile | head -n 1)"
[[ -n "${branch_default}" ]] || fail "no ARG INST_KUBERNETES_V found in Dockerfile"
want_minor="${branch_default%.*}"
got_minor="${version%.*}"
if [[ "${got_minor}" != "${want_minor}" ]]; then
    fail "${version} does not belong to this branch: its Dockerfile defaults to ${branch_default} (${want_minor}.x), run the workflow on the ${got_minor}.x branch instead"
fi

if gh release view "${version}" --json tagName >/dev/null 2>&1; then
    fail "${version} already released (repo=${GH_REPO:-}), delete the release and tag to rebuild it"
fi

echo "version=${version}"
emit_output "version=${version}"

{
    echo "### Build plan"
    echo
    echo "- kubernetes: \`${version}\`"
} | emit_summary
