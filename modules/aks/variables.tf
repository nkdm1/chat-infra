variable "aks_name" {
  type        = string
  description = "Name of the AKS cluster."
}

variable "location" {
  type        = string
  description = "Azure region for the cluster."
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group containing the cluster."
}

variable "dns_prefix" {
  type        = string
  description = "DNS prefix for the AKS-managed Kubernetes API endpoint."
}

variable "aks_subnet_id" {
  type        = string
  description = "Resource ID of the dedicated VNet subnet for AKS nodes."
}

variable "acr_id" {
  type        = string
  description = "Resource ID of the ACR to grant image-pull access to."
}

variable "node_vm_size" {
  type        = string
  description = "VM size for the AKS system node pool."
  default     = "Standard_D2als_v7"
}

variable "node_min_count" {
  type        = number
  description = "Minimum number of system-pool nodes."
  default     = 1

  validation {
    condition     = var.node_min_count >= 1 && var.node_min_count <= 2
    error_message = "node_min_count must be between 1 and 2."
  }
}

variable "node_max_count" {
  type        = number
  description = "Maximum number of system-pool nodes; this module caps it at two."
  default     = 2

  validation {
    condition     = var.node_max_count >= 1 && var.node_max_count <= 2
    error_message = "node_max_count must be between 1 and 2."
  }
}

variable "pod_cidr" {
  type        = string
  description = "Non-overlapping CIDR for Azure CNI Overlay pods."
}

variable "service_cidr" {
  type        = string
  description = "Non-overlapping CIDR for Kubernetes services."
}

variable "dns_service_ip" {
  type        = string
  description = "DNS service IP inside service_cidr."
}

variable "env" {
  type    = string
  default = ""
  validation {
    condition     = length(trimspace(var.env)) > 0
    error_message = "var.env must not be empty"
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}

locals {
  tags = merge(var.tags, {
    env = var.env
  })
}
