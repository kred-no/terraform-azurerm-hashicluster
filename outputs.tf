output "out" {
  value = {
    pip    = one(azurerm_public_ip.MAIN[*])
    subnet = azurerm_subnet.MAIN
    nsg    = azurerm_network_security_group.MAIN
  }
}

output "sensitive" {
  sensitive = true

  value = {
    password = "SecretPassword"
  }
}