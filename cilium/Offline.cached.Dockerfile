# syntax=docker.io/docker/dockerfile:1.25.0
# One-time offline export from the verified legacy image, without copying its Kubernetes content.
# For future independent Cilium releases use Offline.Dockerfile instead.
FROM bbzhu/kubernetes:v1.37.1 AS legacy
FROM scratch
COPY --from=legacy /charts/cilium.tgz /charts/cilium.tgz
COPY --from=legacy /registry/cilium/ /registry/cilium/
COPY cilium/values.yaml /values.yaml
COPY cilium/AddonImageList /AddonImageList
COPY cilium/import-images.sh /import-images.sh
COPY cilium/import-images-docker.sh /import-images-docker.sh
COPY cilium/README.md /README.md
COPY cilium/VERSION /VERSION
