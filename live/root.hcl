remote_state {
  backend = "azurerm"
  config = {
    storage_account_name     = "chatopentofu"
    container_name           = "tfstate"
    resource_group_name      = "tofu-rg"
    subscription_id          = local.subscription_id
    location                 = "polandcentral"
    allow_blob_public_access = false

    key                   = "${path_relative_to_include()}/tofu.tfstate"
    use_azuread_auth      = true
    assign_blob_data_role = true

  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite"
  }
}
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "azurerm" {
  features {}
  subscription_id = "${local.subscription_id}"
}
EOF
}

locals {
  # Require a non-empty Azure subscription ID rather than falling back to a default.
  subscription_id = regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", get_env("ARM_SUBSCRIPTION_ID"))
  env             = basename(dirname(path_relative_to_include()))
}
