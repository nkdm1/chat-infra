resource "azurerm_federated_identity_credential" "this" {
  name                      = var.name
  user_assigned_identity_id = var.identity_id
  issuer                    = var.oidc_issuer_url
  audience                  = ["api://AzureADTokenExchange"]
  subject                   = "system:serviceaccount:chat:chat-app"
}
