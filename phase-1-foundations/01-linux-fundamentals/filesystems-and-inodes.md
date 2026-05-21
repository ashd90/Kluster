# Filesystems & Inodes

## What is a filesystem?
A filesystem is the organisation system for data on disk. It defines
how data is stored, retrieved, and organised. Linux supports many
filesystem types: ext4, xfs, btrfs, tmpfs, overlayfs, and more.

## What is an inode?
Every file and directory has exactly one inode. An inode stores all
metadata about a file EXCEPT its name.

### Inode contents
| Field | Description |
|-------|-------------|
| Inode number | Unique ID within the filesystem |
| File type | Regular, directory, symlink, etc |
| Owner UID/GID | User and group ownership |
| Permissions | rwx bits for owner, group, others |
| Size | File size in bytes |
| Timestamps | atime, mtime, ctime |
| Link count | Number of directory entries pointing here |
| Data block pointers | Where actual content lives on disk |

### What is NOT in an inode
The filename. Filenames live in directories, not inodes.
A directory is a table mapping filenames → inode numbers.

## Hard links vs symlinks

| | Hard link | Symlink |
|-|-----------|---------|
| Same inode | Yes | No (own inode) |
| Cross filesystem | No | Yes |
| Original deleted | Data survives | Link breaks |
| `ls` type | Same as file | l |

Create hard link: `ln source destination`
Create symlink:   `ln -s source destination`

## Key commands
| Command | What it does |
|---------|-------------|
| `ls -li` | List with inode numbers |
| `stat <file>` | Full inode details |
| `df -i` | Inode usage per filesystem |
| `ln` | Create hard link |
| `ln -s` | Create symlink |
| `mount \| grep overlay` | See OverlayFS mounts |

## OverlayFS — Docker and container filesystems

OverlayFS stacks multiple directories into a single unified view.

### Mount options
- `lowerdir` — read-only image layers (colon-separated, bottom to top)
- `upperdir` — writable container layer (all writes go here)
- `workdir` — OverlayFS internal scratch space
- `merged` — unified view the container sees

### How Docker uses OverlayFS
### Why containers are ephemeral
All writes go to the writable upper layer.
When container is deleted, upper layer is deleted.
Image layers remain untouched.
This is why Kubernetes PersistentVolumes exist.

## Linux → Kubernetes mapping

| Linux concept | Kubernetes equivalent |
|---------------|----------------------|
| OverlayFS layers | Container image layers |
| Writable upper layer | Container ephemeral storage |
| Inode link count = 0 → delete | Pod deleted → writable layer removed |
| PersistentVolume | A mount that bypasses the upper layer |
| Running out of inodes | Pod fails to create files even with free disk |

## Important production notes

- **Inode exhaustion**: You can run out of inodes before running out of
  disk space. Millions of tiny files (node_modules, pip cache, logs)
  consume inodes fast. Monitor with `df -i`. Symptom: "No space left
  on device" error even though `df -h` shows free space.

- **Container writes are ephemeral**: Any file written inside a
  container is lost when the container restarts. Always use
  PersistentVolumeClaims for data that must survive restarts.

- **Image layer caching**: Docker caches each layer by its content
  hash. Layers are shared across all containers using the same image.
  A 500MB base image used by 50 containers still only takes 500MB on
  disk. Plan your Dockerfiles to maximise layer reuse.

- **Large upper layers**: If a container writes gigabytes to its
  writable layer (logs, temp files), this consumes host disk space.
  Use volume mounts for high-write paths, not the container filesystem.

- **OverlayFS and databases**: Running a database with its data
  directory inside the container layer (not a volume) is dangerous —
  data is lost on restart AND OverlayFS has worse write performance
  than a direct volume mount. Always mount database data directories
  as PersistentVolumes.

## Real-world production scenarios

### Scenario 1 — Pod cannot write files despite free disk space
Error: "no space left on device" but `df -h` shows 40% free.
Root cause: inode exhaustion. The filesystem has no free inode slots.
Diagnosis: `df -i` on the node — look for 100% IUse%.
Fix: find the directory with millions of small files using
`find / -xdev -printf '%h\n' | sort | uniq -c | sort -rn | head`
Delete or relocate those files. Long term: use a filesystem with
dynamic inode allocation (btrfs, xfs) instead of ext4.

### Scenario 2 — Container data lost after pod restart
Database pod restarts and all data is gone.
Root cause: database data directory was inside the container
filesystem (upper layer) not mounted as a PersistentVolume.
Fix: define a PersistentVolumeClaim and mount it at the database's
data directory path. All writes go to the persistent volume,
survive container restarts indefinitely.

### Scenario 3 — Docker image builds are slow, every layer re-downloads
Root cause: Dockerfile ordering puts frequently-changing lines
(app code) before rarely-changing lines (dependencies install).
Docker invalidates the cache at the first changed line and rebuilds
everything after it.
Fix: order Dockerfile layers from least-changed to most-changed:
  1. Base OS
  2. System packages
  3. Dependency files (package.json, requirements.txt)
  4. Install dependencies (this layer gets cached)
  5. Copy app code (changes every build but only this layer rebuilds)

## FAQ

**Q: Why does `rm` not always free disk space immediately?**
A: rm removes the directory entry (the filename → inode mapping) and
decrements the inode link count. The data blocks are only freed when
link count reaches 0 AND no process has the file open. If a running
process has the file open, the inode stays alive until that process
closes it. This is why deleting a large log file while a process is
writing to it doesn't free space until the process is restarted.
In Kubernetes: restart the pod or use `truncate -s 0 /path/to/file`
to zero out the file without deleting it.

**Q: How do I see how much space a container's writable layer is using?**
A: `docker ps -s` shows the size column: "X MB (virtual Y MB)".
X = writable layer size. Y = total including image layers.
For Kubernetes pods: exec into the pod and run `du -sh /*`
or check node-level with `sudo du -sh /var/lib/docker/overlay2/*`

**Q: Can two containers share the same writable layer?**
A: No. Each container gets its own private writable upper layer.
They can share read-only image layers, but writes are always isolated.

**Q: What happens to the writable layer when a container crashes?**
A: It persists until the container is explicitly removed (docker rm
or kubectl pod deletion). A crashed-but-not-deleted container still
has its writable layer on disk. This is how you can `docker start`
a stopped container and find your files still there.

**Q: What is a bind mount vs a volume mount?**
A: A bind mount maps a specific host path into the container.
A volume mount uses Docker/Kubernetes managed storage.
Both bypass the OverlayFS upper layer — writes go directly to the
underlying storage, not the ephemeral container layer.
In Kubernetes: always use PersistentVolumeClaims, not bind mounts
(bind mounts tie you to a specific node's filesystem).

---

## Understanding check — clarifications

### On container writes and disk usage
Every write inside a container goes to the OverlayFS writable upper
layer, which physically lives at /var/lib/docker/overlay2/ on the host.
Writing 10GB of logs inside a container = 10GB consumed on host disk.
No volume mounts needed for this to happen.
This is a real production issue: runaway log writers fill node disks.
Fix: always mount log directories as volumes, or configure log rotation
inside the container.

### On rm and open file descriptors
`rm` does two things:
  1. Removes the directory entry (the filename → inode mapping)
  2. Decrements the inode link count

Space is freed ONLY when BOTH conditions are true:
  - Link count reaches 0 (no more filenames pointing to this inode)
  - No process has the file open (no open file descriptors)

If an app is actively writing to a log file and you rm it:
  - Link count drops to 0 (filename is gone, ls won't show it)
  - But the app's file descriptor keeps the inode alive
  - Data blocks are NOT freed until the app closes the file
  - Disk usage does not change until process restart

Workaround (without restarting): truncate the file to zero bytes
  truncate -s 0 /proc/<pid>/fd/<fd_number>
This empties the content while the file descriptor stays valid.
The writing process continues without errors, disk space is reclaimed.
