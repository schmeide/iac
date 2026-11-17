# The Azure side of the schmeide.app worker (schmeide/schmeide.app docs/stage2.md, "Deploy and
# hosting"): its workload identity, the identity ACR runs push app images as, and the
# provisioner password. The Kubernetes side is gitops/schmeide/schmeide-app/worker.yaml and
# gitops/schmeide/apps/schmeide-worker.yaml.

# The worker pod's identity, federated to its service account the way cert-manager's is in
# dns.tf. It schedules ACR runs and deletes an app's repositories.
resource "azurerm_user_assigned_identity" "worker" {
  name                = "id-schmeide-worker"
  resource_group_name = azurerm_resource_group.cluster.name
  location            = var.location
  tags                = local.tags

  lifecycle {
    replace_triggered_by = [terraform_data.tenant]
  }
}

resource "azurerm_federated_identity_credential" "worker" {
  name                      = "schmeide-worker"
  user_assigned_identity_id = azurerm_user_assigned_identity.worker.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = module.cluster.oidc_issuer_url
  subject                   = "system:serviceaccount:schmeide-app:schmeide-worker"
}

# What an ACR run pushes app images as. In ABAC repository mode a run has no push rights of
# its own; the registry carries this identity (registry.tf) so a run can name it.
resource "azurerm_user_assigned_identity" "acr_run" {
  name                = "id-schmeide-acr-run"
  resource_group_name = azurerm_resource_group.registry.name
  location            = var.location
  tags                = local.tags

  lifecycle {
    replace_triggered_by = [terraform_data.tenant]
  }
}

# Container Registry Repository Writer on apps/* only: every data action is allowed only for a
# repository under apps/. The trailing slash keeps it from matching apps-something.
resource "azurerm_role_assignment" "acr_run_apps" {
  scope                = module.registry.id
  role_definition_name = "Container Registry Repository Writer"
  principal_id         = azurerm_user_assigned_identity.acr_run.principal_id
  principal_type       = "ServicePrincipal"
  condition_version    = "2.0"
  condition            = <<-CONDITION
    (
     (
      !(ActionMatches{'Microsoft.ContainerRegistry/registries/repositories/content/read'})
      AND
      !(ActionMatches{'Microsoft.ContainerRegistry/registries/repositories/metadata/read'})
      AND
      !(ActionMatches{'Microsoft.ContainerRegistry/registries/repositories/content/write'})
      AND
      !(ActionMatches{'Microsoft.ContainerRegistry/registries/repositories/metadata/write'})
     )
     OR
     (
      @Request[Microsoft.ContainerRegistry/registries/repositories:name] StringStartsWithIgnoreCase 'apps/'
     )
    )
  CONDITION
}

# The ids the worker reads, as one JSON secret that gitops/schmeide/apps/schmeide-app-secrets.yaml
# expands into Secret schmeide-app/schmeide-app-azure. Not secrets, but this public repository
# does not commit them, so they travel the way cert-manager's do. Keys are the env var names.
resource "azurerm_key_vault_secret" "worker_azure" {
  name         = "schmeide-app-worker-azure"
  key_vault_id = module.cluster.key_vault_id
  content_type = "application/json; ids for the schmeide.app worker, not secret"
  tags         = local.tags
  value = jsonencode({
    AZURE_CLIENT_ID                = azurerm_user_assigned_identity.worker.client_id
    SCHMEIDE_AZURE_SUBSCRIPTION_ID = var.subscription_id
    SCHMEIDE_ACR_RESOURCE_GROUP    = azurerm_resource_group.registry.name
    SCHMEIDE_ACR_RUN_IDENTITY      = azurerm_user_assigned_identity.acr_run.client_id
    SCHMEIDE_ACR_RUN_IDENTITY_ID   = azurerm_user_assigned_identity.acr_run.id
  })

  # Terraform rewrites it in place when an id changes; removing it stops the worker starting.
  lifecycle {
    prevent_destroy = true
  }
}

# The schmeide_provisioner Postgres role's password, generated like the others in gitops.tf.
# The role is created by hand inside Postgres (gitops/README.md, "The schmeide_provisioner
# login"). Alphanumeric: it is spliced into a URL unescaped.
ephemeral "random_password" "schmeide_provisioner" {
  length      = 32
  special     = false
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
}

resource "azurerm_key_vault_secret" "schmeide_provisioner_password" {
  name             = "schmeide-app-provisioner-password"
  key_vault_id     = module.cluster.key_vault_id
  value_wo         = ephemeral.random_password.schmeide_provisioner.result
  value_wo_version = 1
  content_type     = "password for schmeide_provisioner@psql-schmeide"
  tags             = local.tags

  # The vault holds the only copy. Destroying the secret loses the password.
  lifecycle {
    prevent_destroy = true
  }
}
