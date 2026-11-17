# The registry's name is global across Azure and was not checked for availability.
resource "azurerm_resource_group" "registry" {
  name     = "schmeide-registry"
  location = var.location
  tags     = local.tags
}

module "registry" {
  source = "../../modules/registry"

  name                = "schmeide"
  resource_group_name = azurerm_resource_group.registry.name
  location            = var.location
  identity_ids        = [azurerm_user_assigned_identity.acr_run.id]
  tags                = local.tags
}

# The push identity for schmeide/schmeide.app's CI. A user-assigned identity rather than
# a second federated credential on the app registration in bootstrap/, so the workflow
# that pushes images is not the identity that can apply this repo.
resource "azurerm_user_assigned_identity" "schmeide_app_push" {
  name                = "id-schmeide-app-push"
  resource_group_name = azurerm_resource_group.registry.name
  location            = var.location
  tags                = local.tags

  lifecycle {
    replace_triggered_by = [terraform_data.tenant]
  }
}

# Only pushes to main. The subject prefix is the immutable form GitHub mints for this
# repository, read with
#   gh api repos/schmeide/schmeide.app/actions/oidc/customization/sub
# on 2026-11-17. The classic repo:schmeide/schmeide.app prefix would never match.
resource "azurerm_federated_identity_credential" "schmeide_app_push" {
  name                      = "github-schmeide-app-main"
  user_assigned_identity_id = azurerm_user_assigned_identity.schmeide_app_push.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "repo:schmeide@357239714/schmeide.app@1459650460:ref:refs/heads/main"
}

# Container Registry Repository Writer (read and write, no delete), limited by the ABAC
# condition to the schmeide-app repository: every one of the role's four data actions is
# allowed only when the requested repository is schmeide-app. Without the condition this
# role would cover the whole registry. The shape is the one in the ACR docs,
# container-registry-rbac-abac-repository-permissions.
resource "azurerm_role_assignment" "schmeide_app_push" {
  scope                = module.registry.id
  role_definition_name = "Container Registry Repository Writer"
  principal_id         = azurerm_user_assigned_identity.schmeide_app_push.principal_id
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
      @Request[Microsoft.ContainerRegistry/registries/repositories:name] StringEqualsIgnoreCase 'schmeide-app'
     )
    )
  CONDITION
}
