# Burstable B2s by default: 2 vCores, 4 GiB. B1ms is cheaper but allows about 50
# connections, and Temporal alone opens more than that across its four services and two
# stores. Sizing, the connection pooler and per-database limits are not decided
# (decisions/postgres.md in the planning repo); revisit sku_name before tenants share
# this server.
#
# The admin password is generated in key_vault.tf and sent with a write-only argument,
# so it is in neither state nor the planfile. To rotate it, bump
# administrator_password_version: the next apply generates a new one and writes it to
# both the server and the vault.
resource "azurerm_postgresql_flexible_server" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  version             = var.postgres_version
  sku_name            = var.sku_name
  storage_mb          = var.storage_mb
  auto_grow_enabled   = true

  delegated_subnet_id           = var.delegated_subnet_id
  private_dns_zone_id           = var.private_dns_zone_id
  public_network_access_enabled = false

  administrator_login               = var.administrator_login
  administrator_password_wo         = ephemeral.random_password.admin.result
  administrator_password_wo_version = var.administrator_password_version

  # Password auth, because Temporal and Forgejo connect with a password. Entra auth can
  # be added alongside later for people.
  authentication {
    password_auth_enabled         = true
    active_directory_auth_enabled = false
  }

  backup_retention_days        = var.backup_retention_days
  geo_redundant_backup_enabled = false

  tags = var.tags

  lifecycle {
    prevent_destroy = true
    # Azure picks an availability zone when none is given and reports it back. Without
    # this every plan would try to move the server to "no zone".
    ignore_changes = [zone]
  }
}

# Temporal's visibility schema creates the btree_gin extension. Azure only allows
# extensions listed in azure.extensions, so the schema job fails without this.
resource "azurerm_postgresql_flexible_server_configuration" "extensions" {
  name      = "azure.extensions"
  server_id = azurerm_postgresql_flexible_server.this.id
  value     = "BTREE_GIN"
}

# The platform's databases. Per-project databases are created by the platform at runtime,
# with a login each, and are not managed here.
resource "azurerm_postgresql_flexible_server_database" "platform" {
  for_each = toset(var.databases)

  name      = each.value
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"

  lifecycle {
    prevent_destroy = true
  }
}
