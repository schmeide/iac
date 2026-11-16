# A user-assigned identity is bound to the tenant it was created in. Keying it on the
# tenant makes a tenant move a plan that replaces it, as in autobutler-org/iac. No
# prevent_destroy: it would block exactly that replacement, and an identity holds no data.
resource "terraform_data" "tenant" {
  input = data.azurerm_client_config.current.tenant_id
}

# User-assigned, so terraform can grant Network Contributor on the node subnet before the
# cluster exists. The kubelet identity is the one AKS creates; see registry.tf.
resource "azurerm_user_assigned_identity" "control" {
  name                = local.control_identity_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  lifecycle {
    replace_triggered_by = [terraform_data.tenant]
  }
}
