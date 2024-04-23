terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "3.99.0"
    }
  }
}

provider "azurerm" {
  subscription_id = "Enter_Your_Subscription_id"
  client_id = "Enter_Your_Client_id"
  client_secret = "Enter_Your_Client_Secret"
  tenant_id = "Enter_Your_Tenant_id"
  features {}
}

locals {
  location = "South India"
  resource_group_name = "linux-grp"
}

resource "azurerm_resource_group" "linux-grp" {
  name = "linux-grp"
  location = local.location
}


resource "azurerm_virtual_network" "linux_vnet" {
  name = "linux-vnet"
  resource_group_name = local.resource_group_name
  location = local.location
  address_space = ["10.0.0.0/16"]

  depends_on = [ azurerm_resource_group.linux-grp ]
}

resource "azurerm_subnet" "subnetB" {
  name = "SubnetB"
  resource_group_name = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.linux_vnet.name
  address_prefixes = ["10.0.1.0/24"]

  depends_on = [ azurerm_resource_group.linux-grp,
    azurerm_virtual_network.linux_vnet
   ]
}

# network interface's

resource "azurerm_public_ip" "public_ip1" {
  name = "pub-ip1"
  location = local.location
  resource_group_name = local.resource_group_name
  allocation_method = "Static"
}

resource "azurerm_network_interface" "linux_interface1" {
  name = "linux-net-interface1"
  location = local.location
  resource_group_name = local.resource_group_name

  ip_configuration {
    name = "internal"
    subnet_id = azurerm_subnet.subnetB.id
    public_ip_address_id = azurerm_public_ip.public_ip1.id
    private_ip_address_allocation = "Dynamic"
  }

  depends_on = [ 
    azurerm_virtual_network.linux_vnet,
   ]
}

resource "azurerm_public_ip" "public_ip2" {
  name = "pub-ip2"
  location = local.location
  resource_group_name = local.resource_group_name
  allocation_method = "Static"
}

resource "azurerm_network_interface" "linux_interface2" {
  name = "linux-net-interface2"
  location = local.location
  resource_group_name = local.resource_group_name

  ip_configuration {
    name = "internal"
    subnet_id = azurerm_subnet.subnetB.id
    public_ip_address_id = azurerm_public_ip.public_ip2.id
    private_ip_address_allocation = "Dynamic"
  }

  depends_on = [ 
    azurerm_virtual_network.linux_vnet,
   ]
}

#VM'S
resource "azurerm_linux_virtual_machine" "app_linux_vm1" {
  name = "app-linux-vm1"
  location = local.location
  resource_group_name = local.resource_group_name
  network_interface_ids = [ azurerm_network_interface.linux_interface1.id ]
  admin_username = "Enter_Username"
  admin_password = "Enter_Password"
  disable_password_authentication = false
  size = "Standard_D2s_v3"

  os_disk {
    storage_account_type = "Standard_LRS"
    caching = "ReadWrite"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
  depends_on = [ azurerm_network_interface.linux_interface1 ]
}

resource "azurerm_linux_virtual_machine" "app_linux_vm2" {
  name = "app-linux-vm2"
  location = local.location
  resource_group_name = local.resource_group_name
  network_interface_ids = [ azurerm_network_interface.linux_interface2.id ]
  
  admin_username = "Enter_Username"
  admin_password = "Enter_Password"
  disable_password_authentication = false
  size = "Standard_D2s_v3"

  os_disk {
    storage_account_type = "Standard_LRS"
    caching = "ReadWrite"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
  depends_on = [ azurerm_network_interface.linux_interface2 ]
}



#lb

resource "azurerm_public_ip" "load_pub_id" {
  name = "load-public-ip"
  location = local.location
  resource_group_name = local.resource_group_name
  allocation_method = "Static"
  sku = "Standard"
}

resource "azurerm_lb" "load_balancer" {
  name = "load-balancer"
  location = local.location
  resource_group_name = local.resource_group_name
  sku = "Standard"

  frontend_ip_configuration {
    name = "frontend-ip"
    public_ip_address_id = azurerm_public_ip.load_pub_id.id
  }

  depends_on = [ 
    azurerm_public_ip.load_pub_id
   ]
}

resource "azurerm_lb_backend_address_pool" "PoolA" {
  name = "PoolA"
  loadbalancer_id = azurerm_lb.load_balancer.id

  depends_on = [ azurerm_lb.load_balancer ]
}

resource "azurerm_lb_backend_address_pool_address" "linux_vm_1" {
  name = "linux-vm-1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.PoolA.id
  virtual_network_id = azurerm_virtual_network.linux_vnet.id
  ip_address = azurerm_network_interface.linux_interface1.private_ip_address
  
  depends_on = [ azurerm_lb_backend_address_pool.PoolA ]
}

resource "azurerm_lb_backend_address_pool_address" "linux_vm_2" {
  name = "linux-vm-2"
  backend_address_pool_id = azurerm_lb_backend_address_pool.PoolA.id
  virtual_network_id = azurerm_virtual_network.linux_vnet.id
  ip_address = azurerm_network_interface.linux_interface2.private_ip_address

  depends_on = [ azurerm_lb_backend_address_pool.PoolA ]
}

resource "azurerm_lb_probe" "health_probeA" {
  name = "health-probeA"
  port = 80
  loadbalancer_id = azurerm_lb.load_balancer.id

  depends_on = [ azurerm_lb.load_balancer ]
}
 
resource "azurerm_lb_rule" "RuleA" {
  name = "RuleA"
  loadbalancer_id = azurerm_lb.load_balancer.id
  frontend_port = 80
  backend_port = 80
  protocol = "Tcp"
  frontend_ip_configuration_name = "frontend-ip"
  probe_id = azurerm_lb_probe.health_probeA.id
  backend_address_pool_ids = [ azurerm_lb_backend_address_pool.PoolA.id ]
  depends_on = [ 
    azurerm_lb.load_balancer,
    azurerm_lb_probe.health_probeA
   ]
}