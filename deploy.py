#!/usr/bin/env python3

import json
import subprocess
import tempfile
import socket
import sys
import time
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parent
TERRAFORM_DIR = ROOT_DIR / "terraform"
ANSIBLE_DIR = ROOT_DIR / "ansible"
ANSIBLE_PLAYBOOK = ROOT_DIR / ".venv" / "bin" / "ansible-playbook"


def run(command, cwd):
    print(f"\n=== Running: {' '.join(command)} ===")

    subprocess.run(
        command,
        cwd=cwd,
        check=True,
    )


def terraform_apply():
    run(
        ["terraform", "apply", "-auto-approve"],
        TERRAFORM_DIR,
    )


def get_terraform_vms():
    result = subprocess.run(
        ["terraform", "output", "-json", "vms"],
        cwd=TERRAFORM_DIR,
        capture_output=True,
        text=True,
        check=True,
    )

    return json.loads(result.stdout)

def build_inventory(vms):
    inventory = {
        "all": {
            "children": {
                "k3s_nodes": {
                    "hosts": {}
                }
            }
        }
    }

    server_ip = None
    for vm_name, vm in vms.items():
        if vm["role"] == "server":
            if server_ip is not None:
                raise ValueError("Only one server allowed") 
            server_ip = vm["ip"]
        
    if server_ip is None:
        raise RuntimeError("No VM role 'server' is found")

    for vm_name, vm in vms.items():
        host_vars = {
            "ansible_host": vm["ip"],
            "ansible_user": vm["user"],
            "ansible_python_interpreter": "/usr/bin/python3"
        }

        if vm["role"] == "server":
            host_vars["k3s_control_node"] = True
            host_vars["k3s_registration_address"] = server_ip

        inventory["all"]["children"]["k3s_nodes"]["hosts"][vm_name] = host_vars

    return inventory

def validate_vms(vms):
    if not vms:
        raise RuntimeError("Terraform returned no VMs")

    for name, vm in vms.items():
        if not vm.get("ip"):
            raise RuntimeError(f"{name}: IP address is missing")

        if not vm.get("user"):
            raise RuntimeError(f"{name}: user is missing")
        
        if not vm.get("role"):
            raise RuntimeError(f"{name}: role is missing")

    print("\n=== VMs ===")

    for name, vm in vms.items():
        print(f"{name}: {vm['user']}@{vm['ip']}")

def wait_for_vms(vms, timeout=300):
    pending = {vm["ip"] for vm in vms.values()}
    deadline = time.monotonic() + timeout

    # Фаза 1: TCP poll порта 22
    while pending:
        for ip in list(pending):
            try:
                socket.create_connection((ip, 22), timeout=3).close()
                pending.discard(ip)
            except OSError:
                pass

        if pending and time.monotonic() > deadline:
            raise RuntimeError(f"VMs are unreachable via SSH: {', '.join(sorted(pending))}")

        if pending:
            time.sleep(5)

    print("All VMs are reachable via SSH")

    # Фаза 2: cloud-init отработал внутри каждой ВМ
    ssh_opts = [
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=10",
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
    ]

    for vm in sorted(vms.values(), key=lambda item: item["ip"]):
        ip = vm["ip"]
        cmd = [
            "ssh", *ssh_opts,
            f"{vm['user']}@{ip}",
            "command -v apt-get >/dev/null && sudo -n cloud-init status --wait",
        ]

        while True:
            result = subprocess.run(cmd, capture_output=True, text=True)

            if result.returncode == 0:
                print(f"{ip}: ready")
                break

            if time.monotonic() > deadline:
                raise RuntimeError(f"{ip}: VMs is not ready (cloud-init/apt)")

            time.sleep(5)

def run_ansible(inventory):
    with tempfile.NamedTemporaryFile(
        mode="w",
        suffix=".json",
        delete=False,
    ) as inventory_file:

        json.dump(
            inventory,
            inventory_file,
            indent=2,
        )

        inventory_path = inventory_file.name

    try:
        run(
            [
                str(ANSIBLE_PLAYBOOK),
                "-i",
                inventory_path,
                "site.yml",
            ],
            ANSIBLE_DIR,
        )

    finally:
        Path(inventory_path).unlink(missing_ok=True)


def main():
    print("=== Terraform ===")
    terraform_apply()

    print("\n=== Reading Terraform outputs ===")
    vms = get_terraform_vms()

    validate_vms(vms)

    print("\n=== Waiting for VMs ===")
    wait_for_vms(vms)

    print("\n=== Building Ansible inventory ===")
    inventory = build_inventory(vms)

    print("\n=== Ansible ===")
    run_ansible(inventory)

    print("\n=== Deployment complete ===")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit("\nInterrupted by user")
    except subprocess.CalledProcessError as e:
        sys.exit(f"\nCommand failed (exit {e.returncode}): {' '.join(e.cmd)}\nSee output above for details.")
    except (RuntimeError, ValueError) as e:
        sys.exit(f"\nDeployment failed: {e}")
