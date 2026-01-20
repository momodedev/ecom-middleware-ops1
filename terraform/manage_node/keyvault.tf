data "http" "myip" {
  count = var.deploy_mode != "separate" ? 1 : 0
  url = "https://ipinfo.io/ip" # https://ipv4.icanhazip.com
}


resource "azurerm_key_vault" "example" {
  count                           = var.deploy_mode != "separate" ? 1 : 0
  name                            = "control-keyvault"
  location                        = local.resource_group_location
  resource_group_name             = local.resource_group_name
  tenant_id                       = data.azurerm_client_config.current.tenant_id
  sku_name                        = "premium"
  soft_delete_retention_days      = 7
  rbac_authorization_enabled      = true
  public_network_access_enabled   = true  # Allow Terraform to access the Key Vault for reading/writing secrets
  network_acls {
    bypass = "AzureServices"
    default_action = "Deny"
    # Allow both the current detected IP and a fixed corporate egress IP to avoid firewall rejections when the public IP flips.
    ip_rules = [
      "${chomp(data.http.myip[0].response_body)}",
      "167.220.255.70",
      "167.220.233.6",
    ]
    virtual_network_subnet_ids = [local.control_subnet_id]
  }
}


resource "azurerm_role_assignment" "keyvault" {
  count                = var.deploy_mode != "separate" ? 1 : 0
  scope                = azurerm_key_vault.example[0].id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_virtual_machine.example.identity[0].principal_id
}

# Add delay to allow RBAC permissions to propagate before creating secrets
resource "time_sleep" "wait_for_rbac" {
  count           = var.deploy_mode != "separate" ? 1 : 0
  depends_on      = [azurerm_role_assignment.user, azurerm_role_assignment.keyvault]
  create_duration = "90s"
}

resource "azurerm_key_vault_secret" "example" {
  count        = var.deploy_mode != "separate" ? 1 : 0
  name         = "github-token"
  value        = var.github_token
  key_vault_id = azurerm_key_vault.example[0].id
  depends_on   = [time_sleep.wait_for_rbac, azurerm_key_vault.example]
}





