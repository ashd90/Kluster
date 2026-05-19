# Kluster

A hands-on, project-based Kubernetes learning journey from Linux fundamentals
to production-grade platform engineering.

**OS**: CachyOS (Arch Linux)
**Local cluster**: kind (Kubernetes IN Docker)
**Approach**: Every concept is taught through a real project

---

## Roadmap

| Phase | Topics | Projects |
|-------|--------|---------|
| [Phase 1 — Foundations](#phase-1--foundations) | Linux, containers, YAML, kubectl | P01, P02, P03 |
| [Phase 2 — Core Kubernetes](#phase-2--core-kubernetes) | Architecture, workloads, config, networking | P04, P05, P06 |
| [Phase 3 — Storage & Scheduling](#phase-3--storage--scheduling) | Volumes, PVCs, resource limits, affinity | P07, P08, P09 |
| [Phase 4 — Security](#phase-4--security) | RBAC, pod security, network policies | P10, P11, P12 |
| [Phase 5 — Advanced Kubernetes](#phase-5--advanced-kubernetes) | Helm, autoscaling, observability, troubleshooting | P13, P14, P15 |
| [Phase 6 — Production & Platform Engineering](#phase-6--production--platform-engineering) | CI/CD, ArgoCD, multi-env, cloud | P16, P17, P18 |

---

## Phase 1 — Foundations

**Goal**: Understand what containers really are before touching Kubernetes.

### Topics
- Linux fundamentals: processes, signals, filesystems, users, networking, cgroups, namespaces
- Containers: Docker architecture, image layers, container networking
- YAML & kubectl: structure, imperative vs declarative, reading manifests
- Why Kubernetes: scheduling problem, scaling, self-healing, desired state

### Projects
| # | Project | Key concepts |
|---|---------|-------------|
| P01 | [Linux process explorer](phase-1-foundations/projects/p01-linux-process-explorer/) | PIDs, namespaces, cgroups, signals |
| P02 | [Containerise a Python app](phase-1-foundations/projects/p02-containerise-python-app/) | Dockerfile, image layers, registries |
| P03 | [kind cluster + kubectl tour](phase-1-foundations/projects/p03-kind-cluster-kubectl-tour/) | kind setup, kubectl basics, first manifests |

---

## Phase 2 — Core Kubernetes

**Goal**: Deploy and manage real applications on Kubernetes.

### Topics
- Architecture: control plane, worker nodes, API server, scheduler, etcd
- Core workloads: Pod, ReplicaSet, Deployment, StatefulSet, DaemonSet
- Configuration: ConfigMaps, Secrets, environment variables
- Services & networking: ClusterIP, NodePort, LoadBalancer, Ingress, cluster DNS

### Projects
| # | Project | Key concepts |
|---|---------|-------------|
| P04 | [Deploy a todo app](phase-2-core-kubernetes/projects/p04-todo-app/) | Pods, Deployments, Services |
| P05 | [Multi-tier blog platform](phase-2-core-kubernetes/projects/p05-multi-tier-blog/) | StatefulSet, ConfigMaps, Secrets |
| P06 | [Ingress routing](phase-2-core-kubernetes/projects/p06-ingress-routing/) | Ingress, DNS, multiple services |

---

## Phase 3 — Storage & Scheduling

**Goal**: Run stateful workloads and control where pods land.

### Topics
- Storage: Volumes, PersistentVolumes, PersistentVolumeClaims, StorageClasses
- Resource management: Requests & Limits, ResourceQuotas, LimitRanges
- Advanced scheduling: Node selectors, Node affinity, Taints & tolerations, Pod anti-affinity

### Projects
| # | Project | Key concepts |
|---|---------|-------------|
| P07 | [Stateful Postgres DB](phase-3-storage-and-scheduling/projects/p07-stateful-postgres/) | PV, PVC, StatefulSet, data persistence |
| P08 | [Resource quota sandbox](phase-3-storage-and-scheduling/projects/p08-resource-quota-sandbox/) | ResourceQuota, LimitRange, requests/limits |
| P09 | [Node affinity scheduling](phase-3-storage-and-scheduling/projects/p09-node-affinity-scheduling/) | Node affinity, taints, tolerations |

---

## Phase 4 — Security

**Goal**: Lock down the cluster. Non-negotiable for anything production.

### Topics
- Access control: RBAC, Roles vs ClusterRoles, ServiceAccounts, least privilege
- Pod security: SecurityContext, Pod Security Standards, image security
- Network security: NetworkPolicies, internal-only services, mTLS concepts

### Projects
| # | Project | Key concepts |
|---|---------|-------------|
| P10 | [RBAC multi-tenant cluster](phase-4-security/projects/p10-rbac-multi-tenant/) | Roles, RoleBindings, ServiceAccounts |
| P11 | [Hardened pod deployment](phase-4-security/projects/p11-hardened-pod/) | SecurityContext, non-root, read-only FS |
| P12 | [Network policy firewall](phase-4-security/projects/p12-network-policy-firewall/) | NetworkPolicy, ingress/egress rules |

---

## Phase 5 — Advanced Kubernetes

**Goal**: Package, scale, observe, and debug production workloads.

### Topics
- Helm: charts, values, releases, repositories
- Autoscaling: HPA, VPA, Cluster Autoscaler
- Observability: logs, metrics, traces, Prometheus, Grafana
- Troubleshooting: CrashLoopBackOff, OOMKilled, Pending pods, networking failures

### Projects
| # | Project | Key concepts |
|---|---------|-------------|
| P13 | [Helm chart for full app](phase-5-advanced-kubernetes/projects/p13-helm-chart-full-app/) | Helm chart authoring, values, upgrades |
| P14 | [HPA load test](phase-5-advanced-kubernetes/projects/p14-hpa-load-test/) | HPA, metrics-server, load testing |
| P15 | [Break-and-fix incident lab](phase-5-advanced-kubernetes/projects/p15-break-and-fix-lab/) | Real failure scenarios, debugging |

---

## Phase 6 — Production & Platform Engineering

**Goal**: Ship code to production safely and repeatedly.

### Topics
- CI/CD & GitOps concepts: deployment strategies, rollbacks, progressive delivery
- ArgoCD: architecture, install, app syncing, health checks, multi-env management
- Multi-environment: dev/stage/prod, namespace vs cluster strategy, promotion flows
- Cloud Kubernetes: EKS/GKE/AKS, cloud networking, cost optimisation

### Projects
| # | Project | Key concepts |
|---|---------|-------------|
| P16 | [GitOps with ArgoCD](phase-6-production/projects/p16-gitops-argocd/) | ArgoCD setup, Git-driven deploys, sync |
| P17 | [Multi-env promotion flow](phase-6-production/projects/p17-multi-env-promotion/) | Dev → staging → prod, Helm + ArgoCD |
| P18 | [Cloud cluster deploy](phase-6-production/projects/p18-cloud-cluster-deploy/) | Managed Kubernetes, cloud networking |

---

## Tool stack

| Tool | Purpose |
|------|---------|
| Docker | Container runtime |
| kind | Local multi-node Kubernetes clusters |
| kubectl | Kubernetes CLI |
| Helm | Package manager for Kubernetes |
| ArgoCD | GitOps continuous delivery |
| Prometheus | Metrics collection |
| Grafana | Metrics visualisation |
| k9s | Terminal UI for Kubernetes |

---

## How this repo is organised

Each topic folder contains a `README.md` with theory, diagrams, and commands.
Each project folder contains:
- `README.md` — what we're building, why, and step-by-step walkthrough
- All YAML manifests and code used in the project
- A `notes.md` for personal observations and lessons learned

---

*Built on CachyOS · Kubernetes the hard way (then the right way)*
