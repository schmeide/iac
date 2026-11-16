# iac

Azure infrastructure for Schmeide, as Terraform against the `azurerm` provider. Its layout, tooling and conventions
follow [autobutler-org/iac](https://github.com/autobutler-org/iac).

`AGENTS.md` is the rules and commands. This file is the reasoning.

**Status: applied.** The `schmeide` subscription is live and the workflows are on. "Current state" below has what
exists and what is still open.

## Current state

As of 2026-11-16, every planned resource exists in `centralus`. The stack moved there from `eastus`, where the
subscription may not create PostgreSQL flexible servers ([#3](https://github.com/schmeide/iac/issues/3),
[#8](https://github.com/schmeide/iac/issues/8)). The state account `stschmeidetfstate` stays in `eastus`.

- Network: `schmeide-vnet`, the `nodes` and delegated `postgres` subnets, the Postgres private DNS zone and its link.
- AKS `schmeide`, Kubernetes 1.36, one `Standard_D2s_v6` system node and a `Standard_D4as_v6` user pool (1-2 nodes).
- PostgreSQL 17 `psql-schmeide` (`B_Standard_B2s`), with the `schmeide`, `temporal`, `temporal_visibility` and
  `forgejo` databases. Its FQDN matches the one in `gitops/`.
- Key Vault `kv-schmeide` with `postgres-admin-password` and `forgejo-admin-password`.
- Container registry `schmeide` (Basic), storage account `stschmeidefrontends` with the `bundles` container.
- The identities and role assignments the modules declare.
- Helm releases `external-secrets`, `argo-cd` and `argocd-bootstrap`. Argo has synced Traefik: its LoadBalancer
  Service has a public IP that answers 404, as Traefik with no routes does.

Open:

- **Kubernetes access for people** ([#4](https://github.com/schmeide/iac/issues/4)). Only the CI identity holds an
  `Azure Kubernetes Service RBAC *` role, and subscription Owner does not imply one. So cert-manager, the
  ExternalSecrets, Temporal, Forgejo and the Applications' sync status are unverified.
- **vCPU quota** ([#5](https://github.com/schmeide/iac/issues/5)). The regional limit in `centralus` is 10 and the
  cluster uses 6, which leaves no room for a second user node and an upgrade surge at once.

### Reaching the cluster

Local accounts are disabled, so `kubectl` authenticates through `kubelogin` with your Azure CLI login, and needs an
`Azure Kubernetes Service RBAC` role on the cluster (#4).

```bash
brew install kubectl kubelogin helm
az aks get-credentials --resource-group schmeide-cluster --name schmeide --subscription schmeide
kubelogin convert-kubeconfig -l azurecli
kubectl get applications -n argocd
```

No hostname exists yet, so the UIs are reached with port-forward only:

```bash
# Argo CD at https://localhost:8080, user admin
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
kubectl -n argocd port-forward svc/argo-cd-argocd-server 8080:443

# Temporal Web at http://localhost:8081, once Postgres exists
kubectl -n temporal port-forward svc/temporal-web 8081:8080
```

`gitops/README.md` lists what is still a placeholder: the Forgejo and Temporal hostnames, the Forgejo admin email, the
dynamic ingress IP, and the shared Postgres admin login.

## Layout

```text
azure/<subscription>/     one Azure subscription, one root module, one state file
modules/<name>/           shared modules, referenced with a relative source
bootstrap/                Bicep for the terraform state backend, and the CI identity script
gitops/<subscription>/    what Argo CD applies inside the cluster
.github/workflows/        check on PRs, plan on PRs, apply on push to main
```

**Every directory under `azure/` is an Azure subscription.** `azure/schmeide/` is the root module for the `schmeide`
subscription, and the only one. The Makefile resolves the directory name to the subscription and tenant IDs with
`az`, so no GUID is committed to this public repo, and a configuration under `azure/schmeide/` cannot quietly apply
somewhere else.

## What the seed creates

The shape comes from the decisions in the Schmeide planning repo: one AKS cluster for the platform and every tenant's
backends (a namespace per tenant), one shared Postgres server, static frontends in Blob Storage behind a CDN, a
container registry, and Let's Encrypt certificates.

| Root file | Module | What |
| --- | --- | --- |
| `network.tf` | `modules/network` | VNet, AKS node subnet, delegated Postgres subnet, Postgres private DNS zone |
| `cluster.tf` | `modules/cluster` | AKS with workload identity, a system and an autoscaled user pool, the platform Key Vault |
| `registry.tf` | `modules/registry` | Azure Container Registry, pull granted to the cluster |
| `postgres.tf` | `modules/postgres` | PostgreSQL flexible server, private access, databases for the platform, Temporal, Forgejo |
| `frontends.tf` | `modules/frontends` | Storage account for generated frontend bundles |
| `gitops.tf` | | Argo CD and External Secrets, and the root Argo Application |

Argo CD then installs, from `gitops/schmeide/apps`: cert-manager with a Let's Encrypt issuer, Traefik as the ingress
controller, Temporal, and Forgejo. `gitops/README.md` covers that layer.

Each component has its own resource group (`schmeide-network`, `schmeide-cluster`, and so on), created in the root
file that wires its module, as in autobutler-org/iac.

### Left out on purpose

- Foundry resources. One is created per tenant, by the platform, later.
- A CDN or Front Door. The service is not chosen; see `modules/frontends/README.md`.
- DNS zones. No domain is chosen for the platform or the sandbox apps.
- Monitoring beyond what AKS needs to run.
- Push identities for the registry and a deploy identity for frontend bundles. They belong to the platform's build and
  deploy steps, which do not exist yet.

## State

State lives in the `tfstate` container of the `stschmeidetfstate` storage account, in the `schmeide` subscription
itself. That account has no access keys (`allowSharedKeyAccess: false`), so access is Entra ID RBAC, which is why the
backend block sets `use_azuread_auth = true` and omits `resource_group_name`. Locking is a native blob lease.

The backend block also omits `subscription_id` and `tenant_id`. They are not known yet, and a backend block cannot
take variables, so the backend reads `ARM_SUBSCRIPTION_ID` and `ARM_TENANT_ID`. `make` exports both; in CI,
`azure/login` does.

`bootstrap/` is Bicep and not Terraform because a backend has to exist before Terraform has anywhere to record that it
built one. See `bootstrap/README.md`.

## Secrets

Terraform never stores a secret value. The Postgres admin password and the Forgejo admin password are generated by
ephemeral `random_password` resources and sent to Azure through write-only arguments (`administrator_password_wo`,
`value_wo`), so they appear in neither state nor the planfile artifact. Each lands in the platform Key Vault, and
External Secrets projects it into the cluster. To rotate one, bump its `*_version` and apply.

No workflow reads an Actions secret. The CI identity uses OIDC and has no client secret.

## Bringing the subscription online

Until these steps are done, `check.yml` is the only workflow that runs. `plan.yml` and `apply.yml` show their jobs as
skipped because the `AZURE_ENABLED` repository variable is not `true`.

1. **Create the subscription** and name it exactly `schmeide`. The Makefile resolves `SUBSCRIPTION=schmeide` by that
   name.
2. **Log in to its tenant** with `az login --tenant <tenant-id>` as someone who can create app registrations and
   assign roles in that subscription.
3. **Check the names that must be globally unique** and change any that are taken. None was checked, because nothing
   here calls Azure yet:

   | Name | Where |
   | --- | --- |
   | `stschmeidetfstate` | `bootstrap/main.bicep`, `azure/schmeide/backend.tf`, `bootstrap/github-oidc.bash` |
   | `kv-schmeide` | `azure/schmeide/cluster.tf` |
   | `schmeide` (registry) | `azure/schmeide/registry.tf` |
   | `psql-schmeide` | `azure/schmeide/postgres.tf`, `gitops/schmeide/temporal/values.yaml`, `forgejo/values.yaml` |
   | `stschmeidefrontends` | `azure/schmeide/frontends.tf` |

4. **Check quota and versions in the region** (`centralus` by default). The cluster needs about 12 vCPUs at its default
   ceiling: one `Standard_D2s_v6` system node, room to rotate it, and up to two `Standard_D4as_v6` user nodes. A new
   subscription's per-family quota may be lower. `az vm list-usage -l centralus -o table` shows it, and
   `az aks get-versions -l centralus -o table` shows whether Kubernetes `1.36` is offered.
5. **Fill in `principalId`** in `bootstrap/main.bicepparam` with your own object ID
   (`az ad signed-in-user show --query id -o tsv`).
6. **Create the state backend:** `make bootstrap/whatif`, then `make bootstrap`. Then register the resource
   providers the stack uses with `make bootstrap/providers`. A new subscription has almost none registered, and the
   first apply fails with `MissingSubscriptionRegistration` without this.
7. **Create the CI identity:** `./bootstrap/github-oidc.bash create`. It prints three commands.
8. **Set the repository variables** it printed: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` and `AZURE_SUBSCRIPTION_ID`.
   They are variables, not secrets; none is sensitive.
9. **Plan locally** to see the first plan before CI does: `make init`, then `make plan`. Untested: the Helm releases in
   `gitops.tf` point at a cluster that does not exist yet. If the first plan fails on them, land the cluster first in
   one pull request and `gitops.tf` in the next.
10. **Turn the workflows on:** `gh variable set AZURE_ENABLED --repo schmeide/iac --body true`. The next pull request
    plans, and the next merge to `main` applies.
11. **After the first apply**, fill in the placeholders listed in `gitops/README.md` (the Postgres FQDN if the name
    changed, and the hostnames once a domain is chosen).

## Getting started

```bash
brew install terraform tflint azure-cli make
npm ci
gmake            # help
gmake check      # format + lint + markdown + bicep + validate; no Azure access needed
```

On macOS use `gmake`: the Makefile needs GNU Make 3.82+ for `.ONESHELL:`, and `/usr/bin/make` is 3.81. The Makefile
checks this and says so.

## CI

`check.yml` runs formatting, linting, Markdown and validation on every pull request, and needs no Azure credentials.
`make check/validate` inits with `-backend=false`, so it reads provider schemas and nothing else.

`plan.yml` runs a real plan on a pull request, uploads the planfile, and posts the plan to the job summary and a sticky
PR comment. `apply.yml` runs on push to `main`, calls `plan.yml` as its first job, and applies that job's planfile, so
what gets applied is what was planned for that commit. Both are gated on `AZURE_ENABLED`.

`codeql.yml` scans the workflow files as the `actions` language. CodeQL has no Terraform or Bicep analyzer, so that is
all it can read; `tflint` covers the Terraform.

## Dependency updates

Renovate, with the policy written out in `renovate.json`: `config:recommended`, daily, and one grouped pull request
per ecosystem (GitHub Actions, Terraform providers, npm, and the Helm chart versions in the Argo CD Applications).
autobutler-org/iac extends an org-wide preset; this repo cannot, so the equivalent rules are inline.

Renovate only runs once the [Renovate GitHub App](https://github.com/apps/renovate) is installed on `schmeide/iac`.
Until then nothing opens update pull requests. Renovate was chosen over Dependabot because Dependabot cannot update the
chart versions in Argo CD Application files.

Check the lock file diff on every Terraform update. `.terraform.lock.hcl` covers four platforms, and a regenerated lock
that shrank still passes CI. If the `h1:` list got shorter, run `make lock` on the branch.

## Adding a shared module

`modules/<name>/`, with a file per resource type, `variables.tf`, `outputs.tf`, and a `main.tf` holding the module's
`terraform` block. Call it from the root module with a relative `source`. Constraints in a module are floors
(`>= 5.0`); the root module pins.
