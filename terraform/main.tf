# -------------------------------------------------------------------
# Debian 13 base image -> Terraform-managed libvirt volume
# -------------------------------------------------------------------
resource "libvirt_volume" "debian13_base" {
  name = "debian13-base.qcow2"
  pool = "default"

  target = {
    format = {
      type = "qcow2"
    }
  }

  create = {
    content = {
      url = "/var/lib/libvirt/images/base/debian-13-genericcloud-amd64.qcow2"
    }
  }
}

resource "libvirt_volume" "debian13" {
  for_each = var.vms

  name = "${each.key}.qcow2"
  pool = "default"

  capacity      = each.value.disk
  capacity_unit = "GiB"

  target = {
    format = {
      type = "qcow2"
    }
  }

  backing_store = {
    path = libvirt_volume.debian13_base.path

    format = {
      type = "qcow2"
    }
  }

}

# -------------------------------------------------------------------
# Cloud-init seed
# -------------------------------------------------------------------

resource "libvirt_cloudinit_disk" "debian13" {
  for_each = var.vms

  name = "${each.key}-cloudinit.iso"

  meta_data = <<-EOF
    instance-id: ${each.key}
    local-hostname: ${each.key}
  EOF


  user_data = templatefile("${path.module}/cloud-init.yaml", {
    user           = each.value.user
    ssh_public_key = var.ssh_public_key
  })

  network_config = <<-EOF
  version: 2

  ethernets:
    enp1s0:
      addresses:
        - ${each.value.ip}/24
      dhcp4: false
      dhcp6: false
      routes:
        - to: 0.0.0.0/0
          via: ${var.network_gateway}
      nameservers:
        addresses:
          - ${var.network_gateway}
EOF
}

# -------------------------------------------------------------------
# Put cloud-init ISO into libvirt storage pool
# -------------------------------------------------------------------

resource "libvirt_volume" "debian13_cloudinit" {
  for_each = var.vms

  name = "${each.key}-cloudinit.iso"
  pool = "default"

  create = {
    content = {
      url = libvirt_cloudinit_disk.debian13[each.key].path
    }
  }

  target = {
    format = {
      type = "iso"
    }
  }

  depends_on = [
    libvirt_cloudinit_disk.debian13
  ]
}

# -------------------------------------------------------------------
# Debian 13 VM
# -------------------------------------------------------------------

resource "libvirt_domain" "vm" {
  for_each = var.vms

  name   = each.key
  type   = "kvm"
  memory = each.value.memory
  vcpu   = each.value.vcpu

  memory_unit = "MiB"

  running   = true
  autostart = true

  # Настройка для загрузки образа через UEFI
  features = {
    acpi = true
  }

  # Debian GenericCloud у нас успешно загружался именно через UEFI.
  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
    firmware     = "efi"

    boot_devices = [
      {
        dev = "hd"
      }
    ]
  }

  devices = {
    # ---------------------------------------------------------------
    # Debian system disk + cloud-init ISO
    # ---------------------------------------------------------------

    disks = [
      {
        device = "disk"

        driver = {
          name = "qemu"
          type = "qcow2"
        }

        source = {
          file = {
            file = libvirt_volume.debian13[each.key].path
          }
        }

        target = {
          dev = "vda"
          bus = "virtio"
        }
      },

      {
        device = "cdrom"

        source = {
          file = {
            file = libvirt_volume.debian13_cloudinit[each.key].path
          }
        }

        target = {
          dev = "sda"
          bus = "sata"
        }

        read_only = true
      }
    ]

    # ---------------------------------------------------------------
    # libvirt default network
    # ---------------------------------------------------------------

    interfaces = [
      {
        type = "network"

        model = {
          type = "virtio"
        }

        source = {
          network = {
            network = "default"
          }
        }
      }
    ]

    # ---------------------------------------------------------------
    # Serial console
    # ---------------------------------------------------------------

    serials = [
      {
        type = "pty"

        target = {
          type = "isa-serial"
          port = 0
        }
      }
    ]

    consoles = [
      {
        type = "pty"

        target = {
          type = "serial"
          port = 0
        }
      }
    ]

    # ---------------------------------------------------------------
    # QEMU Guest Agent channel
    # ---------------------------------------------------------------

    channels = [
      {
        type = "unix"

        target = {
          virt_io = {
            name = "org.qemu.guest_agent.0"
          }
        }
      }
    ]
  }
}
