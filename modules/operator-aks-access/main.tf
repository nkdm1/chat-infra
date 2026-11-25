terraform {
  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
  }
}

# Read only the cluster properties needed to locate its system-managed DNS zone.
# Do not request or export any kubeconfig or client credentials here.
data "azapi_resource" "aks" {
  type        = "Microsoft.ContainerService/managedClusters@2025-09-01"
  resource_id = var.aks_id
  response_export_values = [
    "properties.privateFQDN",
    "properties.nodeResourceGroup",
    "properties.apiServerAccessProfile.privateDNSZone",
  ]
}

locals {
  fqdn_parts = split(".", data.azapi_resource.aks.output.properties.privateFQDN)
  zone_name  = join(".", slice(local.fqdn_parts, 1, length(local.fqdn_parts)))
}

data "azurerm_private_dns_zone" "aks" {
  name                = local.zone_name
  resource_group_name = data.azapi_resource.aks.output.properties.nodeResourceGroup

  lifecycle {
    precondition {
      condition     = lower(data.azapi_resource.aks.output.properties.apiServerAccessProfile.privateDNSZone) == "system"
      error_message = "This stack only supports an AKS system-managed private DNS zone."
    }
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "operator" {
  name                 = var.dns_link_name
  private_dns_zone_id  = data.azurerm_private_dns_zone.aks.id
  virtual_network_id   = var.operator_virtual_network_id
  registration_enabled = false
}

resource "azurerm_role_assignment" "cluster_admin" {
  scope                = var.aks_id
  role_definition_name = "Azure Kubernetes Service Cluster Admin Role"
  principal_id         = var.operator_principal_id
}
