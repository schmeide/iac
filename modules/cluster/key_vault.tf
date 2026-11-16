# The platform's Key Vault. Workloads in the cluster read it through External Secrets
# (azure/schmeide/gitops.tf). It holds the Postgres admin password and the Forgejo admin
# password, which terraform writes with write-only arguments so neither value lands in
# state or in the planfile.
#
# Access policies rather than Azure RBAC, as in autobutler-org/iac. CI applies as a
# Contributor, which can write access policies (they are part of the vault resource) but
# cannot create Key Vault data-plane role assignments: those roles are not in the
# bootstrap script's allow list. Policies added by hand, such as one a person gives
# themselves to read a secret, are left alone. The vault declares none inline.
resource "azurerm_key_vault" "this" {
  name                = var.key_vault_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  rbac_authorization_enabled = false
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  tags = var.tags

  # The generated passwords exist nowhere else. Recreating the vault loses them.
  lifecycle {
    prevent_destroy = true
  }
}

# The apply identity writes the generated secrets. Get to read their metadata back on a
# refresh, Set to write, Delete and Recover so a destroy or a re-create of a soft-deleted
# secret does not wedge the apply.
resource "azurerm_key_vault_access_policy" "github_actions" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azuread_service_principal.github_actions.object_id

  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete",
    "Recover",
  ]
}
