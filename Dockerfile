# syntax=docker.io/docker/dockerfile:1.25.0

ARG BASE_IMAGE=docker.io/rockylinux/rockylinux:10.2.20260525.0

ARG INST_KUBERNETES_V=v1.37.1
ARG INST_CONTAINERD_V=v2.3.4
ARG INST_CRUN_V=v1.29.1
ARG INST_ZOT_V=v2.1.20
ARG INST_SEALOS_V=v5.1.1
ARG INST_CRI_TOOLS_V=v1.36.0
ARG INST_CILIUM_V=1.20.4

FROM ghcr.io/cpaas-dev/kluster-vendor-kubernetes:${INST_KUBERNETES_V} AS kubernetes
FROM ghcr.io/cpaas-dev/kluster-vendor-containerd:${INST_CONTAINERD_V} AS containerd
FROM ghcr.io/cpaas-dev/kluster-vendor-crun:${INST_CRUN_V} AS crun
FROM ghcr.io/cpaas-dev/kluster-vendor-zot:${INST_ZOT_V} AS zot
FROM ghcr.io/cpaas-dev/kluster-vendor-sealos:${INST_SEALOS_V} AS sealos
FROM ghcr.io/cpaas-dev/kluster-vendor-cri-tools:${INST_CRI_TOOLS_V} AS cri-tools

FROM docker.io/alpine/helm:3.19.0 AS helm
FROM quay.io/skopeo/stable:v1.21.0 AS addons
ARG TARGETARCH
ARG INST_CILIUM_V
COPY --from=helm /usr/bin/helm /usr/local/bin/helm
COPY cilium/values.yaml /build/cilium-values.yaml
COPY images/shim/AddonImageList /build/AddonImageList
RUN curl --fail --location --retry 3 \
      "https://helm.cilium.io/cilium-${INST_CILIUM_V}.tgz" -o /build/cilium.tgz \
    && echo '505abff8385811df1a949776fc42e9f10697989a332acc86d6e8933efcb855ed  /build/cilium.tgz' | sha256sum -c - \
    && mkdir -p /manifests /charts \
    && cp /build/cilium.tgz /charts/ \
    && helm template cilium /build/cilium.tgz --namespace kube-system \
         --kube-version 1.37.1 --include-crds --values /build/cilium-values.yaml \
         > /manifests/cilium.yaml
RUN mkdir -p /registry && while read -r image; do \
      repo_tag="${image#*/}"; repo="${repo_tag%:*}"; tag="${repo_tag##*:}"; \
      mkdir -p "/registry/${repo}"; \
      skopeo copy --retry-times 3 --override-os linux --override-arch "${TARGETARCH}" \
        "docker://${image}" "oci:/registry/${repo}:${tag}" || exit 1; \
    done < /build/AddonImageList

FROM ${BASE_IMAGE}

RUN mkdir -p /bin /etc /images/shim /registry /scripts
COPY scripts /scripts
COPY kubernetes/bin/kubelet-*.sh /scripts/
COPY cri-tools/crictl.yaml /etc/crictl.yaml
COPY etc /etc

ARG INST_KUBERNETES_V=v1.37.1
ARG INST_SEALOS_V=v5.1.1

COPY --from=kubernetes \
    /cpaas/vendor/kubernetes/kubeadm \
    /cpaas/vendor/kubernetes/kubectl \
    /cpaas/vendor/kubernetes/kubelet \
    /bin/

COPY --from=cri-tools \
    /cpaas/vendor/cri-tools/crictl \
    /bin/

COPY --from=kubernetes \
    /cpaas/vendor/kubernetes/DefaultImageList \
    /images/shim/DefaultImageList

COPY --from=kubernetes /cpaas/vendor/kubernetes-images/etcd /registry/etcd
COPY --from=kubernetes /cpaas/vendor/kubernetes-images/kube-apiserver /registry/kube-apiserver
COPY --from=kubernetes /cpaas/vendor/kubernetes-images/kube-controller-manager /registry/kube-controller-manager
COPY --from=kubernetes /cpaas/vendor/kubernetes-images/kube-scheduler /registry/kube-scheduler
COPY --from=kubernetes /cpaas/vendor/kubernetes-images/pause /registry/pause
COPY --from=addons /registry/ /registry/
COPY --from=addons /manifests/ /manifests/
COPY --from=addons /charts/ /charts/
COPY cilium/values.yaml /charts/cilium-values.yaml
COPY deploy /deploy
COPY images/shim/AddonImageList /images/shim/AddonImageList
RUN awk '!seen[$0]++' /images/shim/DefaultImageList /images/shim/AddonImageList > /tmp/DefaultImageList \
    && mv /tmp/DefaultImageList /images/shim/DefaultImageList

COPY --from=containerd \
    /cpaas/vendor/containerd/containerd \
    /cpaas/vendor/containerd/containerd-shim-runc-v2 \
    /cpaas/vendor/containerd/containerd-stress \
    /cpaas/vendor/containerd/ctr \
    /bin/

COPY --from=crun \
    /cpaas/vendor/crun/crun \
    /bin/

COPY --from=zot \
    /cpaas/vendor/zot/zot \
    /cpaas/vendor/zot/zli \
    /bin/

COPY --from=sealos \
    /cpaas/vendor/sealos/image-cri-shim \
    /bin/

RUN bash /scripts/verify-image.bash

ENV \
    defaultVIP=10.103.97.2 \
    sandboxImage=pause:3.10.2

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
    init="bash cri-init.bash \$registryDomain \$registryPort && bash init.bash" \
    clean="bash clean.bash && bash cri-clean.bash \$criData" \
    check="bash check.bash \$registryData" \
    init-registry="bash registry-init.bash \$registryData \$registryConfig" \
    clean-registry="bash registry-clean.bash \$registryData \$registryConfig" \
    vip="\$defaultVIP"
