# GitOps

Terraform installs Argo CD and External Secrets once, from `azure/schmeide/gitops.tf`, plus one root Application.
Argo then applies whatever is under `gitops/schmeide/apps` on `main`. Helm values sit beside `apps/`, one directory
per chart, so the directory sync does not apply them as manifests.

`schmeide/iac` is public, so Argo clones it with no repository credential.

Reach the Argo CD UI with `kubectl -n argocd port-forward svc/argo-cd-server 8080:443`. The admin password is
in the `argocd-initial-admin-secret` Secret. There is no public hostname, because no domain is chosen.

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
- `temporal-secrets.yaml`, `forgejo-secrets.yaml`: the namespaces, and ExternalSecrets that project passwords from the
  platform Key Vault through the `schmeide` ClusterSecretStore.

Traefik is the ingress controller because ingress-nginx was retired upstream in March 2026.

Sync waves order the first sync: namespaces and the two Applications that bring CRDs (cert-manager, Traefik) at 0,
the ClusterIssuer and ExternalSecrets at 1, Temporal and Forgejo at 2.

## Secrets

Terraform generates both passwords and writes them to Key Vault with write-only arguments, so neither is in state:

| Key Vault secret | Used by | Kubernetes Secret |
| --- | --- | --- |
| `postgres-admin-password` | Temporal, Forgejo | `temporal/temporal-db`, `forgejo/forgejo-db` |
| `forgejo-admin-password` | Forgejo's `schmeide-admin` user | `forgejo/forgejo-admin` |

## Placeholders

Each is marked `PLACEHOLDER` in the file.

| What | Where | Fill in |
| --- | --- | --- |
| Postgres FQDN | `temporal/values.yaml` (`connectAddr`, `serverName`), `forgejo/values.yaml` (`HOST`) | `postgres_fqdn` output after the first apply. It matches if `psql-schmeide` was available. |
| Postgres login for Temporal and Forgejo | `temporal/values.yaml`, `forgejo/values.yaml`, `apps/*-secrets.yaml` | Both use the admin login for now. A dedicated login per service needs a role created inside Postgres, which terraform cannot reach from CI on a private server. |
| Forgejo hostname | `forgejo/values.yaml` (`DOMAIN`, `ROOT_URL`, `ingress.hosts`, `ingress.tls`) | A name on the platform domain, once chosen. Then set `ingress.enabled: true`. |
| Forgejo admin email | `forgejo/values.yaml` (`gitea.admin.email`) | An address on the platform domain. |
| Ingress public IP | `traefik/values.yaml` | Dynamic for now. Reserve a static IP when DNS records point at it. |
| Temporal UI hostname | `temporal/values.yaml` | None yet; the UI is reached with `kubectl port-forward`. |

The `.invalid` names never resolve, so nothing is issued or exposed until they are replaced.

## Not verified

`helm template` was not run against these values; no Helm binary was available when they were written. The keys were
checked by reading each chart's `values.yaml` and templates at the pinned version.
