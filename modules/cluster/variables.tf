variable "name" {
  description = "Cluster name, also its dns_prefix and the stem of the control-plane identity name."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group to create the cluster, identity and vault in. The caller owns its lifecycle."
  type        = string
}

variable "location" {
  description = "Azure region for every resource this module creates."
  type        = string
  default     = "centralus"
}

variable "kubernetes_version" {
  description = "Kubernetes major.minor. A minor alias lets automatic_upgrade_channel \"patch\" move patches without a diff. Check it is offered with: az aks get-versions -l <location> -o table"
  type        = string
  default     = "1.36"
}

variable "nodes_subnet_id" {
  description = "Subnet every node pool joins. The control-plane identity gets Network Contributor on it."
  type        = string
}

variable "pod_cidr" {
  description = "Azure CNI overlay pod CIDR. Each node takes a /24. Must not overlap the VNet, peered networks, or service_cidr."
  type        = string
  default     = "10.128.0.0/12"
}

variable "service_cidr" {
  description = "Kubernetes service CIDR. The DNS service takes the tenth address. Must not overlap the VNet or pod_cidr."
  type        = string
  default     = "172.16.0.0/16"
}

variable "system_vm_size" {
  description = "VM size of the single always-on system node."
  type        = string
  default     = "Standard_D2s_v6"
}

variable "user_vm_size" {
  description = "VM size of the autoscaled user pool that runs the platform and tenant workloads."
  type        = string
  default     = "Standard_D4as_v6"
}

variable "user_min_count" {
  description = "Minimum nodes in the user pool."
  type        = number
  default     = 1
}

variable "user_max_count" {
  description = "Maximum nodes in the user pool. Bounded by the subscription's vCPU quota for user_vm_size's family."
  type        = number
  default     = 2
}

variable "registry_id" {
  description = "ARM id of the container registry the kubelet pulls from."
  type        = string
}

variable "key_vault_name" {
  description = "Globally unique name of the platform Key Vault, 3-24 characters."
  type        = string
}

variable "github_actions_app_name" {
  description = "Display name of the app registration bootstrap/github-oidc.bash creates. It gets cluster admin and secret write access."
  type        = string
  default     = "github-actions-schmeide-iac"
}

variable "tags" {
  description = "Tags applied to every resource this module manages."
  type        = map(string)
  default     = {}
}
