# Processes & PIDs

## Key concepts
- Every running program is a process with a unique PID
- Every process (except PID 1) has a parent — forming a tree
- PID 1 is systemd on CachyOS — the root of all processes
- Inside a container, your app becomes PID 1 (in its own PID namespace)

## Process states
| State | Letter | Meaning |
|-------|--------|---------|
| Running | R | Using CPU |
| Sleeping | S | Waiting, interruptible |
| Deep sleep | D | Waiting for I/O, uninterruptible |
| Stopped | T | Paused |
| Zombie | Z | Done, parent not notified |

## Key commands
| Command | What it does |
|---------|-------------|
| `echo $$` | Show current shell PID |
| `ps aux` | Show all processes |
| `ps -p <pid> -o pid,ppid,cmd` | Show specific process with parent |
| `pstree -p` | Show process tree with PIDs |
| `pgrep <name>` | Find PID by process name |
| `kill <pid>` | Send SIGTERM to process |
| `htop` | Interactive process viewer |

## Kubernetes connection
- Container's PID 1 = your app (not systemd)
- `kubectl delete pod` sends SIGTERM, then SIGKILL (like kill then kill -9)
- Pod phases map to Linux process states
