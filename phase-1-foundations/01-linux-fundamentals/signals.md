# Signals

## What are signals?

Signals are software interrupts — small messages the kernel delivers to
a process to notify it that something happened. A process can register
a handler function for most signals. Two signals (SIGKILL and SIGSTOP)
bypass the process entirely and are handled directly by the kernel.

---

## The signals that matter

| Signal | Number | Catchable | Default action | When you see it |
|--------|--------|-----------|----------------|-----------------|
| SIGHUP | 1 | Yes | Terminate | Terminal closes / config reload |
| SIGINT | 2 | Yes | Terminate | Ctrl+C |
| SIGQUIT | 3 | Yes | Core dump | Ctrl+\ |
| SIGKILL | 9 | **NO** | Terminate | Force kill — no escape |
| SIGTERM | 15 | Yes | Terminate | Polite shutdown request |
| SIGCHLD | 17 | Yes | Ignore | Child process finished |
| SIGSTOP | 19 | **NO** | Stop | Pause process |

---

## How Kubernetes uses signals

### kubectl delete pod — the full sequence
### What terminationGracePeriodSeconds means
This is set per pod in the spec:
```yaml
spec:
  terminationGracePeriodSeconds: 60   # give app 60s to clean up
  containers:
    - name: myapp
```
Default is 30 seconds. For databases or apps with long transactions,
increase this to give enough time for clean shutdown.

---

## The graceful shutdown pattern

A well-behaved Kubernetes application does this on SIGTERM:
1. Stops accepting new incoming requests
2. Finishes processing requests already in progress
3. Closes database connections cleanly
4. Flushes any pending writes
5. Exits with code 0

In bash (used for scripts and entrypoints):
```bash
KEEP_RUNNING=true

handle_sigterm() {
    echo "Shutting down gracefully..."
    # cleanup steps here
    KEEP_RUNNING=false
}

trap 'handle_sigterm' SIGTERM

while $KEEP_RUNNING; do
    # do work
    sleep 5 &
    wait $!    # sleep in background + wait = signal-receptive
done
```

The `sleep 5 & wait $!` pattern is critical.
Plain `sleep 5` freezes bash inside the child — signals queue but
don't fire until sleep finishes.
`sleep 5 & wait $!` keeps bash in a waiting state that is fully
receptive to signals. Signal fires immediately.

---

## Zombie processes

A zombie is a process that has finished executing but whose parent
has not yet called wait() to collect its exit status. The process
is dead — it uses no CPU or memory — but it holds a PID slot in
the kernel's process table.

### Why zombies are dangerous in containers
- PID slots are finite (default max: 32768 on Linux)
- Each zombie permanently holds one slot
- When the table fills: no new processes can be created
- Container cannot spawn threads, workers, or any subprocess
- Hard crash follows

### How to detect zombies
```bash
# Count zombies on host
ps aux | awk '$8=="Z"' | wc -l

# Count zombies inside a running container
kubectl exec mypod -- ps aux | grep ' Z '

# See zombie's parent (to identify the broken process)
ps -p <zombie_pid> -o ppid=
```

### Fix: handle SIGCHLD in PID 1
```bash
trap 'wait -n 2>/dev/null' SIGCHLD
```

### Fix: use tini as PID 1
```dockerfile
FROM node:20
RUN apt-get install -y tini
ENTRYPOINT ["/usr/bin/tini", "--", "node", "server.js"]
```
tini handles both signal forwarding and zombie reaping automatically.

---

## Important production notes

- **SIGKILL cannot be caught** — ever. If your app does not exit within
  terminationGracePeriodSeconds, Kubernetes will SIGKILL it. Data loss
  and corruption are possible. Always handle SIGTERM.

- **SIGTERM is not SIGKILL** — many developers assume `kill` kills
  immediately. It doesn't. `kill` sends SIGTERM — a polite request.
  The process can handle it, delay it, or (wrongly) ignore it.
  Only `kill -9` is truly immediate.

- **Containers without signal handling cause deployment outages** —
  every rolling update deletes old pods. If those pods don't handle
  SIGTERM, in-flight requests fail during every deployment.
  This is one of the most common causes of "deploys cause brief errors".

- **SIGHUP as reload signal** — many production daemons (nginx, sshd,
  prometheus) use SIGHUP to reload their configuration without
  restarting. In Kubernetes, you can send signals to containers with:
  `kubectl exec mypod -- kill -HUP 1`

- **Bash trap and subshells** — trap handlers registered in a parent
  bash script do NOT propagate to subshells. Each subshell needs its
  own trap. This is a common bug in complex entrypoint scripts.

---

## Real-world production scenarios

### Scenario 1 — Rolling deployment causes 502 errors
Every time you deploy a new version, users see brief 502 errors.
Root cause: old pods receive SIGTERM but the app has no handler.
The pod dies mid-request. Load balancer hasn't removed it from
rotation yet. In-flight requests fail.
Fix: add SIGTERM handler that waits for in-flight requests to complete
before exiting. In most frameworks this is called "graceful shutdown".
Examples: `server.close()` in Node.js, `server.shutdown()` in Python.

### Scenario 2 — Pod stuck in Terminating for hours
`kubectl delete pod mypod` runs but the pod stays in Terminating state.
Root cause: PID 1 inside the container is ignoring SIGTERM. After 30s
grace period, Kubernetes sends SIGKILL. But if the process is in D
state (waiting on hung I/O), even SIGKILL won't work.
Fix: `kubectl delete pod mypod --force --grace-period=0`
This removes the pod object from etcd. The container may still linger
on the node until the I/O resolves or the node is restarted.

### Scenario 3 — Container works fine locally but crashes in production
Locally you run the app directly. In production it runs in a container.
Root cause: locally, your shell (bash/zsh) is PID 1 and handles
signals for you. In the container, your app is PID 1 and must
handle signals itself. `docker run myapp` puts your process at PID 1
with no signal forwarding from any parent.
Fix: add signal handling to your app, or use tini.

### Scenario 4 — Kubernetes ignores terminationGracePeriodSeconds
You set grace period to 120s but pods are killed in 30s.
Root cause: `kubectl delete` has its own `--grace-period` flag which
overrides the pod spec value. Check if your CI/CD pipeline is running
`kubectl delete pod --grace-period=30` explicitly.
Fix: remove the flag from the pipeline command and let the pod spec
value be respected.

---

## FAQ

**Q: What happens if I send SIGTERM to PID 1 inside a container?**
A: If your app handles SIGTERM — graceful shutdown begins.
If your app ignores SIGTERM — nothing happens until grace period
expires and Kubernetes sends SIGKILL.
If your app forwards SIGTERM to child processes — they shut down too.

**Q: Can I change the grace period without redeploying?**
A: Not at runtime. terminationGracePeriodSeconds is part of the pod
spec and is immutable once the pod is running. You must update the
Deployment manifest and roll out a new version.

**Q: What is the difference between SIGTERM and SIGINT?**
A: Semantically, SIGTERM means "please terminate" (from another process
or the kernel). SIGINT means "interrupted by user" (Ctrl+C from the
terminal). In practice they often trigger the same cleanup behavior,
but conventionally SIGTERM is what you handle for graceful shutdown
in production and SIGINT is for developer/interactive use.

**Q: Why does `kill -9` sometimes not work?**
A: Two reasons. First, the process might be in D state (uninterruptible
sleep waiting for I/O) — the kernel will not deliver any signal,
including SIGKILL, until the I/O resolves. Second, on some systems
there can be a brief delay between sending SIGKILL and the kernel
actually scheduling the reaping. Usually it's nearly instant.

**Q: What exit code should a gracefully-shutdown app return?**
A: Exit code 0 means success/normal termination. If your app exits
due to SIGTERM, returning 0 tells Kubernetes the shutdown was clean.
Kubernetes treats exit code 0 as a successfully terminated container.
Non-zero codes indicate errors and may trigger restartPolicy actions.

**Q: How do I test that my app handles SIGTERM correctly?**
A: Run it locally, send SIGTERM, and verify:
1. The process exits within your expected grace period
2. No in-flight requests are dropped (use a load testing tool)
3. Database connections are closed cleanly (check DB connection logs)
4. Exit code is 0
In Kubernetes: watch pod logs during `kubectl delete pod` and confirm
you see your shutdown log messages before the pod disappears.
