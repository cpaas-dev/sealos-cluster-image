#!/usr/bin/env bash
# Run only after Sealos has started its registry on a fresh cluster.
set -euo pipefail
bundle=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
: "${REGISTRY_AUTHFILE:?Set REGISTRY_AUTHFILE to a skopeo-compatible authfile for the Sealos registry}"
: "${CILIUM_REGISTRY:=sealos.hub:5000}"
command -v skopeo >/dev/null || { echo 'skopeo is required' >&2; exit 1; }
[[ -r "$REGISTRY_AUTHFILE" ]] || { echo 'Registry authfile is not readable' >&2; exit 1; }
while IFS= read -r image; do
  [[ -n "$image" ]] || continue
  repo_tag=${image#*/}
  repo=${repo_tag%:*}
  tag=${repo_tag##*:}
  src="${bundle}/registry/${repo}"
  [[ -s "${src}/index.json" ]] || { echo "Missing offline OCI image: $src" >&2; exit 1; }
  skopeo copy --all --dest-tls-verify=false --dest-authfile "$REGISTRY_AUTHFILE" \
    "oci:${src}:${tag}" "docker://${CILIUM_REGISTRY}/${repo}:${tag}"
done < "${bundle}/AddonImageList"
