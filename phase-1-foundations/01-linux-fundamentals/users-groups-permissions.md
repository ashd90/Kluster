# Users, Groups & Permissions

## Core concepts

Every process runs as a UID. Every file has an owner UID and GID.
The kernel checks UID/GID numerically — not by username string.
Usernames are human-readable labels. UIDs are what actually matter.

### Special UIDs
| UID | Name | Purpose |
|-----|------|---------|
| 0 | root | Superuser — bypasses all permission checks |
| 65534 | nobody | No-privilege user for daemons |
| 1000+ | regular users | Normal user accounts |

## Permission model

Every file has 9 permission bits in three groups:
### Permission bits
| Bit | Files | Directories |
|-----|-------|-------------|
| r | Read content | List contents |
| w | Write content | Create/delete inside |
| x | Execute | cd into directory |

### Octal notation
| Octal | Binary | Permissions |
|-------|--------|-------------|
| 7 | 111 | rwx |
| 6 | 110 | rw- |
| 5 | 101 | r-x |
| 4 | 100 | r-- |
| 0 | 000 | --- |

Common permission sets:
- 755 → rwxr-xr-x (executables, directories)
- 644 → rw-r--r-- (regular files)
- 600 → rw------- (private files, SSH keys)
- 640 → rw-r----- (group-readable private files)

## Key commands
| Command | What it does |
|---------|-------------|
| `id` | Show current UID, GID, and all groups |
| `whoami` | Show current username |
| `ls -la` | List with permissions and ownership |
| `stat <file>` | Full permission and ownership details |
| `chmod <mode> <file>` | Change permissions |
| `chown user:group <file>` | Change owner and group |
| `umask` | Show default permission mask |
| `usermod -aG <group> <user>` | Add user to group |
| `groups` | Show groups current user belongs to |

## Linux → Kubernetes mapping

| Linux concept | Kubernetes equivalent |
|---------------|----------------------|
| Process UID | Pod's runAsUser |
| File ownership | Volume file ownership |
| Group membership | Pod's runAsGroup / fsGroup |
| UID 0 = root = dangerous | runAsNonRoot: true |
| chmod 600 on secrets | Kubernetes Secret volume permissions |

## Important production notes

- **Default root in containers**: Most base images (ubuntu, debian,
  node, python) run as UID 0 by default. This is dangerous.
  If the container is compromised, the attacker has root on the
  container — and potentially on the host if other protections fail.
  Always specify a non-root USER in your Dockerfile.

- **UID consistency matters**: If container A writes files as UID 1000
  and container B (a new version) runs as UID 1001, container B cannot
  read container A's files. Always use consistent UIDs across versions
  of your application containers.

- **The docker group = root equivalent**: Being in the docker group
  allows a user to run containers with --privileged or mount host paths,
  which gives effective root access to the host. Treat docker group
  membership like sudo access.

- **fsGroup in Kubernetes**: When a pod mounts a PersistentVolume,
  the files may be owned by a UID that doesn't match the container's
  runAsUser. fsGroup tells Kubernetes to chown all volume files to
  a specific GID when the pod starts, ensuring the container can
  access its own persistent data.

- **ReadOnlyRootFilesystem**: Setting this to true in Kubernetes
  securityContext prevents the container from writing anywhere on
  its own filesystem. All writes must go to explicitly mounted volumes.
  This dramatically limits what an attacker can do if they get in.

## Real-world production scenarios

### Scenario 1 — Container works locally, permission denied in cluster
Dev runs container as root locally (default). In production cluster,
a PodSecurityPolicy (or Pod Security Admission) enforces runAsNonRoot.
Container starts as UID 1000 but tries to write to /app/logs which
was created as root during image build.
Fix: in Dockerfile, create directories and set ownership before
switching to non-root user:
  RUN mkdir -p /app/logs && chown -R 1000:1000 /app/logs
  USER 1000

### Scenario 2 — PersistentVolume data inaccessible after pod update
Old pod version ran as UID 999. New version runs as UID 1000.
All files on the PV are owned by 999. New pod gets permission denied.
Fix: add fsGroup to pod securityContext so Kubernetes adjusts
volume ownership on mount:
  securityContext:
    runAsUser: 1000
    fsGroup: 1000

### Scenario 3 — Security audit fails: containers running as root
Cluster security scan reports all pods running as UID 0.
Fix in stages:
  1. Add USER directive to all Dockerfiles
  2. Add runAsNonRoot: true to all pod specs
  3. Add runAsUser: <specific-uid> to remove ambiguity
  4. Test that application still works with reduced privileges

## FAQ

**Q: What happens if runAsUser is set to 0 in Kubernetes?**
A: The container runs as root. If runAsNonRoot is also set to true,
Kubernetes will reject the pod at admission — it refuses to start
a container that would violate the non-root requirement.

**Q: Can a container process change its own UID?**
A: Only if it is currently running as root (UID 0). Root can call
setuid() to drop privileges. Non-root processes cannot elevate
privileges (unless the setuid bit is set on the executable).
In containers, you should drop to non-root at startup, not mid-run.

**Q: What is the difference between USER in Dockerfile and
runAsUser in Kubernetes?**
A: Dockerfile USER sets the default UID for the image.
Kubernetes runAsUser overrides it at runtime.
Kubernetes wins — it can force a different UID regardless of
what the Dockerfile specifies. Best practice: set both, and make
them consistent so behaviour is predictable.

**Q: Why does chmod not work on files in a Kubernetes volume?**
A: Depends on the volume type. Some volume types (NFS, certain CSI
drivers) don't support arbitrary permission changes. Also, if the
container is running as non-root, it can only chmod files it owns.
Use fsGroup and defaultMode (for ConfigMap/Secret volumes) instead
of trying to chmod at runtime.

**Q: What is defaultMode on a ConfigMap or Secret volume mount?**
A: It sets the file permissions (in octal) for files projected from
ConfigMaps or Secrets into the container. Default is 0644.
For files that will be used as SSH keys or TLS certs, set 0600:
  volumes:
  - name: my-secret
    secret:
      secretName: my-tls-cert
      defaultMode: 0600
