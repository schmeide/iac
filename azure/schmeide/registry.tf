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
  tags                = local.tags
}
