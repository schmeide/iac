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

Terraform installs `external-secrets` 2.15.0 and `argo-cd` 10.18.0 (Argo CD v3.6.1). All versions were read from the
upstream repository indexes or release lists on 2026-11-16. Renovate keeps them current.

Besides the Applications, `apps/` holds:

- `cluster-issuer.yaml`: a `letsencrypt` ClusterIssuer, HTTP-01 through the `traefik` ingress class.
- `temporal-secrets.yaml`, `forgejo-secrets.yaml`, `schmeide-app-secrets.yaml`: the namespaces, and ExternalSecrets
  that project secrets from the platform Key Vault through the `schmeide` ClusterSecretStore.

Traefik is the ingress controller because ingress-nginx was retired upstream in March 2026.

Sync waves order the first sync: namespaces and the two Applications that bring CRDs (cert-manager, Traefik) at 0,
the ClusterIssuer and ExternalSecrets at 1, Temporal and Forgejo at 2.

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

- File: `gitops/schmeide/schmeide-app/kustomization.yaml`, created with the Application in #25.
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
| Postgres FQDN | `temporal/values.yaml` (`connectAddr`, `serverName`), `forgejo/values.yaml` (`HOST`), `apps/schmeide-app-secrets.yaml` (`DATABASE_URL`) | `postgres_fqdn` output after the first apply. It matches if `psql-schmeide` was available. |
| Postgres login for Temporal and Forgejo | `temporal/values.yaml`, `forgejo/values.yaml`, `apps/*-secrets.yaml` | Both use the admin login for now. A dedicated login per service needs a role created inside Postgres, which terraform cannot reach from CI on a private server. |
| Forgejo hostname | `forgejo/values.yaml` (`DOMAIN`, `ROOT_URL`, `ingress.hosts`, `ingress.tls`) | A name on the platform domain, once chosen. Then set `ingress.enabled: true`. |
| Forgejo admin email | `forgejo/values.yaml` (`gitea.admin.email`) | An address on the platform domain. |
| Temporal UI hostname | `temporal/values.yaml` | None yet; the UI is reached with `kubectl port-forward`. |

The `.invalid` names never resolve, so nothing is issued or exposed until they are replaced.

## Not verified

`helm template` was not run against these values; no Helm binary was available when they were written. The keys were
checked by reading each chart's `values.yaml` and templates at the pinned version.
