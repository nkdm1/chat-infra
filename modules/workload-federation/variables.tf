variable "name" {
  description = "Name of the federated identity credential."
  type        = string
}

variable "identity_id" {
  description = "Resource ID of the application managed identity."
  type        = string
}

variable "oidc_issuer_url" {
  description = "OIDC issuer URL of this environment's AKS cluster."
  type        = string
}
