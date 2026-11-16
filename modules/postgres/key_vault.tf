# The admin password, generated where it is used, as autobutler-org/iac prefers. The
# ephemeral resource produces a value terraform never stores. It goes to the server and to
# the vault through write-only arguments in the same apply, and on later applies neither
# is sent again until administrator_password_version changes.
#
# The vault copy is what External Secrets projects into the cluster for Temporal and
# Forgejo, and what a person reads to connect by hand.
ephemeral "random_password" "admin" {
  length      = 32
  special     = false
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
}

resource "azurerm_key_vault_secret" "admin_password" {
  name             = var.key_vault_secret_name
  key_vault_id     = var.key_vault_id
  value_wo         = ephemeral.random_password.admin.result
  value_wo_version = var.administrator_password_version
  content_type     = "password for ${var.administrator_login}@${var.name}"
  tags             = var.tags

  # The vault holds the only copy. Destroying the secret loses the password.
  lifecycle {
    prevent_destroy = true
  }
}
