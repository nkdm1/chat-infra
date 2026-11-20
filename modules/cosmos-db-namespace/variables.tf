variable "account_id" {
  type        = string
  description = "Resource ID of the shared Cosmos DB account."
}

variable "account_name" {
  type        = string
  description = "Name of the shared Cosmos DB account."
}

variable "endpoint" {
  type        = string
  description = "Endpoint of the shared Cosmos DB account."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group containing the shared Cosmos DB account."
}

variable "database_name" {
  type        = string
  description = "Environment-specific Cosmos DB SQL database name."
}

variable "container_name" {
  type        = string
  description = "Messages container name."
  default     = "messages"
}

variable "throughput" {
  type        = number
  description = "Shared manual throughput for this environment's SQL database. Keep at 400 RU/s for the free-tier design."
  default     = 400

  validation {
    condition     = var.throughput >= 400 && var.throughput <= 1000 && var.throughput % 100 == 0
    error_message = "throughput must be between 400 and 1000 RU/s in increments of 100."
  }
}

variable "app_principal_id" {
  type        = string
  description = "Optional workload identity object ID to grant Cosmos DB Built-in Data Contributor at this database scope."
  default     = null
  nullable    = true
}
