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
- Key Vault `kv-schmeide` with `postgres-admin-password`, `forgejo-admin-password`, `schmeide-app-auth-secret` and
  `schmeide-app-postgres-password`.
- Container registry `schmeide` (Basic), storage account `stschmeidefrontends` with the `bundles` container.
- The identities and role assignments the modules declare.
- Helm releases `external-secrets`, `argo-cd` and `argocd-bootstrap`.
- vCPU quota in `centralus`: 16 regional and 12 for the Dav6 family, room for two user nodes, an upgrade surge node
  and a system pool rotation ([#5](https://github.com/schmeide/iac/issues/5)). Dsv6 stays at 10.

Verified inside the cluster with `kubectl` on 2026-11-16 ([#4](https://github.com/schmeide/iac/issues/4)):

- Both nodes `Ready` on Kubernetes 1.36.
- Argo CD: every pod running, and the `schmeide`, `cert-manager`, `traefik`, `temporal` and `forgejo` Applications
  `Synced` and `Healthy`. `cert-manager` was `OutOfSync` on the webhook AKS edits until
  [#18](https://github.com/schmeide/iac/issues/18).
- cert-manager: controller, cainjector and webhook running; the `letsencrypt` ClusterIssuer is `Ready` with a
  registered ACME account. No Certificate exists yet, because no hostname does.
- External Secrets: the `schmeide` ClusterSecretStore is `Valid`, and the `temporal-db`, `forgejo-db` and
  `forgejo-admin` ExternalSecrets are `SecretSynced`.
- Traefik: running, with a LoadBalancer IP that answers 404, as Traefik with no routes does.
- Temporal: frontend, history, matching, worker, web and admintools running, with no errors logged since a
  startup restart of matching. Forgejo: running and `Ready`, and its health check pings Postgres every 10 seconds.

### Reaching the cluster

Local accounts are disabled, so `kubectl` authenticates through `kubelogin` with your Azure CLI login, and needs an
`Azure Kubernetes Service RBAC` role on the cluster. Subscription Owner does not include one. The owner's account
holds `Azure Kubernetes Service RBAC Cluster Admin` at the cluster's scope, granted by hand rather than in Terraform,
so that no object ID is committed to this public repository:

```bash
az role assignment create \
  --assignee-object-id "$(az ad signed-in-user show --query id -o tsv)" \
  --assignee-principal-type User \
  --role "Azure Kubernetes Service RBAC Cluster Admin" \
  --scope "$(az aks show -g schmeide-cluster -n schmeide --subscription schmeide --query id -o tsv)"
```

The assignment is scoped to the cluster resource, so it is deleted with it. **Run it again whenever the cluster is
recreated.** It takes a few minutes to reach the API server. Use `Azure Kubernetes Service RBAC Reader` instead for an
account that should only look.

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

# Temporal Web at http://localhost:8081
kubectl -n temporal port-forward svc/temporal-web 8081:8080
```

`gitops/README.md` lists what is still a placeholder: the Forgejo and Temporal hostnames, the Forgejo admin email, and
the shared Postgres admin login.

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
| `registry.tf` | `modules/registry` | Azure Container Registry, pull granted to the cluster, push to `schmeide-app` for schmeide.app's CI |
| `postgres.tf` | `modules/postgres` | PostgreSQL flexible server, private access, databases for the platform, Temporal, Forgejo |
| `frontends.tf` | `modules/frontends` | Storage account for generated frontend bundles |
| `gitops.tf` | | Argo CD and External Secrets, and the root Argo Application |
| `dns.tf` | | The `apps.schmeide.com` zone, its wildcard record, and cert-manager's DNS-01 identity |

Argo CD then installs, from `gitops/schmeide/apps`: cert-manager with a Let's Encrypt issuer, Traefik as the ingress
controller, Temporal, and Forgejo. `gitops/README.md` covers that layer.

Each component has its own resource group (`schmeide-network`, `schmeide-cluster`, and so on), created in the root
file that wires its module, as in autobutler-org/iac.

### Left out on purpose

- Foundry resources. One is created per tenant, by the platform, later.
- A CDN or Front Door. The service is not chosen; see `modules/frontends/README.md`.
- Azure DNS for `schmeide.app` and `schmeide.com`. Both stay at Porkbun; only `apps.schmeide.com` is delegated to
  Azure. See "DNS" below.
- Monitoring beyond what AKS needs to run.
- A deploy identity for frontend bundles, and push identities for tenants' images. They belong to the platform's
  build and deploy steps, which do not exist yet. The one push identity is schmeide.app's CI, in `registry.tf`, limited
  to the `schmeide-app` repository; `gitops/README.md`, "Deploying schmeide.app", covers it.

### DNS

The `schmeide.app` zone is hosted at Porkbun (name servers `*.ns.porkbun.com`). The apex and `www` point at GitHub
Pages, which serves the site in Stage 1, so the zone stays where it is and terraform manages no DNS.

The cluster's one public name is `api.schmeide.app`. Traefik's LoadBalancer is pinned to the static IP
`pip-schmeide-ingress` (in `schmeide-cluster`, created by `modules/cluster`), so the record does not move with
redeploys. Adding it is a manual step for the owner, once, after the apply that creates the IP:

1. `gmake init`, then `gmake output` and read `ingress_ip_address`.
2. At Porkbun, add an `A` record: host `api`, answer that IP.
3. Check it: `dig +short api.schmeide.app` returns the IP, and `dig +short schmeide.app` still returns GitHub Pages'
   `185.199.108-111.153`.

If the IP is ever replaced, the record has to be edited by hand; `prevent_destroy` on the IP is there to stop that.

#### `apps.schmeide.com`

Built apps are served at `<host>.apps.schmeide.com`. `schmeide.com` stays at Porkbun: its apex is the marketing site
on GitHub Pages and its MX and SPF records forward mail, and terraform never touches it. Only the `apps` label is
delegated to the Azure DNS zone `apps.schmeide.com` in `dns.tf` (resource group `schmeide-network`), which holds a
wildcard `A` record `*` aliased to `pip-schmeide-ingress`. cert-manager answers DNS-01 there with the
`id-schmeide-cert-manager` workload identity, which holds DNS Zone Contributor on that zone only, and issues the
`*.apps.schmeide.com` certificate Traefik serves by default (`gitops/README.md`, "Apps domain").

The delegation is a manual step for the owner, once, after the apply that creates the zone:

1. `gmake init`, then `gmake output` and read `apps_name_servers`: four `ns1-NN.azure-dns.com.`-style names.
2. At Porkbun, in the `schmeide.com` zone, add four `NS` records, host `apps`, one per name server. Change no other
   `schmeide.com` record.
3. Check it: `dig NS apps.schmeide.com` (or `dig +short NS apps.schmeide.com`) lists the four Azure name servers,
   `dig +short anything.apps.schmeide.com` returns `ingress_ip_address`, and `dig +short MX schmeide.com` is unchanged.

Until then the wildcard Certificate stays not Ready; nothing else waits on it.

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
`value_wo`), so they appear in neither state nor a planfile. Each lands in the platform Key Vault, and
External Secrets projects it into the cluster. To rotate one, bump its `*_version` and apply.

The CI identity uses OIDC and has no client secret. `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` and `AZURE_SUBSCRIPTION_ID`
are still Actions *secrets*, not variables. None is a credential, but this repository is public, Terraform prints the
subscription ID in every resource ID and most errors, and GitHub masks secrets in logs where it does not mask
variables. `AZURE_ENABLED` stays a variable, because a job-level `if:` cannot read secrets.

Masking only rewrites log lines that contain the exact value. It does not cover:

- the job summary and the plan comment on a pull request. `plan.yml` replaces the three IDs in the rendered plan
  before writing either;
- a value that has been transformed (URL-encoded, base64, split across lines), which no longer matches;
- runs from before the switch, whose logs were deleted, and comments already posted on older pull requests.

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

4. **Check quota and versions in the region** (`centralus` by default). The cluster needs 16 regional vCPUs at its
   default ceiling: one `Standard_D2s_v6` system node and room to rotate it (4 Dsv6), and up to two
   `Standard_D4as_v6` user nodes plus an upgrade surge node (12 Dav6). A new subscription's limits are usually 10.
   `az vm list-usage -l centralus -o table` shows them, and `az aks get-versions -l centralus -o table` shows whether
   Kubernetes `1.36` is offered.
5. **Fill in `principalId`** in `bootstrap/main.bicepparam` with your own object ID
   (`az ad signed-in-user show --query id -o tsv`).
6. **Create the state backend:** `make bootstrap/whatif`, then `make bootstrap`. Then register the resource
   providers the stack uses with `make bootstrap/providers`. A new subscription has almost none registered, and the
   first apply fails with `MissingSubscriptionRegistration` without this.
7. **Create the CI identity:** `./bootstrap/github-oidc.bash create`. It prints three commands.
8. **Set the repository secrets** it printed: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` and `AZURE_SUBSCRIPTION_ID`.
   None is a credential, but secrets are masked in the public Actions logs and variables are not.
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

`plan.yml` runs a real plan on a pull request and posts it to the job summary and a sticky PR comment. `apply.yml`
runs on push to `main` and plans then applies that planfile in one job. Neither uploads the planfile: it embeds a
state snapshot, secrets included, and artifacts in this public repo are downloadable by any signed-in GitHub user.
Both are gated on `AZURE_ENABLED`.
`apply.yml` skips a push that touches only `gitops/**` or Markdown, so schmeide.app's image tag commits do not run
Terraform.

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
