# admin_enabled is the credential switch: the admin user is what shared keys would belong
# to, and every caller authenticates with Entra ID instead. Public network access stays
# on; there is no private endpoint yet.
#
# role_assignment_mode AbacRepositoryPermissions, as in autobutler-org/iac. Pull and push
# are then granted per repository with the Container Registry Repository roles, which is
# what lets one tenant's build push only to that tenant's repositories later. AcrPull is
# not honored in this mode.
resource "azurerm_container_registry" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  admin_enabled       = false

  public_network_access_enabled = true
  role_assignment_mode          = "AbacRepositoryPermissions"

  # User-assigned identities ACR Tasks runs may authenticate as. A run can name only an
  # identity the registry carries.
  dynamic "identity" {
    for_each = length(var.identity_ids) > 0 ? [1] : []
    content {
      type         = "UserAssigned"
      identity_ids = var.identity_ids
    }
  }

  tags = var.tags

  lifecycle {
    prevent_destroy = true
  }
}
