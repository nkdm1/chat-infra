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
  subscription_id = get_env("ARM_SUBSCRIPTION_ID", "cf816eae-f4d9-4db4-bfa6-bda71e2cbf68")
  env             = basename(dirname(path_relative_to_include()))
}
