# What Containers Really Are

## The real definition
A container is an ordinary Linux process launched with:
- Isolated namespaces (what it can see)
- cgroup resource limits (how much it can use)
- OverlayFS filesystem (what files it sees)

Not a VM. Not magic. Just Linux features combined.

## The three pillars

### Pillar 1 — Namespaces (Isolation)
| Namespace | What container sees |
|-----------|-------------------|
| PID | Own process tree, app is PID 1 |
| Net | Own network interface and IP |
| Mnt | Own filesystem (OverlayFS) |
| UTS | Own hostname |
| IPC | Own shared memory |

### Pillar 2 — cgroups (Limits)
| Resource | How limited |
|----------|------------|
| Memory | memory.max — OOMKill if exceeded |
| CPU | cpu.max — throttled if exceeded |
| PIDs | pids.max — no new processes if exceeded |

### Pillar 3 — OverlayFS (Filesystem)
Read-only image layers + writable container layer.
Writes go to top layer — deleted when container removed.

## Container vs Image
| | Image | Container |
|-|-------|-----------|
| What | Read-only template | Running instance |
| Analogy | Class definition | Object instance |
| Mutable | No | Yes (writable layer) |
| Survives docker rm | Yes | Writable layer deleted |

## Container lifecycle
## Exit codes
| Code | Meaning | Kubernetes |
|------|---------|-----------|
| 0 | Clean exit | Completed |
| 1 | App error | Error |
| 137 | SIGKILL/OOMKill | OOMKilled |
| 143 | SIGTERM graceful | Completed |

## Docker flags → Kubernetes pod spec
| Docker flag | Kubernetes equivalent |
|-------------|----------------------|
| --memory | resources.limits.memory |
| --cpus | resources.limits.cpu |
| --user | securityContext.runAsUser |
| --read-only | securityContext.readOnlyRootFilesystem |
| --tmpfs | volumes.emptyDir.medium: Memory |

## Key commands
| Command | What it does |
|---------|-------------|
| `docker run -d` | Start container in background |
| `docker inspect <name>` | Full container details |
| `docker exec <name> cmd` | Run command inside container |
| `docker stop <name>` | Send SIGTERM, wait, SIGKILL |
| `docker kill <name>` | Send SIGKILL immediately |
| `docker rm <name>` | Delete container + writable layer |
| `docker system df` | Show disk usage |

## Important production notes

- **Privileged containers break all isolation** — never use
  privileged: true in production Kubernetes without strong reason.
  It gives the container root access to the host.

- **Stop ≠ Delete** — docker stop preserves the writable layer.
  docker rm destroys it. In Kubernetes, pod restarts recreate
  the container from scratch — writable layer is always lost.
  Use PersistentVolumes for data that must survive restarts.

- **Kubernetes removed Docker in 1.24** — Kubernetes now uses
  containerd + runc directly. Container images are identical —
  OCI format, same layers, same behaviour. Only the management
  layer changed.

- **One process per container** — the Docker/Kubernetes philosophy.
  Each container should run one main process as PID 1. Multiple
  processes in one container makes signal handling, logging, and
  resource limits much harder to manage correctly.

## FAQ

**Q: If containers share the host kernel, what isolates them?**
A: Namespaces isolate visibility. cgroups isolate resource usage.
The kernel itself enforces both. A container cannot see outside
its namespaces or exceed its cgroup limits without a kernel exploit.

**Q: Can two containers see each other's processes?**
A: Not by default — each has its own PID namespace. Exception:
containers in the same Kubernetes pod share a network namespace
but not PID namespace by default. You can enable shared PID
namespace with shareProcessNamespace: true in the pod spec.

**Q: Why does Kubernetes not use Docker anymore?**
A: Kubernetes needed a minimal container runtime interface (CRI).
Docker is a full developer tool — it includes build, push, pull,
compose, and more. Kubernetes only needs run/stop/inspect.
containerd provides exactly that, without Docker's overhead.
Your Docker-built images still work perfectly on Kubernetes.
