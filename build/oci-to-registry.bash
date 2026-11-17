#!/usr/bin/env bash

# Convert OCI image layouts into the docker-distribution filesystem layout that
# sealos syncs from <rootfs>/registry to the registry host.
#
# The images are pushed through `sealctl registry serve filesystem`, the same
# storage code sealos uses on the registry host at deploy time, so the output is
# exactly the format sealos expects (docker/registry/v2/...).
#
# Every directory under LAYOUT_ROOT that contains an `oci-layout` file is one
# repository; its path relative to LAYOUT_ROOT is the repository name, e.g.
#   <root>/kube-apiserver   -> sealos.hub:5000/kube-apiserver
#   <root>/labring/lvscare  -> sealos.hub:5000/labring/lvscare
# Every tag recorded in the layout is copied with its full multi-arch index, so
# one registry/ serves amd64 and arm64 nodes alike.
#
# The temporary server listens on a fixed port; the script fails if that server
# is not the one it started (e.g. another build step already holds the port),
# instead of silently writing the images into someone else's directory.
#
# Usage: oci-to-registry.bash REGISTRY_DIR LAYOUT_ROOT [LAYOUT_ROOT...]
#
# Requires `sealctl`, `oras` and `curl` in PATH.

set -euo pipefail

readonly PORT=5000

fail() {
    echo "oci-to-registry: $*" >&2
    exit 1
}

if [[ $# -lt 2 ]]; then
    fail "usage: oci-to-registry.bash REGISTRY_DIR LAYOUT_ROOT [LAYOUT_ROOT...]"
fi

registry_dir=$1
shift

mkdir -p "${registry_dir}"
sealctl registry serve filesystem -p "${PORT}" --disable-logging "${registry_dir}" &
serve_pid=$!
trap 'kill "${serve_pid}" 2>/dev/null || true; wait "${serve_pid}" 2>/dev/null || true' EXIT

endpoint="127.0.0.1:${PORT}"
for _ in $(seq 1 60); do
    if curl -fsS -o /dev/null "http://${endpoint}/v2/" 2>/dev/null; then
        break
    fi
    kill -0 "${serve_pid}" 2>/dev/null || fail "sealctl registry serve exited early (dir=${registry_dir}, port=${PORT})"
    sleep 0.5
done
curl -fsS -o /dev/null "http://${endpoint}/v2/" \
    || fail "registry at ${endpoint} not ready after 30s (dir=${registry_dir})"
# The endpoint answering is not enough: if the port was already taken, our
# server has exited and we would be talking to a foreign one.
sleep 1
kill -0 "${serve_pid}" 2>/dev/null \
    || fail "sealctl registry serve exited, port ${PORT} is held by another process (dir=${registry_dir})"

count=0
for root in "$@"; do
    [[ -d "${root}" ]] || fail "layout root not found: ${root}"
    mapfile -t layouts < <(find "${root}" -name oci-layout -type f -printf '%h\n' | sort)
    [[ ${#layouts[@]} -gt 0 ]] || fail "no OCI layout found under ${root}"

    for layout in "${layouts[@]}"; do
        repo="${layout#"${root}"/}"
        mapfile -t tags < <(oras repo tags --oci-layout "${layout}")
        [[ ${#tags[@]} -gt 0 ]] || fail "OCI layout has no tags: ${layout}"

        for tag in "${tags[@]}"; do
            echo "oci-to-registry: ${layout}:${tag} -> ${repo}:${tag}"
            oras cp --from-oci-layout "${layout}:${tag}" --to-plain-http "${endpoint}/${repo}:${tag}"
            [[ -d "${registry_dir}/docker/registry/v2/repositories/${repo}/_manifests/tags/${tag}" ]] \
                || fail "pushed ${repo}:${tag} but it is not in ${registry_dir}, another registry answered on port ${PORT}"
            count=$((count + 1))
        done
    done
done

echo "oci-to-registry: ${count} image(s) written to ${registry_dir}"
curl -fsS "http://${endpoint}/v2/_catalog"
echo
