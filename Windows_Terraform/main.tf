terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "3.99.0"
    }
  }
}

provider "azurerm" {
  subscription_id = "Your_Subscription_Id"
  client_id = "Your_Client_Id"
  client_secret = "Your_Client_Secret"
  tenant_id = "Your_Tenant_Id"
  features {}
}

locals {
  location = "Central India"
  resource_group = "app-grp"
  linux_resource_group = "linux-grp"
  linux_location = "South India"
}

resource "azurerm_resource_group" "app-grp" {
  name = local.resource_group
  location = local.location
}

resource "azurerm_virtual_network" "app_vnet" {
  name = "app-net"
  location = local.location
  resource_group_name = local.resource_group
  address_space       = ["10.0.0.0/16"]


  subnet {
    name = "SubnetA"
    address_prefix = "10.0.1.0/24"
  }
}

data "azurerm_subnet" "SubnetA" {
  name = "SubnetA"
  resource_group_name = local.resource_group
  virtual_network_name = azurerm_virtual_network.app_vnet.name
}

resource "azurerm_network_interface" "app_interface" {
  name = "app-netinterface"
  location = local.location
  resource_group_name = local.resource_group

  ip_configuration {
    name = "internal"
    subnet_id = data.azurerm_subnet.SubnetA.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.app_public_ip.id
  }

  depends_on = [ 
    azurerm_virtual_network.app_vnet,
    azurerm_public_ip.app_public_ip
   ]
}

resource "azurerm_public_ip" "app_public_ip" {
  name = "app-public-ip"
  resource_group_name = local.resource_group
  location = local.location
  allocation_method = "Static"
  
  depends_on = [ azurerm_resource_group.app-grp ]
}

resource "azurerm_windows_virtual_machine" "app_vm" {
  name = "app-vm"
  resource_group_name = local.resource_group
  location = local.location
  size = "Standard_D2s_v3"
  admin_username = "Enter_Your_Username"
  admin_password = "Enter_Your_Password"
  network_interface_ids = [ azurerm_network_interface.app_interface.id ]
  availability_set_id = azurerm_availability_set.app_avail_set.id

  os_disk {
    caching = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }

  depends_on = [ azurerm_network_interface.app_interface ]
}

resource "azurerm_availability_set" "app_avail_set" {
  name = "app-avail-set"
  location = local.location
  resource_group_name = local.resource_group
  platform_fault_domain_count = 3
  platform_update_domain_count = 3

  depends_on = [ azurerm_resource_group.app-grp ]
}

resource "azurerm_storage_account" "storage_account" {
    name = "appstorage710"
    resource_group_name = "app-grp"
    location = local.location
    account_tier = "Standard"
    account_replication_type = "LRS"
    allow_nested_items_to_be_public = true
    depends_on = [ azurerm_resource_group.app-grp ]
}

resource "azurerm_storage_container" "app_container" {
  name = "app-container"
  storage_account_name = azurerm_storage_account.storage_account.name
  container_access_type = "blob"
}

resource "azurerm_storage_blob" "app-IIS_Config" {
  name="IIS_Config.ps1"
  storage_account_name = azurerm_storage_account.storage_account.name
  storage_container_name = azurerm_storage_container.app_container.name 
  type = "Block"
  source = "IIS_Config.ps1"
  depends_on = [
    azurerm_storage_container.app_container
   ]
}

resource "azurerm_virtual_machine_extension" "app_extension" {
  name = "appvm-extension"
  virtual_machine_id = azurerm_windows_virtual_machine.app_vm.id
  type = "CustomScriptExtension"
  publisher = "Microsoft.Compute"
  type_handler_version = "1.10"

  depends_on = [ azurerm_storage_blob.app-IIS_Config ]

  settings = <<SETTINGS
    {
        "fileUris": ["https://${azurerm_storage_account.storage_account.name}.blob.core.windows.net/app-container/IIS_Config.ps1"],
          "commandToExecute": "powershell -ExecutionPolicy Unrestricted -file IIS_Config.ps1"     
    }
SETTINGS
}

resource "azurerm_network_security_group" "app-nsg" {
  name = "app-nsg"
  location = local.location
  resource_group_name = local.resource_group

  security_rule {
    name = "Allow_HTTP"
    priority = 200
    direction = "Inbound"
    access = "Allow"
    protocol = "Tcp"
    source_port_range = "*"
    destination_port_range = "80"
    source_address_prefix = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name = "Allow_RDP"
    priority = 100
    direction = "Inbound"
    access = "Allow"
    protocol = "Tcp"
    source_port_range = "*"
    destination_port_range = "3389"
    source_address_prefix = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name = "Allow_webDeploy"
    priority = 300
    direction = "Inbound"
    access = "Allow"
    protocol = "Tcp"
    source_port_range = "*"
    destination_port_range = "8172"
    source_address_prefix = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "app_nsg_association" {
  network_security_group_id = azurerm_network_security_group.app-nsg.id
  subnet_id = data.azurerm_subnet.SubnetA.id

  depends_on = [ 
    azurerm_network_security_group.app-nsg
   ]
}