# syntax=docker.io/docker/dockerfile:1.25.0

# https://github.com/cpaas-dev/kluster-vendor-kubernetes/releases
ARG INST_KUBERNETES_V=v1.33.13
# https://github.com/cpaas-dev/kluster-vendor-containerd/releases
ARG INST_CONTAINERD_V=v2.4.2
# https://github.com/cpaas-dev/kluster-vendor-runc/releases
ARG INST_RUNC_V=v1.5.3
# https://github.com/cpaas-dev/kluster-vendor-crun/releases
ARG INST_CRUN_V=v1.31
# https://github.com/cpaas-dev/kluster-vendor-registry/releases
ARG INST_REGISTRY_V=v3.1.2
# https://github.com/cpaas-dev/kluster-vendor-oras/releases
ARG INST_ORAS_V=v1.4.0
# https://github.com/cpaas-dev/kluster-vendor-sealos/releases
ARG INST_SEALOS_V=v5.1.2
# https://github.com/cpaas-dev/kluster-vendor-cri-tools/releases
ARG INST_CRI_TOOLS_V=v1.37.0

FROM ghcr.io/cpaas-dev/kluster-vendor-kubernetes:${INST_KUBERNETES_V} AS kubernetes
FROM ghcr.io/cpaas-dev/kluster-vendor-containerd:${INST_CONTAINERD_V} AS containerd
FROM ghcr.io/cpaas-dev/kluster-vendor-runc:${INST_RUNC_V} AS runc
FROM ghcr.io/cpaas-dev/kluster-vendor-crun:${INST_CRUN_V} AS crun
FROM ghcr.io/cpaas-dev/kluster-vendor-registry:${INST_REGISTRY_V} AS distribution
FROM ghcr.io/cpaas-dev/kluster-vendor-oras:${INST_ORAS_V} AS oras
FROM ghcr.io/cpaas-dev/kluster-vendor-sealos:${INST_SEALOS_V} AS sealos
FROM ghcr.io/cpaas-dev/kluster-vendor-cri-tools:${INST_CRI_TOOLS_V} AS cri-tools

# ---------------------------------------------------------------------------
# registry
#    Convert the vendored OCI layouts into the docker-distribution layout that
#    sealos syncs from <rootfs>/registry to the registry host. Keeps the full
#    multi-arch index, so it runs once on the build platform and every target
#    platform gets the same registry/ (amd64 + arm64 images).
# ---------------------------------------------------------------------------
FROM --platform=${BUILDPLATFORM} ghcr.io/cpaas-dev/kluster-vendor-sealos:${INST_SEALOS_V} AS registry-tools

FROM --platform=${BUILDPLATFORM} ghcr.io/cpaas-dev/kluster-vendor-kubernetes:${INST_KUBERNETES_V} AS registry

COPY --from=registry-tools /cpaas/vendor/sealos/sealctl /usr/local/bin/sealctl
COPY --from=registry-tools /cpaas/vendor/sealos-images /cpaas/vendor/sealos-images
COPY --chmod=755 build/oci-to-registry.bash /usr/local/bin/oci-to-registry.bash

RUN oci-to-registry.bash /registry \
    /cpaas/vendor/kubernetes-images \
    /cpaas/vendor/sealos-images

FROM scratch

ARG INST_KUBERNETES_V=v1.33.13
ARG INST_SEALOS_V=v5.1.2

COPY --from=kubernetes \
    /cpaas/vendor/kubernetes/kubeadm \
    /cpaas/vendor/kubernetes/kubectl \
    /cpaas/vendor/kubernetes/kubelet \
    bin/

COPY --from=kubernetes \
    /cpaas/vendor/kubernetes/DefaultImageList \
    /images/shim/DefaultImageList

COPY --from=registry /registry/ registry/

COPY --from=oras \
    /cpaas/vendor/oras/oras \
    bin/

COPY --from=containerd \
    /cpaas/vendor/containerd/containerd \
    /cpaas/vendor/containerd/containerd-shim-runc-v2 \
    /cpaas/vendor/containerd/containerd-stress \
    /cpaas/vendor/containerd/ctr \
    bin/

COPY --from=runc \
    /cpaas/vendor/runc/runc \
    bin/

COPY --from=crun \
    /cpaas/vendor/crun/crun \
    bin/

COPY --from=distribution \
    /cpaas/vendor/registry/registry \
    bin/

COPY --from=sealos \
    /cpaas/vendor/sealos/image-cri-shim \
    bin/

# sealos runs <rootfs>/opt/sealctl on every node (cri socket / cgroup driver
# detection, hosts, certs, static pods); it must match the sealos version.
COPY --from=sealos \
    /cpaas/vendor/sealos/sealctl \
    opt/

COPY --from=cri-tools \
    /cpaas/vendor/cri-tools/crictl \
    bin/

ENV \
    defaultVIP=10.103.97.2 \
    sandboxImage=pause:3.10

ENV \
    criData=/var/lib/containerd \
    \
    registryData=/var/lib/registry \
    registryConfig=/etc/registry \
    registryDomain=sealos.hub \
    registryPort=5000 \
    registryUsername=admin \
    registryPassword=passw0rd \
    \
    disableApparmor=false \
    \
    SEALOS_SYS_CRI_ENDPOINT=/var/run/containerd/containerd.sock \
    SEALOS_SYS_IMAGE_ENDPOINT=/var/run/image-cri-shim.sock

LABEL \
    sealos.io.type=rootfs \
    sealos.io.version=v1beta1 \
    version=${INST_KUBERNETES_V} \
    image=ghcr.io/labring/lvscare:${INST_SEALOS_V}

LABEL \
    init="init-cri.bash \$registryDomain \$registryPort && bash init.bash" \
    clean="clean.bash && bash clean-cri.bash \$criData" \
    check="check.bash \$registryData" \
    init-registry="init-registry.bash \$registryData \$registryConfig" \
    clean-registry="clean-registry.bash \$registryData \$registryConfig" \
    vip="\$defaultVIP"

COPY etc etc/
COPY scripts scripts/
# sealos copies statics/audit-policy.yml to /etc/kubernetes/ on masters
COPY statics statics/

LABEL \
    org.opencontainers.image.title="sealos-cluster-image" \
    org.opencontainers.image.description="Sealos rootfs cluster image for offline Kubernetes deployment, assembled from kluster-vendor images" \
    org.opencontainers.image.version="${INST_KUBERNETES_V}" \
    org.opencontainers.image.source="https://github.com/cpaas-dev/sealos-cluster-image" \
    org.opencontainers.image.vendor="Kluster" \
    org.opencontainers.image.licenses="Apache-2.0"
