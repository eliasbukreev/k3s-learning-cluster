variable "vms" {
  description = "Virtual machines to create"

  type = map(object({
    memory = number
    vcpu   = number
    disk   = number
    ip     = string
    user   = string
    role = string
  }))

  validation {
    condition = alltrue([
      for vm in values(var.vms) :
      vm.memory > 0
    ])

    error_message = "VM memory must be greater than 0 MiB."
  }

  validation {
    condition = alltrue([
      for vm in values(var.vms) :
      vm.vcpu > 0
    ])

    error_message = "VM vCPU count must be greater than 0."
  }

  validation {
    condition = alltrue([
      for vm in values(var.vms) :
      vm.disk > 0
    ])

    error_message = "VM disk size must be greater than 0 GiB."
  }
  validation {
    condition = alltrue([
      for vm in values(var.vms) :
      can(cidrhost("${vm.ip}/32", 0))
    ])

    error_message = "VM IP address must be a valid IPv4 address."
  }

  validation {
    condition = alltrue([
      for vm in values(var.vms) :
      length(trimspace(vm.user)) > 0
    ])

    error_message = "VM user must not be empty."
  }

  validation {
    condition = alltrue([
      for vm in values(var.vms) :
      length(trimspace(vm.user)) > 0
    ])

    error_message = "VM user must not be empty."
  }

  validation {
  condition = alltrue([
    for vm in values(var.vms) :
    contains(["server", "agent"], vm.role)
  ])

  error_message = "VM role must be either \"server\" or \"agent\"."
}
}

variable "ssh_public_key" {
  description = "SSH public key installed for the VM user"
  type        = string

  validation {
    condition     = can(regex("^ssh-(ed25519|rsa|ecdsa) ", var.ssh_public_key))
    error_message = "ssh_public_key must be an OpenSSH public key."
  }
}

variable "network_gateway" {
  description = "IPv4 gateway and DNS server for the libvirt network"
  type        = string
  default     = "192.168.122.1"

  validation {
    condition     = can(cidrhost("${var.network_gateway}/32", 0))
    error_message = "network_gateway must be a valid IPv4 address."
  }
}
