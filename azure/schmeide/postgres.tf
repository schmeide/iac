# The shared Postgres server and the platform's databases:
#
#   schmeide              the customer database (tenants, projects, work items, usage)
#   temporal              Temporal's default store
#   temporal_visibility   Temporal's visibility store
#   forgejo               Forgejo
#
# Per-project databases are created by the platform at runtime, not here. The server name
# is global across Azure and was not checked for availability. The FQDN it produces is
# also written into gitops/schmeide/temporal/values.yaml and forgejo/values.yaml; change
# all three together.
resource "azurerm_resource_group" "postgres" {
  name     = "schmeide-postgres"
  location = var.location
  tags     = local.tags
}

module "postgres" {
  source = "../../modules/postgres"

  name                = "psql-schmeide"
  resource_group_name = azurerm_resource_group.postgres.name
  location            = var.location
  delegated_subnet_id = module.network.postgres_subnet_id
  private_dns_zone_id = module.network.postgres_private_dns_zone_id
  key_vault_id        = module.cluster.key_vault_id

  databases = [
    "schmeide",
    "temporal",
    "temporal_visibility",
    "forgejo",
  ]

  tags = local.tags
}
