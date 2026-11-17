# Argo CD and External Secrets, installed once, as in autobutler-org/iac. Argo then
# watches gitops/schmeide/apps on main and applies everything there: cert-manager, the
# ingress controller, Temporal, Forgejo, and the ExternalSecrets that hand them and the
# schmeide.app API their secrets. gitops/README.md covers that layer.
#
# Chart versions looked up on 2026-11-16 from the upstream Helm repository indexes:
# external-secrets 2.15.0 (appVersion v2.15.0) at https://charts.external-secrets.io and
# argo-cd 10.18.0 (appVersion v3.6.1) at https://argoproj.github.io/argo-helm.

# The External Secrets controller's identity. It reads the platform vault before any
# workload exists. Replaced on a tenant change for the reason given in
# modules/cluster/identity.tf.
resource "terraform_data" "tenant" {
  input = var.tenant_id
}

resource "azurerm_user_assigned_identity" "gitops" {
  name                = "id-schmeide-gitops"
  resource_group_name = azurerm_resource_group.cluster.name
  location            = var.location
  tags                = local.tags

  lifecycle {
    replace_triggered_by = [terraform_data.tenant]
  }
}

# The chart's service account is named explicitly below, so this subject cannot drift
# from a chart helper change.
resource "azurerm_federated_identity_credential" "gitops" {
  name                      = "external-secrets"
  user_assigned_identity_id = azurerm_user_assigned_identity.gitops.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = module.cluster.oidc_issuer_url
  subject                   = "system:serviceaccount:external-secrets:external-secrets"
}

# Get and List only. An access policy, not RBAC, for the reason in
# modules/cluster/key_vault.tf.
resource "azurerm_key_vault_access_policy" "gitops" {
  key_vault_id = module.cluster.key_vault_id
  tenant_id    = var.tenant_id
  object_id    = azurerm_user_assigned_identity.gitops.principal_id

  secret_permissions = [
    "Get",
    "List",
  ]
}

# The Forgejo admin password, generated the same way as the Postgres admin password in
# modules/postgres/key_vault.tf: never in state, never in the planfile. Bump
# value_wo_version to rotate it. gitops/schmeide/apps/forgejo-secrets.yaml projects it.
ephemeral "random_password" "forgejo_admin" {
  length      = 32
  special     = false
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
}

resource "azurerm_key_vault_secret" "forgejo_admin_password" {
  name             = "forgejo-admin-password"
  key_vault_id     = module.cluster.key_vault_id
  value_wo         = ephemeral.random_password.forgejo_admin.result
  value_wo_version = 1
  content_type     = "password for the Forgejo admin user"
  tags             = local.tags

  # The vault holds the only copy. Destroying the secret loses the password.
  lifecycle {
    prevent_destroy = true
  }
}

# The schmeide.app API's session-signing key and the password of its Postgres role,
# generated the same way and projected by gitops/schmeide/apps/schmeide-app-secrets.yaml.
# The role itself is created by hand inside Postgres (gitops/README.md, "The schmeide_app
# login"), so bumping the password's value_wo_version also needs an ALTER ROLE there.
ephemeral "random_password" "schmeide_app_auth" {
  length      = 64
  special     = false
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
}

resource "azurerm_key_vault_secret" "schmeide_app_auth_secret" {
  name             = "schmeide-app-auth-secret"
  key_vault_id     = module.cluster.key_vault_id
  value_wo         = ephemeral.random_password.schmeide_app_auth.result
  value_wo_version = 1
  content_type     = "SCHMEIDE_AUTH_SECRET for the schmeide.app API"
  tags             = local.tags

  # Destroying it signs every user out; keep it unless that is the intent.
  lifecycle {
    prevent_destroy = true
  }
}

# Alphanumeric only: it is spliced into DATABASE_URL unescaped.
ephemeral "random_password" "schmeide_app_postgres" {
  length      = 32
  special     = false
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
}

resource "azurerm_key_vault_secret" "schmeide_app_postgres_password" {
  name             = "schmeide-app-postgres-password"
  key_vault_id     = module.cluster.key_vault_id
  value_wo         = ephemeral.random_password.schmeide_app_postgres.result
  value_wo_version = 1
  content_type     = "password for schmeide_app@psql-schmeide"
  tags             = local.tags

  # The vault holds the only copy. Destroying the secret loses the password.
  lifecycle {
    prevent_destroy = true
  }
}

# The system pool is tainted CriticalAddonsOnly. These two releases are the non-addon
# pods that still belong there; everything Argo installs runs on the user pool.
locals {
  system_tolerations = [
    {
      key      = "CriticalAddonsOnly"
      operator = "Equal"
      value    = "true"
      effect   = "NoSchedule"
    },
  ]
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "2.15.0"
  namespace        = "external-secrets"
  create_namespace = true

  values = [
    yamlencode({
      serviceAccount = {
        name = "external-secrets"
        annotations = {
          "azure.workload.identity/client-id" = azurerm_user_assigned_identity.gitops.client_id
        }
      }
      # The webhook only projects a token into pods that carry this label.
      podLabels = {
        "azure.workload.identity/use" = "true"
      }
      global = {
        tolerations = local.system_tolerations
      }
      tolerations = local.system_tolerations
      webhook = {
        tolerations = local.system_tolerations
      }
      certController = {
        tolerations = local.system_tolerations
      }
    }),
  ]
}

# The Argo CD server stays ClusterIP. No domain is chosen, so there is no hostname to
# put it on; reach the UI with
#   kubectl -n argocd port-forward svc/argo-cd-argocd-server 8080:443
# The admin password is left unset so the chart generates one, kept out of git and out of
# terraform outputs.
resource "helm_release" "argo_cd" {
  name             = "argo-cd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "10.18.0"
  namespace        = "argocd"
  create_namespace = true

  # The ClusterSecretStore below needs the External Secrets CRDs.
  depends_on = [helm_release.external_secrets]

  values = [
    yamlencode({
      global = {
        tolerations = local.system_tolerations
      }
      # schmeide/iac is public, so Argo clones it with no repository credential.
      extraObjects = [
        {
          apiVersion = "external-secrets.io/v1"
          kind       = "ClusterSecretStore"
          metadata = {
            name = "schmeide"
          }
          spec = {
            provider = {
              azurekv = {
                authType = "WorkloadIdentity"
                vaultUrl = module.cluster.key_vault_uri
                serviceAccountRef = {
                  name      = "external-secrets"
                  namespace = "external-secrets"
                }
              }
            }
          }
        },
      ]
    }),
  ]
}

# Not in the argo-cd release: that chart installs the Application CRD, and Helm builds the
# whole manifest before the API server serves the new kind. This release runs after it.
resource "helm_release" "argocd_bootstrap" {
  name       = "argocd-bootstrap"
  chart      = "${path.module}/charts/argocd-bootstrap"
  namespace  = "argocd"
  depends_on = [helm_release.argo_cd]
}
