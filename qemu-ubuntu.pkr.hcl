packer {
  required_plugins {
    qemu = {
      version = "~> 1"
      source  = "github.com/hashicorp/qemu"
    }
    ansible = {
      version = "~> 1"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

variable "ssh_username" {
  type    = string
  default = "packer"
}

variable "ssh_password" {
  type    = string
  default = "packer"
}

variable "vm_name" {
  type    = string
  default = "ubuntu-20.04-x86_64"
}

source "file" "user_data" {
  content = <<EOF
#cloud-config
ssh_pwauth: True
users:
  - name: ${var.ssh_username}
    lock_passwd: false
    plain_text_passwd: ${var.ssh_password}
    sudo: ALL=(ALL) NOPASSWD:ALL
EOF
  target  = "boot-${var.vm_name}/user-data"
}

source "file" "meta_data" {
  content = <<EOF
instance-id: ubuntu-microk8s
local-hostname: ubuntu-microk8s
EOF
  target  = "boot-${var.vm_name}/meta-data"
}

build {
  sources = ["sources.file.user_data", "sources.file.meta_data"]

  provisioner "shell-local" {
    inline = ["genisoimage -output boot-${var.vm_name}/cidata.iso -input-charset utf-8 -volid cidata -joliet -r boot-${var.vm_name}/user-data boot-${var.vm_name}/meta-data"]
  }
}

source "qemu" "ubuntu" {
  disk_compression = true
  disk_image       = true
  iso_url          = "https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img"
  iso_checksum     = "file:https://cloud-images.ubuntu.com/focal/current/SHA256SUMS"
  output_directory = "output-${var.vm_name}"
  shutdown_command = "echo '${var.ssh_password}' | sudo -S shutdown -P now"
  memory = 8192
  disk_size        = "20G"
  format           = "qcow2"
  accelerator      = "kvm"
  ssh_password     = var.ssh_password
  ssh_timeout      = "60m"
  ssh_username     = var.ssh_username
  vm_name          = "${var.vm_name}.qcow2"
  net_device       = "virtio-net"
  qemu_binary      = "kvm"
  qemuargs = [
    ["-cdrom", "boot-${var.vm_name}/cidata.iso"],
    ["-cpu", "host"]
  ]
  headless               = true
  boot_wait              = "1s"
  ssh_port               = 22
  ssh_read_write_timeout = "600s"
  http_directory         = "./"
  boot_command = [
    "<tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><wait>",
    "<tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><wait>",
    "<tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><wait>",
    "<tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><wait>",
    "<tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><wait>",
    "<tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><wait>",
    "<tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><wait>",
    "<tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><wait>",
    "<tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><wait>",
    "<tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><wait>",
    "c<wait5>",
    "set gfxpayload=keep<enter><wait5>",
    "linux /casper/vmlinuz <wait5>",
    "autoinstall quiet fsck.mode=skip noprompt <wait5>",
    "net.ifnames=0 biosdevname=0 systemd.unified_cgroup_hierarchy=1 <wait5>",
    "ds=\"nocloud-net;s=http://{{.HTTPIP}}:{{.HTTPPort}}/\" <wait5>",
    "---<enter><wait5>",
    "initrd /casper/initrd<enter><wait5>",
    "boot<enter>"
  ]
}

build {
  sources = ["source.qemu.ubuntu"]
  # cloud-init may still be running when we start executing scripts
  # To avoid race conditions, make sure cloud-init is done first
  provisioner "shell" {
    execute_command = "echo '${var.ssh_password}' | {{ .Vars }} sudo -S -E sh -eux '{{ .Path }}'"
    scripts = [
      "./scripts/cloud-init-wait.sh",
    ]
  }
  provisioner "ansible" {
    galaxy_file          = "./ansible/requirements.yaml"
    galaxy_force_install = true

    playbook_file    = "./ansible/playbook.yaml"
    ansible_env_vars = ["ANSIBLE_REMOTE_TMP=/tmp/.ansible/tmp"]
    roles_path       = "./ansible/roles"
    user             = var.ssh_username

    #extra_arguments = ["-vvvv"]
  }
  # provisioner "shell" {
  #   execute_command   = "echo '${var.ssh_password}' | {{ .Vars }} sudo -S -E sh -eux '{{ .Path }}'"
  #   expect_disconnect = true
  #   scripts = [
  #      "./scripts/disable-updates.sh",
  #     "./scripts/qemu.sh",
  #     "./scripts/clear-machine-information.sh"
  #   ]
  # }
}