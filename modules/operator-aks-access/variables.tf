variable "aks_id" {
  description = "Resource ID of the private AKS cluster."
  type        = string
}

variable "operator_principal_id" {
  description = "Principal ID of the temporary operator VM managed identity."
  type        = string
}

variable "operator_virtual_network_id" {
  description = "Resource ID of the operator VNet to link to AKS private DNS."
  type        = string
}

variable "dns_link_name" {
  description = "Name of the temporary AKS private DNS VNet link."
  type        = string
}
