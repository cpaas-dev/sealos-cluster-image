Top-level scripts are the sealos entrypoints referenced by the `LABEL`s in the
`Dockerfile`; sealos runs them with this directory as the working directory.
Each component keeps its `init.bash` / `clean.bash` under `<component>/`, and its
config files under `../etc/<component>/`; `common.bash` holds shared helpers.
The repository layout mirrors the final rootfs layout.
Exceptions are paths sealos reads itself: `../etc/registry.yml` (registry
domain/port/auth/data), `../statics/audit-policy.yml`, `../opt/sealctl`, and
`../registry/`, which the Dockerfile fills via `../build/oci-to-registry.bash`.

## init-registry

```bash
init-registry.bash $registryData $registryConfig
```

- registry/init.bash

## clean-registry

```bash
clean-registry.bash $registryData $registryConfig
```

- registry/clean.bash

## check

```bash
check.bash $registryData
```

## init

```bash
init-cri.bash $registryDomain $registryPort && bash init.bash
```

- init-cri.bash
  - cri-tools/init.bash
  - image-cri-shim/init.bash
  - crun/init.bash
  - runc/init.bash
  - containerd/init.bash
- init.bash
  - kubernetes/init.bash
  - oras/init.bash

## clean

```bash
clean.bash && bash clean-cri.bash $criData
```

- clean.bash
  - oras/clean.bash
  - kubernetes/clean.bash
- clean-cri.bash
  - containerd/clean.bash (also removes crun, runc, crictl)
  - image-cri-shim/clean.bash
