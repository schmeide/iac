# The apply identity, looked up by the app registration name bootstrap/github-oidc.bash
# creates. data.azurerm_client_config would be whoever ran terraform, and a local plan
# would then grant that person cluster admin. The object id is the service principal.
data "azuread_service_principal" "github_actions" {
  display_name = var.github_actions_app_name
}

# Free tier: this starts as a demo and does not need the uptime SLA. Move to Standard
# before tenants depend on it.
#
# The API server is public and has no authorized IP ranges. GitHub-hosted Actions
# runners have no stable egress, and the Helm provider has to reach the API from those
# runners. Entra is the lock, which is why local accounts are off.
resource "azurerm_kubernetes_cluster" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  dns_prefix          = var.name
  kubernetes_version  = var.kubernetes_version
  sku_tier            = "Free"

  # Named rather than the default MC_<rg>_<cluster>_<location>, as in autobutler-org/iac.
  node_resource_group = "${var.resource_group_name}-nodes"

  # Holds the minor chosen in kubernetes_version while Azure applies its patches.
  automatic_upgrade_channel = "patch"

  local_account_disabled    = true
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # linux_profile is omitted: with local accounts disabled there is no local admin for an
  # SSH key to log in as.

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.control.id]
  }

  azure_active_directory_role_based_access_control {
    tenant_id          = data.azurerm_client_config.current.tenant_id
    azure_rbac_enabled = true
  }

  # azurerm 5.11+ requires this block. Manual, and no automatic default pools: Auto would
  # let AKS create node pools this module does not describe.
  node_provisioning_profile {
    mode               = "Manual"
    default_node_pools = "None"
  }

  # Azure CNI overlay with Cilium for the dataplane and for network policy. Pods get
  # addresses from pod_cidr, not from the node subnet, so many pods per tenant cannot
  # exhaust the VNet. Each node takes a /24 of pod_cidr and runs up to 250 pods. The
  # /12 default holds 4,096 nodes, temporary rotation pools included. Sizing is in
  # modules/network/README.md.
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    pod_cidr            = var.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = cidrhost(var.service_cidr, 10)
  }

  # One small node, always on. It runs AKS addons, Argo CD, and External Secrets.
  # CriticalAddonsOnly keeps every other pod off it. Changing the flag cycles this pool,
  # so it needs a temporary name.
  default_node_pool {
    name                         = "system"
    vm_size                      = var.system_vm_size
    node_count                   = 1
    os_disk_size_gb              = 32
    os_disk_type                 = "Managed"
    vnet_subnet_id               = var.nodes_subnet_id
    only_critical_addons_enabled = true
    temporary_name_for_rotation  = "systemtmp"
    tags                         = var.tags

    # AKS writes these on create. Leaving the block unset plans them back to null.
    upgrade_settings {
      drain_timeout_in_minutes      = 0
      max_surge                     = "10%"
      node_soak_duration_in_minutes = 0
    }
  }

  tags = var.tags

  # The identity id referenced above is not a dependency on its Network Contributor
  # assignment, so this depends_on is load-bearing.
  depends_on = [
    azurerm_role_assignment.control_network,
  ]

  lifecycle {
    prevent_destroy = true
  }
}

# Everything that is not an addon: the platform, Temporal, Forgejo, the ingress
# controller, sandbox pods, check Jobs, and tenant backends. Autoscaled between small
# bounds for the demo. Raise user_max_count with the subscription's vCPU quota; see
# README.md.
#
# No node_count. With autoscaling the provider uses min_count as the initial count.
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = var.user_vm_size
  mode                  = "User"
  vnet_subnet_id        = var.nodes_subnet_id

  auto_scaling_enabled = true
  min_count            = var.user_min_count
  max_count            = var.user_max_count

  os_disk_size_gb             = 64
  os_disk_type                = "Managed"
  temporary_name_for_rotation = "usertmp"

  # AKS writes these on create. Leaving the block unset plans them back to null.
  upgrade_settings {
    drain_timeout_in_minutes      = 0
    max_surge                     = "10%"
    node_soak_duration_in_minutes = 0
  }

  tags = var.tags
}

# Cluster User is what kubelogin needs to get an API token. RBAC Cluster Admin is what
# CI needs to install Argo CD and External Secrets. Both are scoped to this cluster.
# principal_type is set because the bootstrap grant that lets CI create these
# assignments is constrained.
resource "azurerm_role_assignment" "github_actions_cluster_user" {
  scope                = azurerm_kubernetes_cluster.this.id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = data.azuread_service_principal.github_actions.object_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "github_actions_cluster_admin" {
  scope                = azurerm_kubernetes_cluster.this.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azuread_service_principal.github_actions.object_id
  principal_type       = "ServicePrincipal"
}
