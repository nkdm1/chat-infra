variable "name" {
  description = "Name of the GitHub image publisher identity."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group containing the identity."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "registry_id" {
  description = "Registry resource ID for the AcrPush assignment."
  type        = string
}

variable "github_repository" {
  description = "GitHub owner/repository trusted to publish images."
  type        = string
}

variable "github_branch" {
  description = "Only this branch can exchange GitHub OIDC tokens."
  type        = string
}

variable "env" {
  description = "Environment name."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

locals {
  tags = merge(var.tags, { env = var.env })
}
