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
