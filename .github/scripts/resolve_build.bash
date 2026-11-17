#!/usr/bin/env bash

# 解析本次构建的 Kubernetes 版本，以及是否推送镜像并发布 Release。
#
#   workflow_dispatch   kubernetes_version 输入作为版本，推送并发布；
#                       该版本已有 Release 时直接失败，不覆盖
#   其余（push、PR）    取 Dockerfile 里 INST_KUBERNETES_V 的默认值，只构建不推送
#
# 用法：resolve_build.bash
#
# 环境变量：
#   EVENT_NAME     github.event_name
#   INPUT_VERSION  workflow_dispatch 的 kubernetes_version，其余事件为空
#   GH_TOKEN       gh CLI 凭据（workflow_dispatch 时检查已有 Release）
#   GH_REPO        目标仓库，如 cpaas-dev/sealos-cluster-image
#
# 输出：
#   $GITHUB_OUTPUT 里的 version=<vX.Y.Z> 与 push=<true|false>

set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.bash"

: "${EVENT_NAME:?EVENT_NAME is required}"
INPUT_VERSION="${INPUT_VERSION:-}"

if [[ "${EVENT_NAME}" == "workflow_dispatch" ]]; then
    version="${INPUT_VERSION}"
    push=true
else
    version="$(sed -n 's/^ARG INST_KUBERNETES_V=\(.*\)$/\1/p' Dockerfile | head -n 1)"
    push=false
fi

if [[ ! "${version}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    fail "invalid kubernetes version: '${version}' (event=${EVENT_NAME}, expected vMAJOR.MINOR.PATCH)"
fi

if [[ "${push}" == "true" ]] && gh release view "${version}" --json tagName >/dev/null 2>&1; then
    fail "${version} already released (repo=${GH_REPO:-}), delete the release and tag to rebuild it"
fi

echo "version=${version}"
echo "push=${push}"
emit_output "version=${version}"
emit_output "push=${push}"

{
    echo "### Build plan"
    echo
    echo "- kubernetes: \`${version}\`"
    echo "- push and release: \`${push}\`"
} | emit_summary
