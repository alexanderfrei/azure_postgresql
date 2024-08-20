locals {
  vnet_injection_rg_name      = ""
  vnet_injection_vnet_name    = "" 
  vnet_injection_subnet_name  = ""
  hub_subscription_id         = ""
  spoke_subscription_id       = ""
}


provider "azurerm" {                # assuming that you connect with SPOKE subscription first to create the PostgreSQL DB
  features {}
}

# default provider
provider "azurerm" {
  subscription_id = local.spoke_subscription_id
  features {}
  alias = "spoke_subscription"
}
 
provider "azurerm" {
  subscription_id = local.hub_subscription_id
  features {}
  alias = "hub_subscription"
}

resource "azurerm_resource_group" "example" {
  name     = "example-resources"
  location = "West Europe"
}

resource "azurerm_virtual_network" "example" {
  name                = "example-vn"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "example" {
  name                 = "example-sn"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example.name
  address_prefixes     = ["10.0.2.0/24"]
  service_endpoints    = ["Microsoft.Storage"]
  delegation {
    name = "fs"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"                # subnet must not contain any other resource/s! It must be delegated to Postgresql
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}


resource "azurerm_private_dns_zone" "example" {
  name                = "name1.postgres.database.azure.com"             # you can create name1.postgres.database.azure.com or name2.postgres.database.azure.com
  resource_group_name = azurerm_resource_group.example.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "example" {
  name                  = "exampleVnetZone.com"
  private_dns_zone_name = azurerm_private_dns_zone.example.name
  virtual_network_id    = azurerm_virtual_network.example.id
  resource_group_name   = azurerm_resource_group.example.name
  depends_on            = [azurerm_subnet.example]
#  provider              = azurerm.hub_subscription                      # in case you want to create vnet link to a vnet in HUB subscription
}

resource "azurerm_postgresql_flexible_server" "example" {
  name                          = "example-psqlflexibleserver"
  resource_group_name           = azurerm_resource_group.example.name
  location                      = azurerm_resource_group.example.location
  version                       = "12"
  delegated_subnet_id           = azurerm_subnet.example.id                 # this is the parameter where you inject to a vnet and got the private ip address from the subnet
  private_dns_zone_id           = azurerm_private_dns_zone.example.id
  public_network_access_enabled = false
  administrator_login           = "<PSQL_USERNAME>"
  administrator_password        = "<PSQL_PW>"
  zone                          = "1"

  storage_mb   = 32768
  storage_tier = "P4"

  sku_name   = "B_Standard_B1ms"
  depends_on = [azurerm_private_dns_zone_virtual_network_link.example]

}