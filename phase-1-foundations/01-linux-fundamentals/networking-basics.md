# Networking Basics (TCP/IP, Ports, DNS)

## IP Addresses

An IP address uniquely identifies a device on a network.
IPv4: 32-bit, written as four octets (e.g. 192.168.1.100)
IPv6: 128-bit, written in hex (e.g. 2001:db8::1)

### Important IP ranges
| Range | Purpose |
|-------|---------|
| 10.0.0.0/8 | Private — internal networks |
| 172.16.0.0/12 | Private — internal networks |
| 192.168.0.0/16 | Private — home/office |
| 127.0.0.0/8 | Loopback — localhost |
| 0.0.0.0 | Wildcard — all interfaces |

### CIDR notation
192.168.1.0/24 means:
- First 24 bits = network part (192.168.1)
- Last 8 bits = host part (0-255)
- 254 usable addresses

Kubernetes pod networks use CIDR blocks.
Each node gets a slice (e.g. 10.244.1.0/24 = 254 pods per node).

## Network Interfaces

| Interface | What it is |
|-----------|-----------|
| eth0, enp3s0 | Physical ethernet |
| wlan0, wlp2s0 | WiFi |
| lo | Loopback (127.0.0.1) |
| docker0 | Docker virtual bridge |
| veth* | Virtual ethernet pair (container ↔ host) |
| cni0 | Kubernetes CNI bridge |

### veth pairs
Every container gets a virtual ethernet pair:
- One end inside container (appears as eth0)
- One end on host (appears as vethXXXXXX)
Traffic flows through this pipe in both directions.

## TCP vs UDP

| Feature | TCP | UDP |
|---------|-----|-----|
| Connection | Yes (handshake) | No |
| Reliability | Guaranteed | Best effort |
| Order | In order | May reorder |
| Speed | Slower | Faster |
| Use cases | HTTP, SSH, DB | DNS, streaming |

Kubernetes internal components use TLS over TCP.
DNS queries use UDP port 53 (small/fast).
HTTP health checks use TCP.

## Ports

| Range | Name | Notes |
|-------|------|-------|
| 0-1023 | Privileged | Root or NET_BIND_SERVICE required |
| 1024-49151 | Registered | Common applications |
| 49152-65535 | Ephemeral | OS-assigned for outgoing connections |

### Kubernetes-specific ports
| Port | Service |
|------|---------|
| 6443 | API server |
| 2379-2380 | etcd |
| 10250 | kubelet |
| 30000-32767 | NodePort range |

## DNS

DNS translates names to IPs.
Resolution order: local cache → /etc/hosts → DNS server

### DNS record types
| Record | Purpose |
|--------|---------|
| A | Hostname → IPv4 |
| AAAA | Hostname → IPv6 |
| CNAME | Alias → hostname |
| MX | Mail server |
| TXT | Arbitrary text |
| PTR | IP → hostname (reverse) |

### Kubernetes DNS (CoreDNS)
Every Service gets a DNS name:
  <service>.<namespace>.svc.cluster.local

From same namespace: use just <service>
From different namespace: use <service>.<namespace>

Pod /etc/resolv.conf points to CoreDNS (10.96.0.10 by default).
search domains allow short names to resolve automatically.

## Key commands
| Command | What it does |
|---------|-------------|
| `ip addr show` | Show all interfaces and IPs |
| `ip -brief addr show` | Compact interface listing |
| `ip route show` | Show routing table |
| `ip route get <ip>` | Show route for specific IP |
| `ss -tlnp` | Show TCP listening ports with process |
| `ss -ulnp` | Show UDP listening ports |
| `ss -tnp` | Show all TCP connections |
| `dig <domain>` | DNS lookup with full detail |
| `dig -x <ip>` | Reverse DNS lookup |
| `nslookup <domain>` | Simple DNS lookup |
| `traceroute <host>` | Trace packet path hop by hop |
| `curl -v <url>` | HTTP request with full detail |
| `cat /etc/resolv.conf` | Show DNS configuration |
| `cat /etc/hosts` | Show local hostname overrides |

## Linux → Kubernetes mapping

| Linux concept | Kubernetes equivalent |
|---------------|----------------------|
| IP address | Pod IP (one per pod) |
| Port | containerPort in pod spec |
| Network interface | Pod's eth0 (veth pair) |
| /etc/resolv.conf | Auto-configured to CoreDNS |
| iptables NAT rules | Service ClusterIP routing |
| DNS A record | Service DNS name → ClusterIP |
| Network namespace | Pod network isolation |
| docker0 bridge | CNI bridge (cni0, flannel, etc) |
| veth pair | Pod ↔ node connection |
| Routing table | CNI-managed inter-node routing |

## Important production notes

- **CoreDNS is critical infrastructure**: If CoreDNS pods crash,
  all service-to-service communication by name fails cluster-wide.
  Always run at least 2 CoreDNS replicas. Monitor CoreDNS pod health.

- **DNS caching and TTL**: Applications that cache DNS results
  indefinitely will keep connecting to old pod IPs after a Service
  update. Use short TTLs or ensure your HTTP client respects DNS TTL.
  This causes "works most of the time, fails occasionally" bugs.

- **Port conflicts on nodes**: NodePort services claim a port on
  every node (30000-32767). If you have 50 NodePort services, all
  50 ports are reserved on every node. Plan your port usage.

- **0.0.0.0 vs 127.0.0.1 binding**: An app listening on 127.0.0.1
  is only reachable from within the same pod. An app listening on
  0.0.0.0 is reachable from anywhere. Always check which your app
  binds to — apps that accidentally bind to 127.0.0.1 in containers
  are unreachable by Kubernetes health checks and other pods.

- **Privileged ports in containers**: Don't run containers as root
  just for port 80/443. Run on port 8080/8443 and use a Service or
  Ingress to expose standard ports externally.

- **Network namespace per pod not per container**: All containers
  in a pod share ONE network namespace. They all have the same IP.
  They communicate via localhost. Port conflicts between containers
  in the same pod are real — plan ports carefully.

## Real-world production scenarios

### Scenario 1 — Service unreachable by name, reachable by IP
Pod A can curl http://10.96.45.23 (Service IP) but
curl http://my-service fails with "could not resolve host".
Root cause: CoreDNS is down or crashlooping.
Diagnosis:
  kubectl get pods -n kube-system | grep coredns
  kubectl logs -n kube-system <coredns-pod>
Fix: restart CoreDNS pods, check resource limits,
check CoreDNS ConfigMap for syntax errors.

### Scenario 2 — Intermittent connection failures between services
Service A calls Service B. 1 in 50 requests fails with
"connection refused". Service B has 3 replicas.
Root cause: one of Service B's pods is failing health checks
and being removed from Endpoints, but DNS still returns its IP
briefly due to caching, or iptables rules haven't updated yet.
Diagnosis:
  kubectl get endpoints my-service-b
  kubectl describe pod <failing-pod>
Fix: tune readiness probe to detect failures faster.
Ensure app binds to 0.0.0.0 not 127.0.0.1.

### Scenario 3 — Pod cannot reach external internet
Pod can reach other pods and services but curl google.com fails.
Root cause options:
  1. Network policy blocking egress traffic
  2. Node's iptables rules corrupted
  3. DNS resolution failing for external names
Diagnosis:
  kubectl exec mypod -- curl -v https://google.com
  kubectl exec mypod -- dig google.com
  kubectl exec mypod -- dig google.com @8.8.8.8
If direct DNS to 8.8.8.8 works but CoreDNS doesn't:
  CoreDNS is not forwarding external queries correctly.
  Check CoreDNS Corefile configuration.

### Scenario 4 — Two containers in same pod can't communicate
Container A tries to connect to Container B on port 5000.
Root cause: Container B is binding to 127.0.0.1:5000 instead
of 0.0.0.0:5000. Within a pod, containers share network namespace
so localhost works, but the app must listen on 0.0.0.0 to be
reachable even from within the same pod on a different process.
Fix: configure Container B's app to bind to 0.0.0.0.

## FAQ

**Q: Every pod gets its own IP — how does Kubernetes manage
thousands of IPs without conflicts?**
A: The cluster is configured with a pod CIDR (e.g. 10.244.0.0/16).
Each node is assigned a slice of that CIDR (e.g. 10.244.1.0/24).
The CNI plugin ensures IPs are assigned from the node's slice only.
No two pods on different nodes can get the same IP because they
draw from non-overlapping ranges.

**Q: What is a CNI plugin and do I need to choose one?**
A: CNI (Container Network Interface) is the standard for Kubernetes
networking plugins. Popular options: Flannel (simple), Calico
(supports NetworkPolicy), Cilium (eBPF-based, high performance).
For local kind clusters, kind uses its own CNI automatically.
For production, Calico or Cilium are most common.

**Q: Why does my pod have IP 10.244.x.x but my node has 192.168.x.x?**
A: They are on different networks. The pod network (10.244.0.0/16)
is an overlay network managed by the CNI plugin — it exists
logically on top of the physical node network (192.168.x.x).
The CNI plugin handles routing between them transparently.

**Q: Can two pods in different namespaces communicate?**
A: Yes, by default. Kubernetes namespaces are not network isolation
boundaries. Any pod can reach any other pod by IP regardless of
namespace. To restrict this, use NetworkPolicies (Phase 4).

**Q: What is the difference between ClusterIP, NodePort,
and LoadBalancer?**
A: Three types of Kubernetes Services — covered in depth in Phase 2.
Short answer: ClusterIP = internal only, NodePort = accessible on
every node's IP at a static port, LoadBalancer = cloud provider
creates an external load balancer. All use iptables/eBPF rules
under the hood to route to actual pod IPs.

**Q: How does CoreDNS know about my Services automatically?**
A: CoreDNS watches the Kubernetes API server for Service and
Endpoint changes. When you create a Service, CoreDNS is notified
immediately and adds a DNS record. No manual DNS management needed.
This is one of the core conveniences Kubernetes provides.
