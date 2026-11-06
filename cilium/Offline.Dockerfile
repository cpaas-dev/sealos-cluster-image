# syntax=docker.io/docker/dockerfile:1.25.0
# Export with: docker build --platform linux/amd64 -f cilium/Offline.Dockerfile \
#   --output type=local,dest=/path/to/cilium-offline .
FROM quay.io/skopeo/stable:v1.21.0 AS bundle
ARG TARGETARCH
ARG CILIUM_VERSION=1.20.4
COPY cilium/AddonImageList /build/AddonImageList
COPY cilium/values.yaml /bundle/values.yaml
COPY cilium/import-images.sh /bundle/import-images.sh
COPY cilium/import-images-docker.sh /bundle/import-images-docker.sh
COPY cilium/README.md /bundle/README.md
COPY cilium/VERSION /bundle/VERSION
RUN mkdir -p /bundle/charts /bundle/registry \
    && curl --fail --location --retry 3 \
      "https://helm.cilium.io/cilium-${CILIUM_VERSION}.tgz" -o /bundle/charts/cilium.tgz \
    && echo '505abff8385811df1a949776fc42e9f10697989a332acc86d6e8933efcb855ed  /bundle/charts/cilium.tgz' | sha256sum -c - \
    && cp /build/AddonImageList /bundle/AddonImageList
RUN while read -r image; do \
      repo_tag="${image#*/}"; repo="${repo_tag%:*}"; tag="${repo_tag##*:}"; \
      mkdir -p "/bundle/registry/${repo}"; \
      skopeo copy --retry-times 3 --override-os linux --override-arch "${TARGETARCH}" \
        "docker://${image}" "oci:/bundle/registry/${repo}:${tag}" || exit 1; \
    done < /build/AddonImageList
FROM scratch
COPY --from=bundle /bundle/ /
