# The one AKS cluster: platform, Temporal, Forgejo, sandbox pods, check Jobs, and a
# namespace per tenant. Also the platform Key Vault. modules/cluster/README.md has the
# details.
#
# BEFORE THE FIRST APPLY, ./bootstrap/github-oidc.bash create has to have run. Contributor
# cannot write role assignments, and this module's role assignments fail until that
# script has granted a constrained Role Based Access Control Administrator.
#
# The Key Vault name is global across Azure and was not checked for availability.
resource "azurerm_resource_group" "cluster" {
  name     = "schmeide-cluster"
  location = var.location
  tags     = local.tags
}

module "cluster" {
  source = "../../modules/cluster"

  name                = "schmeide"
  resource_group_name = azurerm_resource_group.cluster.name
  location            = var.location
  nodes_subnet_id     = module.network.nodes_subnet_id
  registry_id         = module.registry.id
  key_vault_name      = "kv-schmeide"
  tags                = local.tags
}
