# Signals

## Key concepts
- Signals are messages from the kernel or other processes to a process
- Every signal has a default action (usually terminate or ignore)
- SIGKILL (9) and SIGSTOP (19) cannot be caught or ignored — ever
- `trap` in bash registers a custom handler for a signal

## The signals that matter
| Signal | Number | Catchable | Kubernetes use |
|--------|--------|-----------|----------------|
| SIGHUP | 1 | Yes | Config reload |
| SIGINT | 2 | Yes | Ctrl+C |
| SIGKILL | 9 | NO | Force kill after grace period |
| SIGTERM | 15 | Yes | kubectl delete pod |
| SIGCHLD | 17 | Yes | Child process finished |

## kubectl delete pod signal flow
1. Kubernetes sends SIGTERM to container PID 1
2. Waits terminationGracePeriodSeconds (default 30s)
3. If still running → sends SIGKILL

## Graceful shutdown pattern
```bash
trap 'cleanup_function' SIGTERM
# Do work in a loop
# cleanup_function sets a flag to exit the loop
```

## Zombie processes
- Finished process whose parent never called wait()
- Shows as STAT = Z in ps aux
- Harmless in small numbers, dangerous if accumulating
- Solution: handle SIGCHLD and call wait() in parent
