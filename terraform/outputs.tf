output "vms" {
  description = "VM connection information"

  value = {
    for name, vm in var.vms :
    name => {
      ip   = vm.ip
      user = vm.user
      role = vm.role
    }
  }
}

output "vm_names" {
  description = "Names of created virtual machines"

  value = keys(var.vms)
}
