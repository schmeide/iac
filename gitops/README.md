# GitOps

Terraform installs Argo CD and External Secrets once, from `azure/schmeide/gitops.tf`, plus one root Application.
Argo then applies whatever is under `gitops/schmeide/apps` on `main`. Helm values sit beside `apps/`, one directory
per chart, so the directory sync does not apply them as manifests.

`schmeide/iac` is public, so Argo clones it with no repository credential.

Reach the Argo CD UI with `kubectl -n argocd port-forward svc/argo-cd-argocd-server 8080:443`. The admin password is
in the `argocd-initial-admin-secret` Secret. There is no public hostname for it.

## What Argo installs

| Application | Chart | Version | Source |
| --- | --- | --- | --- |
| `cert-manager` | `cert-manager` | v1.21.3 | `https://charts.jetstack.io` |
| `traefik` | `traefik` | 42.4.0 (Traefik v3.7.18) | `https://traefik.github.io/charts` |
| `temporal` | `temporal` | 1.8.0 (server 1.32.2) | `https://go.temporal.io/helm-charts` |
| `forgejo` | `forgejo` | 17.3.2 (Forgejo 15.0) | `oci://code.forgejo.org/forgejo-helm/forgejo` |
| `schmeide-app` | none: kustomize | image tag in `schmeide-app/kustomization.yaml` | this repo |

Terraform installs `external-secrets` 2.15.0 and `argo-cd` 10.18.0 (Argo CD v3.6.1). All versions were read from the
upstream repository indexes or release lists on 2026-11-16. Renovate keeps them current.

Besides the Applications, `apps/` holds:

- `cluster-issuer.yaml`: a `letsencrypt` ClusterIssuer, HTTP-01 through the `traefik` ingress class.
- `cluster-issuer-dns.jsonnet` and `apps-wildcard-certificate.yaml`: DNS-01 and the `*.apps.schmeide.com`
  certificate; see "Apps domain" below.
- `temporal-secrets.yaml`, `forgejo-secrets.yaml`, `schmeide-app-secrets.yaml`: the namespaces, and ExternalSecrets
  that project secrets from the platform Key Vault through the `schmeide` ClusterSecretStore.
- `schmeide-builds.yaml` and `schmeide-worker.yaml`: the namespace build Jobs run in and the worker's Kubernetes
  rights; see "Builds and the worker" below.

Traefik is the ingress controller because ingress-nginx was retired upstream in March 2026. Its Service uses
`externalTrafficPolicy: Local`, so Traefik sees the caller's address and puts it in `X-Forwarded-For`; the
schmeide.app API limits sign-in attempts per address.

The Temporal chart registers the `default` Temporal namespace (`server.config.namespaces`), which the schmeide.app API
uses.

## The schmeide.app API

`apps/schmeide-app.yaml` applies the kustomization in `schmeide-app/`, outside `apps/` so the root Application does
not also apply it as raw manifests:

- Deployment `schmeide-app-api`: one replica, `Recreate`, `SCHMEIDE_BUILDS=off`, environment from the
  `schmeide-app/schmeide-app` Secret, and an 8 GiB managed disk (`schmeide-app-data`) at `/data`, which also holds the
  claude CLI's `HOME`. Argo never prunes or deletes the disk; remove it by hand.
- Service and Ingress for `https://api.schmeide.app`, certificate from the `letsencrypt` ClusterIssuer.
- Job `schmeide-app-migrate`, a PreSync hook running `node src/migrate.ts`. If it fails the sync stops before the
  Deployment changes. It needs the `schmeide_app` login below.

Sync waves order the first sync: namespaces, the two Applications that bring CRDs (cert-manager, Traefik), and the
worker's admission policy at 0, the ClusterIssuers, ExternalSecrets, and the `schmeide-builds` and worker RBAC objects
at 1, Temporal and Forgejo at 2, the schmeide.app API at 3, and the apps
wildcard Certificate at 4.

## Builds and the worker

Stage 2 slice 1 (schmeide/schmeide.app `docs/stage2.md`) runs each agent run and each round of checks as a Job in
`schmeide-builds`, and deploys built apps to one `tenant-<id>` namespace per business, all driven by a worker
Deployment of the API's image (`SCHMEIDE_ROLE=worker`, schmeide/schmeide.app#192). That Deployment is not here yet, so
everything below is dormant: nothing holds the `schmeide-worker` token and no pod runs in `schmeide-builds`.

`apps/schmeide-builds.yaml`:

- Namespace `schmeide-builds` with `pod-security.kubernetes.io/enforce: restricted`. Its default service account has
  no Role; build pods also set `automountServiceAccountToken: false`.
- ResourceQuota `builds`: `requests.cpu: 3500m` (three builds of 1.1 CPU), `requests.memory: 7Gi`,
  `limits.memory: 14Gi`, `pods: 10`. A Job whose pod would exceed it waits. With the platform's ~0.9 CPU that needs
  the second user node, which the autoscaler adds.
- LimitRange `builds`: defaults for a container that states nothing (request 100m and 128 MiB, limit 1 CPU and
  512 MiB) and a maximum of the agent's own limit, 2 CPU and 4 GiB.
- NetworkPolicy `default-deny` both ways, and `build-egress`: kube-dns on 53, the Forgejo pod's SSH port (2222, behind
  the `forgejo-ssh` Service's 22), and TCP 443 to `0.0.0.0/0` except `10.0.0.0/8`, `172.16.0.0/12`,
  `192.168.0.0/16`, `169.254.0.0/16` and `168.63.129.16/32`. Slice 3 (#35) narrows 443 to an FQDN allow-list.

`apps/schmeide-worker.yaml` gives service account `schmeide-app/schmeide-worker`:

| Object | Grants |
| --- | --- |
| Role and RoleBinding `schmeide-worker` in `schmeide-builds` | `jobs`: create, get, list, watch, delete. `pods`, `pods/log`: get, list, watch. `secrets`: create, get, delete |
| ClusterRole and ClusterRoleBinding `schmeide-worker` | `namespaces`: get, create, patch, update, delete. `rolebindings`: create, patch, update. `bind` on ClusterRole `schmeide-tenant-deployer` only |
| ClusterRole `schmeide-tenant-deployer`, never bound cluster-wide | Deployments, Services, Ingresses, Secrets, ResourceQuotas, LimitRanges, NetworkPolicies: read and write |

On a business's first deploy the worker creates `tenant-<id>` and binds `schmeide-tenant-deployer` to itself there,
which is the only way it gets rights in that namespace.

RBAC cannot match a namespace by name or label, so ValidatingAdmissionPolicy `schmeide-worker-tenants-only` and its
binding (`admissionregistration.k8s.io/v1`, GA since Kubernetes 1.30) refuse the worker's create, update and delete
of namespaces, RoleBindings, and the deployer role's kinds unless the namespace is named `tenant-*`, carries the
`schmeide.app/tenant` label, and enforces `restricted`; Secrets in `schmeide-builds` are the one exception. A
RoleBinding must bind ClusterRole `schmeide-tenant-deployer` to the worker and nobody else. The policy syncs a wave
before the grants, so the worker never holds them unconfined.

What the worker cannot do: anything in `schmeide-app`, `argocd`, `temporal`, `forgejo` or another platform namespace,
including reading their Secrets; create, relabel or delete a namespace not named `tenant-*`, or relax a tenant
namespace's pod security; bind any other role, or bind the deployer role to anyone else; create service accounts,
Roles, pods or Jobs outside `schmeide-builds`. Admission policies match writes only; the worker's reads stop where its
RBAC does.

Still to come for slice 1: the worker Deployment, the `anthropic-builds`, Forgejo token and `schmeide_provisioner`
ExternalSecrets, the worker's and the ACR Task's Azure identities, and the `postgres:18-alpine` import.

## Apps domain

Built apps are served at `<host>.apps.schmeide.com` with one wildcard certificate, so no app needs a certificate or a
TLS Secret of its own and no app host name reaches Certificate Transparency logs. The zone and its delegation are in
`README.md`, "DNS".

- `apps/cluster-issuer-dns.jsonnet`: the `letsencrypt-dns` ClusterIssuer, DNS-01 with the `azureDNS` solver on the
  `apps.schmeide.com` zone. cert-manager authenticates as `id-schmeide-cert-manager` through workload identity:
  `cert-manager/values.yaml` labels its pod and fixes its service account name, which `azure/schmeide/dns.tf`
  federates.
- `apps/apps-wildcard-certificate.yaml`: `*.apps.schmeide.com` and `apps.schmeide.com` into the Secret
  `traefik/apps-wildcard-tls`.
- `traefik/values.yaml`: the default `TLSStore` serves that Secret to every TLS request no other certificate matches.

The ClusterIssuer is Jsonnet because it needs the identity's client id and the subscription id, which this repository
does not commit. `azure/schmeide/gitops.tf` passes them, with the zone and its resource group, to the root
Application as the Jsonnet top-level argument `certManager` (`charts/argocd-bootstrap`). Without it the file renders
nothing, so it is safe in a sync that runs before that apply.

The Certificate stays not Ready until the owner adds the `apps` NS records at Porkbun. It is in the last wave, and Argo
waits for a wave to be healthy only before it starts the next one, so a pending certificate blocks no other resource;
the root Application shows Progressing or Degraded until it is issued. Check it with
`kubectl -n traefik get certificate apps-wildcard`.

## Secrets

Terraform generates these and writes them to Key Vault with write-only arguments, so none is in state:

| Key Vault secret | Used by | Kubernetes Secret |
| --- | --- | --- |
| `postgres-admin-password` | Temporal, Forgejo | `temporal/temporal-db`, `forgejo/forgejo-db` |
| `forgejo-admin-password` | Forgejo's `schmeide-admin` user | `forgejo/forgejo-admin` |
| `schmeide-app-auth-secret` | schmeide.app API, `SCHMEIDE_AUTH_SECRET` | `schmeide-app/schmeide-app` |
| `schmeide-app-postgres-password` | schmeide.app API, the password in `DATABASE_URL` | `schmeide-app/schmeide-app` |

A person sets these by hand, because their values come from outside and this repo is public:

| Key Vault secret | Env var in `schmeide-app/schmeide-app` |
| --- | --- |
| `schmeide-app-google-client-id`, `schmeide-app-google-client-secret` | `SCHMEIDE_GOOGLE_CLIENT_ID`, `SCHMEIDE_GOOGLE_CLIENT_SECRET` |
| `schmeide-app-microsoft-client-id`, `schmeide-app-microsoft-client-secret` | `SCHMEIDE_MICROSOFT_CLIENT_ID`, `SCHMEIDE_MICROSOFT_CLIENT_SECRET` |
| `schmeide-app-apple-client-id`, `schmeide-app-apple-client-secret` | `SCHMEIDE_APPLE_CLIENT_ID`, `SCHMEIDE_APPLE_CLIENT_SECRET` |
| `schmeide-app-anthropic-api-key` | `ANTHROPIC_API_KEY` |

Each is optional. The ExternalSecret picks them up with `find`, so a missing one leaves its variable empty and the
sync stays healthy; the server offers a sign-in provider only when both its id and secret are set. Set one with the
value on stdin, not on the command line, so it stays out of shell history:

```bash
az keyvault secret set --vault-name kv-schmeide --name schmeide-app-google-client-id --file /dev/stdin
```

The ExternalSecret refreshes hourly. To pick a new value up now, and restart the pod so it reads it:

```bash
kubectl -n schmeide-app annotate externalsecret schmeide-app force-sync="$(date +%s)" --overwrite
kubectl -n schmeide-app rollout restart deployment
```

`DATABASE_URL` is built in the ExternalSecret template:
`postgres://schmeide_app:<schmeide-app-postgres-password>@psql-schmeide.postgres.database.azure.com:5432/schmeide?sslmode=require`.

### The `schmeide_app` login

The API connects as `schmeide_app`, a role with rights on database `schmeide` only. Terraform cannot create it: the
server is private and CI is outside the network. Create it once by hand, from a machine that reaches the server (the
Telepresence route, #12) as `schmeideadmin` (password readable with the `Key Vault Secrets User` role, #13). Run it
after the apply that creates `schmeide-app-postgres-password`, and before the API's first migration.

```bash
export PGHOST=psql-schmeide.postgres.database.azure.com PGUSER=schmeideadmin PGSSLMODE=require
export PGPASSWORD="$(az keyvault secret show --vault-name kv-schmeide --name postgres-admin-password --query value -o tsv)"
psql -d schmeide -v ON_ERROR_STOP=1 \
  -v pw="$(az keyvault secret show --vault-name kv-schmeide --name schmeide-app-postgres-password --query value -o tsv)"
```

```sql
CREATE ROLE schmeide_app LOGIN PASSWORD :'pw';

-- CREATE on the database lets drizzle-kit create its "drizzle" schema for the migrations table.
GRANT CONNECT, CREATE, TEMPORARY ON DATABASE schmeide TO schmeide_app;
GRANT USAGE, CREATE ON SCHEMA public TO schmeide_app;

-- Every role may connect to every database through PUBLIC by default. Grant the admin
-- explicitly first, since Temporal and Forgejo connect as it, then close the rest.
GRANT CONNECT ON DATABASE temporal, temporal_visibility, forgejo TO schmeideadmin;
REVOKE CONNECT ON DATABASE temporal, temporal_visibility, forgejo FROM PUBLIC;
```

The migrations then create every table as `schmeide_app`, so it owns them. This assumes `schmeide` is still empty. If an
earlier run left tables there owned by the admin, drop them or change their owner table by table; not with
`REASSIGN OWNED`, which would also hand over the databases the admin owns.

To rotate the password, bump `value_wo_version` on `azurerm_key_vault_secret.schmeide_app_postgres_password`, merge,
then `ALTER ROLE schmeide_app PASSWORD :'pw';` with the new value and restart the pod.

## Deploying schmeide.app

schmeide/schmeide.app's CI builds the API image and deploys it in two steps: push to the registry, then commit the new
tag here. Argo picks up the commit; nothing in this repo watches the registry.

**Push.** On `main` only, the workflow logs in with `azure/login` (OIDC) as `id-schmeide-app-push`, a user-assigned
identity in `azure/schmeide/registry.tf`. Its one federated credential trusts
`repo:schmeide@357239714/schmeide.app@1459650460:ref:refs/heads/main`, the immutable subject GitHub mints for that
repository. It holds Container Registry Repository Writer on the `schmeide` registry with an ABAC condition limiting it
to the `schmeide-app` repository: it can push and pull there, and cannot delete, list, or touch any other repository.
The image is `schmeide.azurecr.io/schmeide-app:<full git SHA of the schmeide.app commit>`. No `latest`.

The workflow reads these as repository variables on schmeide/schmeide.app, which the owner sets from `gmake output`:

| Variable | Terraform output |
| --- | --- |
| `AZURE_CLIENT_ID` | `schmeide_app_push_client_id` |
| `AZURE_TENANT_ID` | `tenant_id` |
| `AZURE_SUBSCRIPTION_ID` | `subscription_id` |

**Tag.** The workflow then clones `schmeide/iac` with an SSH deploy key that has write access (the private key is a
secret on schmeide/schmeide.app), sets the tag, and pushes one commit straight to `main`:

- File: `gitops/schmeide/schmeide-app/kustomization.yaml`.
- Entry: the `images:` item with `name: schmeide-app` and `newName: schmeide.azurecr.io/schmeide-app`. Only its
  `newTag` changes, to the full SHA. Nothing else in the file or the repo is touched.
- Commit: subject `chore(deploy): schmeide-app <short SHA>`, body naming the schmeide.app commit. `git revert` of it
  rolls the deployment back.
- Push: fast-forward only. `main` requires linear history and forbids force pushes, so on a rejected push the workflow
  fetches, rebases its one commit, and retries.

`apply.yml` ignores pushes that touch only `gitops/**` or Markdown, so a tag commit does not run Terraform.

## Placeholders

Each is marked `PLACEHOLDER` in the file.

| What | Where | Fill in |
| --- | --- | --- |
| Postgres login for Temporal and Forgejo | `temporal/values.yaml`, `forgejo/values.yaml`, `apps/*-secrets.yaml` | Both use the admin login for now. A dedicated login per service needs a role created inside Postgres, which terraform cannot reach from CI on a private server. |
| Forgejo hostname | `forgejo/values.yaml` (`DOMAIN`, `ROOT_URL`, `ingress.hosts`, `ingress.tls`) | A name on the platform domain, once chosen. Then set `ingress.enabled: true`. |
| Forgejo admin email | `forgejo/values.yaml` (`gitea.admin.email`) | An address on the platform domain. |
| Temporal UI hostname | `temporal/values.yaml` | None yet; the UI is reached with `kubectl port-forward`. |

The `.invalid` names never resolve, so nothing is issued or exposed until they are replaced.

## Not verified

`helm template` was not run against these values; no Helm binary was available when they were written. The keys were
checked by reading each chart's `values.yaml` and templates at the pinned version.
