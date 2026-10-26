## init-registry

```bash
registry-init.bash $registryData $registryConfig
```

## clean-registry

```bash
registry-clean.bash $registryData $registryConfig
```

## check

```bash
check.bash $registryData
```

## init

```bash
cri-init.bash $registryDomain $registryPort && bash init.bash
```

- cri-init.bash
  - image-cri-shim-init.bash
  - crun-init.bash
  - containerd-init.bash
- init.bash

## clean

```bash
clean.bash && bash cri-clean.bash $criData
```

- clean.bash
- cri-clean.bash
  - containerd-clean.bash
  - crun-clean.bash
  - image-cri-shim-clean.bash
