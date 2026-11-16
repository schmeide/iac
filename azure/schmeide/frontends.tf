# Generated frontends' static bundles. The CDN in front of them is not chosen yet; see
# modules/frontends/README.md. The account name is global across Azure and was not checked
# for availability.
resource "azurerm_resource_group" "frontends" {
  name     = "schmeide-frontends"
  location = var.location
  tags     = local.tags
}

module "frontends" {
  source = "../../modules/frontends"

  name                = "stschmeidefrontends"
  resource_group_name = azurerm_resource_group.frontends.name
  location            = var.location
  tags                = local.tags
}
