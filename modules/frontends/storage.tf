# Private for now. Shared keys are off, so writers authenticate with Entra ID, and nested
# public access is off, so no container can be opened by accident. How visitors reach a
# bundle is the CDN's job, and that choice (static website endpoint, or a private origin
# the CDN authenticates to) is made together with the CDN. Nothing here serves traffic
# yet. Public network access stays on so a CDN origin and the platform's deploy step can
# reach the account without a private endpoint.
resource "azurerm_storage_account" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  access_tier              = "Hot"

  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  public_network_access           = "Enabled"

  blob_properties {
    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  tags = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

# One container, one prefix per build: <tenant>/<project>/<build>/. A CDN route then maps
# a preview hostname to one prefix, and a deploy is a new prefix plus a route change,
# never an in-place overwrite. See README.md.
resource "azurerm_storage_container" "bundles" {
  name                  = "bundles"
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"

  lifecycle {
    prevent_destroy = true
  }
}
