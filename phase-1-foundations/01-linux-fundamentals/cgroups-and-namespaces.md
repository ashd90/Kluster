# cgroups & Namespaces

## The one-line summary
A container = a process running in isolated namespaces
with cgroup resource limits applied.
No separate kernel. No virtualisation. Just Linux features.

## Namespaces

Namespaces make a process believe it has its own isolated
instance of a global system resource.

### The 7 namespace types
| Namespace | Isolates | Kubernetes use |
|-----------|---------|----------------|
| PID | Process IDs | App is PID 1 inside container |
| Network | Interfaces, IPs, routing | Each pod gets own IP |
| Mount | Filesystem mount points | Container has own filesystem |
| UTS | Hostname, domain name | Pod hostname = pod name |
| IPC | Shared memory, semaphores | Inter-process communication |
| User | UIDs and GIDs | UID 0 in container ≠ host root |
| Cgroup | cgroup root directory | Container sees own cgroup tree |

### Key namespace facts
- Namespaces are identified by inode numbers in /proc/<pid>/ns/
- Same inode = same namespace = shared resource
- Different inode = different namespace = isolated
- `nsenter` enters a namespace without being in that container
- `unshare` creates new namespaces for current process
- Kubernetes pods share net+ipc namespaces between containers
- kubectl exec uses nsenter internally

## cgroups (Control Groups)

cgroups limit, prioritise, and account for resource usage
per process group. The kernel enforces limits — no escape.

### cgroup v2 subsystems
| Subsystem | Controls |
|-----------|---------|
| cpu | CPU time, throttling |
| memory | RAM — OOMKill if exceeded |
| io | Disk bandwidth |
| pids | Max process count |
| cpuset | Which CPU cores |
| devices | Device access |

### Kubernetes resource limits → cgroup mappings
```yaml
resources:
  requests:
    memory: "128Mi"   # scheduler hint — not a cgroup limit
    cpu: "250m"       # 0.25 core — scheduler hint
  limits:
    memory: "256Mi"   # cgroup memory.max = 268435456 bytes
    cpu: "500m"       # cgroup cpu.max = 50000 100000
```

### CPU units
- 1000m = 1 full CPU core
- 500m = 0.5 core
- 250m = 0.25 core
- CPU limits throttle (slow down) — never kill
- CPU requests are for scheduling decisions only

### Memory behaviour
- Memory limits are HARD — exceed = OOMKill (exit code 137)
- OOMKill sends SIGKILL — no graceful shutdown
- kubectl describe pod shows: Reason: OOMKilled
- Memory requests are for scheduling decisions only

## Container = Namespaces + cgroups + OverlayFS
## Key commands
| Command | What it does |
|---------|-------------|
| `lsns` | List all namespaces on system |
| `ls /proc/<pid>/ns/` | See a process's namespaces |
| `nsenter -t <pid> --net -- cmd` | Run cmd in process's net namespace |
| `unshare --pid --fork bash` | Create new PID namespace |
| `cat /proc/<pid>/cgroup` | See process's cgroup path |
| `cat /sys/fs/cgroup/<path>/memory.max` | Read memory limit |
| `cat /sys/fs/cgroup/<path>/cpu.max` | Read CPU limit |
| `cat /sys/fs/cgroup/<path>/cpu.stat` | See CPU throttle stats |
| `docker stats <name> --no-stream` | See live resource usage |
| `docker inspect <name> \| grep OOM` | Check if OOMKilled |

## Linux → Kubernetes mapping

| Linux concept | Kubernetes equivalent |
|---------------|----------------------|
| PID namespace | Pod process isolation |
| Net namespace | Pod IP address |
| Mount namespace | Container filesystem |
| UTS namespace | Pod hostname |
| cgroup memory.max | resources.limits.memory |
| cgroup cpu.max | resources.limits.cpu |
| OOMKill | Pod status: OOMKilled |
| CPU throttle | Pod CPU limit enforcement |
| nsenter | kubectl exec |
| unshare | Container creation |
| /proc/<pid>/root | Container filesystem on host |

## Important production notes

- **OOMKill has no grace period**: Memory limit exceeded = immediate
  SIGKILL. No SIGTERM, no cleanup, no graceful shutdown.
  Set memory limits generously — monitor actual usage first with
  requests only, then add limits based on observed peak usage.

- **CPU throttling is invisible to the app**: A process being
  throttled by cgroups has no idea it's being slowed down.
  It just runs slower. This causes mysterious latency spikes.
  High cpu.stat throttled_usec = your CPU limit is too low.

- **Shared network namespace in pods**: All containers in a pod
  share one network namespace. They have the same IP. Port conflicts
  between containers in the same pod will cause startup failures.
  Plan port usage across all containers in a pod carefully.

- **User namespace support**: Kubernetes 1.30+ supports user
  namespaces (UID mapping). Before this, UID 0 in container = UID 0
  on host if container escapes. Always use runAsNonRoot: true.

- **nsenter for live debugging**: When kubectl exec fails (container
  has no shell, or the process has crashed), you can still debug
  by sshing to the node and using nsenter with the container's PID.
  This is a critical production debugging technique.

- **cgroup limits apply to ALL processes in container**: The memory
  limit covers every process in the container — your app, any
  background threads, child processes, everything. Account for
  all memory users when setting limits.

## Real-world production scenarios

### Scenario 1 — Pod keeps restarting, exit code 137
kubectl describe pod shows OOMKilled.
The memory limit is too low for the workload.
Diagnosis steps:
  1. Check current limit: kubectl get pod -o yaml | grep memory
  2. Check actual usage before the kill:
     kubectl top pod mypod  (if metrics-server installed)
  3. Check app logs before death for memory growth patterns
Fix: increase memory limit. As a rule of thumb, set limit to
2x the normal working memory, 3x if the app has occasional spikes.

### Scenario 2 — App is slow but CPU usage looks low
App responds sluggishly. kubectl top shows 200m CPU usage.
But the limit is 250m — seems fine?
Root cause: the app bursts to 500m+ briefly during request
processing. cgroups throttles these bursts. Average looks low
but p99 latency is terrible.
Diagnosis: check cpu.stat throttled_usec in the container's cgroup.
Fix: raise CPU limit or remove it entirely (use requests only)
if the node has spare capacity.

### Scenario 3 — kubectl exec works but no useful tools available
Container is running a distroless image — no shell, no ps, no curl.
You need to debug a network issue.
Fix: on the node, find the container PID:
  crictl inspect <container-id> | grep pid
Then use nsenter to enter its network namespace with host tools:
  nsenter -t <pid> --net -- ss -tlnp
  nsenter -t <pid> --net -- curl http://other-service
You're using host binaries inside the container's network namespace.
No shell required in the container.

## FAQ

**Q: If containers use the host kernel, what happens if the kernel
crashes?**
A: Every container on that node crashes with it. Containers share
the host kernel — there is no isolation at the kernel level.
This is the fundamental difference from VMs (which have their own
kernel). A kernel panic on a Kubernetes node takes down all pods
on that node simultaneously. This is why you run multiple nodes.

**Q: Can a container escape its namespace?**
A: With default settings, no. But if a container runs as root AND
has certain Linux capabilities (like CAP_SYS_ADMIN), it may be
able to manipulate namespaces. This is why dropping capabilities
and running as non-root in Kubernetes is critical security practice.

**Q: What is the difference between a container and a VM?**
A: VM = full hardware virtualisation + separate kernel.
Container = process isolation via namespaces + cgroups on SHARED kernel.
VMs are heavier (seconds to start, hundreds of MB overhead) but
provide stronger isolation. Containers are lighter (milliseconds
to start, MB overhead) but share the kernel.
In production, many teams run containers INSIDE VMs for both
speed and isolation.

**Q: What is a privileged container and why is it dangerous?**
A: docker run --privileged (or privileged: true in Kubernetes)
disables most namespace isolation. The container can see and
modify host devices, load kernel modules, and manipulate host
network interfaces. Essentially root on the host.
Never use in production unless absolutely required (e.g. some
storage CSI drivers need it). Always audit if you see it.

**Q: How does Kubernetes know when a container has used too much
memory before the OOMKill?**
A: The kernel's cgroup memory controller tracks usage continuously.
When usage reaches memory.max, the kernel OOM killer fires
immediately — there is no warning to Kubernetes first.
Kubernetes learns about it after the fact when the container
exits with code 137. This is why proactive memory monitoring
with kubectl top and Prometheus matters.

**Q: What is the pids cgroup subsystem used for in Kubernetes?**
A: It limits the total number of processes inside a container.
Kubernetes sets this to prevent fork bombs — a malicious or
buggy container that spawns processes infinitely, exhausting
the node's PID table and crashing all other containers.
Default Kubernetes limit is 1000 pids per container.
