# The VNet the cluster and the Postgres server share. Address plan in
# modules/network/README.md.
resource "azurerm_resource_group" "network" {
  name     = "schmeide-network"
  location = var.location
  tags     = local.tags
}

module "network" {
  source = "../../modules/network"

  name_prefix         = "schmeide"
  resource_group_name = azurerm_resource_group.network.name
  location            = var.location
  tags                = local.tags
}
