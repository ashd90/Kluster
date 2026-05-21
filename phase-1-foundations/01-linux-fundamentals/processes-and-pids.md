# Processes & PIDs

## What is a process?

A process is any running program. Every time you launch Firefox, open a
terminal, or run a script, Linux creates a process for it. The kernel
assigns each process a unique number called a PID (Process ID) to track
and manage it.

The kernel is the only entity that can create PID 1. Everything else is
started by an existing process. This creates a tree — every process has
a parent (PPID), and that parent has a parent, all the way up to PID 1.

---

## The process tree
On CachyOS (Arch), PID 1 is systemd.
Inside a container, PID 1 is YOUR APPLICATION.

---

## Process states

| State | Letter | Meaning | Production relevance |
|-------|--------|---------|----------------------|
| Running | R | Using CPU or in run queue | Normal |
| Sleeping | S | Waiting, interruptible | Normal — most processes here |
| Deep sleep | D | Waiting for I/O, uninterruptible | High D count = disk/NFS problem |
| Stopped | T | Paused by signal | Unusual in production |
| Zombie | Z | Done, parent not notified | Accumulation = PID exhaustion risk |

---

## Key commands

| Command | What it does |
|---------|-------------|
| `echo $$` | Current shell PID |
| `ps aux` | All processes, all users |
| `ps -p <pid> -o pid,ppid,cmd` | Specific process with parent |
| `pstree -p` | Visual process tree with PIDs |
| `pgrep <name>` | Find PID by process name |
| `kill <pid>` | Send SIGTERM to process |
| `kill -9 <pid>` | Send SIGKILL — immediate, no escape |
| `htop` | Interactive process viewer (press t for tree view) |

---

## Linux → Kubernetes mapping

| Linux concept | Kubernetes equivalent |
|---------------|----------------------|
| PID | Pod name + UID |
| Parent creates child via fork | Controller creates pods |
| PID 1 = root of everything | PID 1 inside container = your app |
| `ps aux` | `kubectl get pods -A` |
| `kill <pid>` | `kubectl delete pod <name>` |
| Process state (R/S/D/Z) | Pod phase (Running/Pending/Failed) |
| `pstree` hierarchy | kubectl owner references |

---

## Important production notes

- **Containers and PID 1**: Your application runs as PID 1 inside its
  container namespace. PID 1 has a special responsibility — it must
  reap zombie child processes. A regular init system (systemd) does this
  automatically. Your app may not. This causes zombie accumulation.

- **PID namespace isolation**: A process has different PIDs depending on
  which namespace you observe it from. Inside the container it is PID 1.
  On the host it might be PID 4821. Same process, different lens.

- **Re-parenting**: When a parent process dies before its child, the
  child is adopted by PID 1. In a container, if PID 1 (your app) dies,
  all child processes die too — there is no re-parenting escape.

- **PID exhaustion**: Linux has a max PID limit (check with
  `cat /proc/sys/kernel/pid_max`, default 32768). Zombie accumulation
  consumes PID slots. When full, no new processes can be created.
  Container hard-crashes. This is a real production outage cause.

- **`D` state processes**: A process stuck in uninterruptible sleep
  cannot be killed — not even with kill -9. This usually means it is
  waiting on a hung NFS mount or a failing disk. In Kubernetes, this
  manifests as a pod that refuses to terminate and stays in
  Terminating state indefinitely.

---

## Real-world production scenarios

### Scenario 1 — Pod stuck in Terminating forever
You run `kubectl delete pod mypod` and it never finishes.
Root cause: a process inside the container is in `D` state — waiting
on a hung network filesystem. SIGKILL cannot interrupt D state.
Fix: unmount the stuck filesystem, or force-delete the pod with
`kubectl delete pod mypod --force --grace-period=0` (use as last resort).

### Scenario 2 — Node runs out of PIDs
Monitoring alerts fire: "cannot fork: resource temporarily unavailable".
All pods on a node start failing to start new threads or processes.
Root cause: a long-running container with a broken PID 1 that never
reaps zombies has filled the PID table.
Fix: identify container with highest zombie count using
`ps aux | awk '$8=="Z"' | wc -l` inside the container.
Restart that pod. Long-term fix: add tini as PID 1 init process.

### Scenario 3 — Debugging a pod feels like a different machine
You `kubectl exec -it mypod -- bash` and run `ps aux`. You only see
processes inside the container — not the thousands on the host.
This is PID namespace isolation working correctly.
The container has its own PID tree starting at 1.

---

## FAQ

**Q: Why does my app need to be PID 1 in a container?**
A: Because Docker/Kubernetes runs your ENTRYPOINT directly as PID 1.
There is no init system inside a minimal container image. If your app
spawns child processes, it inherits PID 1's responsibility of reaping
zombies. Many apps are not written to do this.

**Q: What is tini and why do people use it?**
A: tini is a minimal init process (~300 lines of C) designed to be
PID 1 in containers. It does exactly two things: forwards signals to
your app, and reaps zombie child processes. Use it when your app spawns
children but doesn't handle SIGCHLD.
Example Dockerfile line: `ENTRYPOINT ["/tini", "--", "your-app"]`

**Q: Can I see all processes on the host from inside a container?**
A: Not by default — PID namespace isolation prevents this. You would
need to run the container with `--pid=host` (Docker) or
`hostPID: true` (Kubernetes pod spec). Both are serious security risks
and should never be used in production without very specific reason.

**Q: What does `ps aux` inside a container show?**
A: Only processes in that container's PID namespace. PID 1 will be
your app's entrypoint process. You will not see host processes.

**Q: I see a process with PPID 1 that I didn't expect. Is this bad?**
A: Not necessarily. It means either systemd started it directly, or
its original parent died and it was re-parented to PID 1.
Check the process name and start time to understand which case it is.
