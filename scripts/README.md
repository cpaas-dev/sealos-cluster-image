## init-registry

```bash
registry-init.bash $registryData $registryConfig
```

Installs and starts the local Zot OCI registry on port 5000.

## clean-registry

```bash
registry-clean.bash $registryData $registryConfig
```

## check

```bash
check.bash $registryData
```

Checks host ports, CRI cleanup state, registry storage, and AppArmor support.

## init

```bash
cri-init.bash $registryDomain $registryPort && bash init.bash
```

- cri-init.bash
  - image-cri-shim-init.bash
  - crun-init.bash
  - containerd-init.bash
- init.bash

The CRI sequence installs the image shim, selects crun when available, and
starts containerd before kubelet is enabled.

When `SEALOS_ISOLATED_CRI=true` is set in the Clusterfile, `cri-init.bash`
instead runs `isolated-init.bash`. It installs the image binaries under
`/opt/sealos-v137/bin`, starts `containerd-v137` and `image-cri-shim-v137`, and
configures kubelet for `/run/containerd-v137/containerd.sock`. In this mode,
`init.bash` does nothing; the shared Docker containerd is left in place.

## clean

```bash
clean.bash && bash cri-clean.bash $criData
```

- clean.bash
- cri-clean.bash
  - containerd-clean.bash
  - image-cri-shim-clean.bash

The cleanup sequence stops kubelet and containerd and removes the CRI runtime
files and services.

With `SEALOS_ISOLATED_CRI=true`, `clean.bash` runs `isolated-clean.bash` and
`cri-clean.bash` does nothing. That cleanup stops the v1.37 kubelet, shim and
dedicated containerd, then removes their configuration and data. It does not
clean Docker's shared `containerd.service` or `/var/lib/containerd`. This is
destructive to the v1.37 cluster; see the root [README](../README.md) before
running Sealos reset. Never reset the old `default` cluster record.
