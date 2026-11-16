locals {
  # Applied to everything this root module manages.
  tags = merge(
    {
      managed_by   = "terraform"
      repo         = "schmeide/iac"
      subscription = "schmeide"
    },
    var.tags,
  )
}
