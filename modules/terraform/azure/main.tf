locals {
  network_security_rules_map = {
    "SSH" = {
      name                   = "SSH"
      priority               = 1001
      destination_port_range = 22
    },
    "HTTP" = {
      name                   = "HTTP"
      priority               = 1002
      destination_port_range = 80
    },
    "HTTPS" = {
      name                   = "HTTPS"
      priority               = 1003
      destination_port_range = 443
    }
  }
  resource_group_name = "compete-labs-${formatdate("MM-DD-YYYY-hh-mm-ss", timestamp())}"
  tags = {
    "Name"              = "compete-labs",
    "deletion_due_time" = timeadd(timestamp(), "2h")
  }
}

data "azurerm_client_config" "config" {}

resource "azurerm_resource_group" "rg" {
  name     = local.resource_group_name
  location = "eastus2"
  tags     = local.tags
}

resource "azurerm_public_ip" "pip" {
  name                = "chatbot-server-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_virtual_network" "vnet" {
  name                = "chatbot-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags
}

resource "azurerm_subnet" "subnet" {
  name                 = "chatbot-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_network_security_group" "nsg" {
  name                = "chatbot-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags
}

resource "azurerm_subnet_network_security_group_association" "subnet-nsg-associations" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_network_security_rule" "ssh" {
  for_each                    = local.network_security_rules_map
  name                        = each.value.name
  priority                    = each.value.priority
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = each.value.destination_port_range
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  network_security_group_name = azurerm_network_security_group.nsg.name
  resource_group_name         = azurerm_resource_group.rg.name
}

resource "azurerm_network_interface" "nic" {
  name                = "chatbot-server-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
  tags = local.tags
}

resource "azurerm_linux_virtual_machine" "linux_vm" {
  name                = "chatbot-server"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_NC96ads_A100_v4"
  admin_username      = "ubuntu"
  network_interface_ids = [
    azurerm_network_interface.nic.id,
  ]
  zone = "2"

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 256
  }

  source_image_reference {
    publisher = "microsoft-dsvm"
    offer     = "ubuntu-hpc"
    sku       = "2204"
    version   = "latest"
  }

  admin_ssh_key {
    username   = "ubuntu"
    public_key = file(var.ssh_public_key)
  }
  tags = local.tags
}
