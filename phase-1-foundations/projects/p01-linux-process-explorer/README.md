# P01 — Linux Process & Namespace Explorer

## What this project builds
A diagnostic shell script that inspects any running process —
its identity, namespace isolation, cgroup limits, open file
descriptors, network connections, and signal handling status.

This is the mental model you use when debugging a Kubernetes pod.
In production you would combine this with kubectl describe, kubectl
logs, and kubectl exec. The underlying data is identical.

## Status
- [x] Complete

## Concepts covered
| Concept | Where used |
|---------|-----------|
| PIDs and process tree | Section 1 — Process Identity |
| Signal handling | Section 6 — Signal Handling |
| /proc filesystem | All sections |
| Filesystem and inodes | FD inspection via /proc/<pid>/fd |
| Users and permissions | UID check and root warning |
| Networking | Section 5 — Network Connections |
| cgroups | Section 3 — Resource Limits |
| Namespaces | Section 2 — Namespace Isolation |

## Project structure
## Usage
```bash
# Basic inspection
sudo ./scripts/process-explorer.sh <PID>

# Watch mode (refreshes every 3 seconds)
sudo ./scripts/process-explorer.sh <PID> --watch

# Inspect a Docker container
CPID=$(docker inspect <name> --format '{{.State.Pid}}')
sudo ./scripts/process-explorer.sh $CPID

# Inspect yourself
sudo ./scripts/process-explorer.sh $$
```

## Key things the output tells you

### Namespace section
All namespaces SHARED → plain host process
All namespaces ISOLATED → containerised process
Mix of shared/isolated → partially isolated (uncommon)

### cgroup section
memory.max = max → no memory limit set
memory.current near memory.max → OOMKill risk
throttled_usec rising → CPU limit too low

### Signal handling section
SIGTERM HANDLED → graceful shutdown possible
SIGTERM NOT handled → will die mid-request on kubectl delete pod
SIGHUP HANDLED → supports config reload without restart

## What this maps to in Kubernetes
| This script shows | kubectl equivalent |
|-------------------|--------------------|
| Namespace isolation | kubectl get pod -o yaml (hostNetwork etc) |
| cgroup memory.current | kubectl top pod |
| cgroup memory.max | resources.limits.memory |
| cgroup cpu.max | resources.limits.cpu |
| SIGTERM handled? | Pod graceful shutdown behaviour |
| Network connections | kubectl exec -- ss -tnp |

## Git workflow
```bash
git add .
git commit -m "p01: description of what you changed"
git push origin main
```
