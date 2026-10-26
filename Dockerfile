# syntax=docker.io/docker/dockerfile:1.25.0

ARG BASE_IMAGE=docker.io/rockylinux/rockylinux:10.2.20260525.0

ARG INST_KUBERNETES_V=v1.33.13
ARG INST_CONTAINERD_V=v2.3.4
ARG INST_CRUN_V=v1.29.1
ARG INST_ZOT_V=v2.1.20
ARG INST_SEALOS_V=v5.1.1
ARG INST_CRI_TOOLS_V=v1.36.0

FROM ghcr.io/cpaas-dev/kluster-vendor-kubernetes:${INST_KUBERNETES_V} AS kubernetes
FROM ghcr.io/cpaas-dev/kluster-vendor-containerd:${INST_CONTAINERD_V} AS containerd
FROM ghcr.io/cpaas-dev/kluster-vendor-crun:${INST_CRUN_V} AS crun
FROM ghcr.io/cpaas-dev/kluster-vendor-zot:${INST_CRUN_V} AS zot
FROM ghcr.io/cpaas-dev/kluster-vendor-sealos:${INST_SEALOS_V} AS sealos
FROM ghcr.io/cpaas-dev/kluster-vendor-cri-tools:${INST_SEALOS_V} AS cri-tools

FROM ${BASE_IMAGE}

RUN mkdir -p /cpaas /images /registry
COPY scripts /cpaas/scripts

ARG INST_KUBERNETES_V=v1.33.13
ARG INST_SEALOS_V=v5.1.1

COPY --from=kubernetes \
    /cpaas/vendor/kubernetes/kubeadm \
    /cpaas/vendor/kubernetes/kubectl \
    /cpaas/vendor/kubernetes/kubelet \
    /cpaas/bin/

COPY --from=kubernetes \
    /cpaas/vendor/kubernetes/DefaultImageList \
    /images/shim/DefaultImageList

COPY --from=kubernetes \
    /cpaas/vendor/kubernetes-images/* \
    /registry/

COPY --from=containerd \
    /cpaas/vendor/containerd/containerd \
    /cpaas/vendor/containerd/containerd-shim-runc-v2 \
    /cpaas/vendor/containerd/containerd-stress \
    /cpaas/vendor/containerd/ctr \
    /cpaas/bin/

COPY --from=crun \
    /cpaas/vendor/crun/crun \
    /cpaas/bin/

COPY --from=zot \
    /cpaas/vendor/zot/zot \
    /cpaas/vendor/zot/zli \
    /cpaas/bin/

COPY --from=sealos \
    /cpaas/vendor/sealos/image-cri-shim \
    /cpaas/bin/

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

COPY . .
