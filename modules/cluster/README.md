# `cluster` module

The schmeide AKS cluster and the platform Key Vault. One cluster runs the platform (API, Temporal, Forgejo, sandbox
pods for agent jobs, check Jobs) and every tenant's generated backends, one namespace per tenant.

Argo CD and External Secrets are installed from the root module, `azure/schmeide/gitops.tf`, not here.

## Shape

- **Free tier**, Kubernetes `1.36` with patch auto-upgrade. Move to Standard before tenants depend on it.
- **Local accounts off**, Entra ID with Azure RBAC. The API server is public with no authorized IP ranges, because
  GitHub-hosted runners have no stable egress. Entra is the lock.
- **OIDC issuer and workload identity on.** External Secrets uses them now; platform workloads will too.
- **Azure CNI overlay with Cilium**, so pods do not take node subnet addresses. Sizing is in
  `modules/network/README.md`.
- **System pool**: one `Standard_D2s_v6`, tainted `CriticalAddonsOnly`. It runs AKS addons, Argo CD and External
  Secrets.
- **User pool**: `Standard_D4as_v6`, autoscaled from 1 to 2. Everything else runs here.
- **Registry**: the kubelet identity gets Container Registry Repository Reader on the registry, which is the pull role
  in ABAC repository mode.

## Quota

At the defaults the cluster can use 12 vCPUs: 2 for the system node, 2 for its temporary copy during a rotation, and
8 for two user nodes. A new subscription's per-family vCPU quota may be lower than that. Check with
`az vm list-usage -l centralus -o table` and request more before raising `user_max_count`. Azure rejects a whole
scale-up that would pass the quota, so a pool stuck below its maximum is the symptom.

## Before the first apply

`./bootstrap/github-oidc.bash create` must have run. The CI identity is a Contributor, which cannot write role
assignments, and this module makes four (Network Contributor on the node subnet, Repository Reader on the registry,
Cluster User and RBAC Cluster Admin on the cluster). The script grants Role Based Access Control Administrator limited
to exactly those roles.

## Key Vault

Access policies, not RBAC, as in autobutler-org/iac: Key Vault data-plane roles are outside the bootstrap script's
allow list. The CI identity gets Get, List, Set, Delete and Recover so terraform can write the generated passwords.
To read a secret yourself, add a policy by hand; terraform leaves it alone:

```bash
az keyvault set-policy --name kv-schmeide \
  --object-id "$(az ad signed-in-user show --query id -o tsv)" \
  --secret-permissions get list
```
