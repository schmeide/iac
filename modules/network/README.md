# `network` module

The schmeide VNet, a subnet for AKS nodes, a subnet delegated to PostgreSQL flexible server, and the private DNS zone
the server registers in, linked to the VNet so pods can resolve it.

There are no NSGs here. AKS manages the security group on its node pools, and a delegated Postgres subnet takes only
the server. autobutler-org/iac uses NSGs only on standalone VMs, and there are none here.

## Address plan

| Range | Size | What |
| --- | --- | --- |
| `10.16.0.0/16` | 65,536 | VNet |
| `10.16.0.0/20` | 4,091 usable | AKS nodes and internal load balancer addresses |
| `10.16.16.0/24` | 251 usable | PostgreSQL flexible server (delegated) |
| `10.128.0.0/12` | 1,048,576 | Pod CIDR (overlay, not in the VNet; set in `modules/cluster`) |
| `172.16.0.0/16` | 65,536 | Service CIDR (not in the VNet; set in `modules/cluster`) |

The rest of `10.16.0.0/16` is free for later subnets, such as private endpoints.

## Why these sizes

The cluster runs one namespace per tenant and many pods per tenant: backends, sandbox pods, and check Jobs. Two
things could run out.

**Pod addresses.** With Azure CNI overlay, pods do not take addresses from the node subnet. Each node gets a `/24`
from the pod CIDR and runs up to 250 pods. A `/12` pod CIDR is 4,096 `/24`s, so it holds 4,096 nodes, or about a
million pods. autobutler-org/iac used a `/16` pod CIDR, which is 256 nodes, and found that a node pool at its ceiling
plus the temporary pool AKS creates to rotate it did not fit. A `/12` leaves room for every pool at its ceiling and
its rotation copy at once.

**Node addresses.** In overlay mode a node takes one address from the node subnet. A `/20` holds about 4,000 nodes,
which is more than the pod CIDR can serve, so the pod CIDR stays the binding limit.

**Services.** A `/16` service CIDR is 65,536 ClusterIPs, which at a handful of services per project is tens of
thousands of projects.

The ranges avoid `10.0.0.0/16` and `10.8.0.0/16`, which autobutler-org/iac uses, so the two estates could be peered
later. The pod and service CIDRs must not overlap the VNet or anything peered with it.
