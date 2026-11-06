#!/usr/bin/env bash
# Offline fallback when skopeo is available only as a locally loaded Docker image.
# Only disposable containers created by this script are removed; it never stops Docker.
set -euo pipefail
bundle=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
: "${REGISTRY_AUTHFILE:?Set REGISTRY_AUTHFILE to a skopeo-compatible registry authfile}"
: "${CILIUM_REGISTRY:=sealos.hub:5000}"
: "${SKOPEO_IMAGE:=quay.io/skopeo/stable:v1.21.0}"
[[ -r "$REGISTRY_AUTHFILE" ]] || { echo 'Registry authfile is not readable' >&2; exit 1; }
# Sealos supplies an HTTP registry at this address. Do not silently use HTTP for other hosts.
[[ "$CILIUM_REGISTRY" == sealos.hub:5000 ]] || { echo 'Docker fallback supports only sealos.hub:5000 (HTTP)' >&2; exit 1; }
command -v docker >/dev/null
command -v python3 >/dev/null
docker image inspect "$SKOPEO_IMAGE" >/dev/null # must be preloaded, never pull upstream
current=''
cleanup() {
  if [[ -n "$current" ]]; then
    docker rm -f "$current" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
while IFS= read -r image; do
  [[ -n "$image" ]] || continue
  repo_tag=${image#*/}
  repo=${repo_tag%:*}
  tag=${repo_tag##*:}
  src="$bundle/registry/$repo"
  [[ -s "$src/index.json" ]] || { echo "Missing offline image: $src" >&2; exit 1; }
  echo "Importing $image to $CILIUM_REGISTRY/$repo:$tag"
  current=$(docker run -d --pull never --network host --read-only \
    --tmpfs /tmp:rw,nosuid,size=1g --security-opt no-new-privileges \
    --mount "type=bind,src=$bundle,dst=/bundle,readonly" \
    --mount "type=bind,src=$REGISTRY_AUTHFILE,dst=/run/auth.json,readonly" \
    "$SKOPEO_IMAGE" copy --all --dest-tls-verify=false \
    --dest-authfile /run/auth.json "oci:/bundle/registry/$repo:$tag" \
    "docker://$CILIUM_REGISTRY/$repo:$tag")
  verified=false
  for attempt in $(seq 1 90); do
    if BUNDLE="$bundle" REPO="$repo" TAG="$tag" REGISTRY_AUTHFILE="$REGISTRY_AUTHFILE" python3 - <<'PY'
import base64, hashlib, json, os, pathlib, urllib.request, urllib.error
base=pathlib.Path(os.environ['BUNDLE'])/'registry'/os.environ['REPO']
tag=os.environ['TAG']
refs=[m for m in json.loads((base/'index.json').read_bytes())['manifests']
      if m.get('annotations',{}).get('org.opencontainers.image.ref.name')==tag]
assert len(refs)==1, 'Expected exactly one manifest for tag'
expected=refs[0]['digest'].split(':',1)[1]
registry='sealos.hub:5000'
auths=json.loads(pathlib.Path(os.environ['REGISTRY_AUTHFILE']).read_bytes())['auths']
headers={'Accept':'application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json'}
if registry in auths:headers['Authorization']='Basic '+auths[registry]['auth']
opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
url=f'http://{registry}/v2/{os.environ["REPO"]}'
try:
    with opener.open(urllib.request.Request(f'{url}/manifests/{tag}',headers=headers),timeout=4) as r:
        data=r.read()
    assert hashlib.sha256(data).hexdigest()==expected, 'Registry manifest differs from offline image'
    manifest=json.loads(data)
    assert manifest.get('layers') and manifest.get('config'), 'Incomplete image manifest'
    for blob in [manifest['config']]+manifest['layers']:
        with opener.open(urllib.request.Request(f'{url}/blobs/{blob["digest"]}',
                                                headers=headers,method='HEAD'),timeout=4) as r:
            assert r.status==200
except (OSError,urllib.error.URLError,AssertionError,ValueError) as ex:
    raise SystemExit(str(ex))
PY
    then
      verified=true
      break
    fi
    sleep 2
  done
  if [[ "$verified" != true ]]; then
    docker logs --tail 20 "$current" >&2 || true
    echo "Registry import not verified for $image" >&2
    exit 1
  fi
  # Some versions of the Docker runner remain running after Zot accepted PUT 201.
  # Kill only this disposable importer, and only after verifying digest and blobs.
  cleanup
  current=''
  echo "Verified local registry manifest and blobs: $image"
done < "$bundle/AddonImageList"
