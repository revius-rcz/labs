---
name: vagrant-virtualbox-labs
description: Provision and operate reproducible local lab virtual machines with Vagrant and the VirtualBox provider. Use when installing or validating Vagrant with VirtualBox; creating, explaining, reviewing, or troubleshooting a Vagrantfile; configuring RAM, CPUs, primary or additional disks, partitions, LVM, or filesystems; managing boxes, plugins, networking, synced folders, snapshots, provisioning, or multi-machine labs; or diagnosing Vagrant and VirtualBox startup, SSH, storage, Guest Additions, port, host-only network, proxy, or virtualization failures.
---

# Vagrant with VirtualBox Labs

Use Vagrant as the lifecycle and configuration layer and VirtualBox as the VM provider. Prefer changing the `Vagrantfile` and reprovisioning over making undocumented changes in VirtualBox Manager.

## Route the task

| Need | Read |
|---|---|
| Learn the complete workflow | [tutorial.md](tutorial.md) |
| Find a command quickly | [cheatsheet.md](cheatsheet.md) |
| Understand or write a `Vagrantfile` | [vagrantfile.md](vagrantfile.md) |
| Diagnose a failure | [troubleshooting.md](troubleshooting.md) |
| Start from a working single-VM lab | [assets/example-lab/Vagrantfile](assets/example-lab/Vagrantfile) and [assets/example-lab/provision.sh](assets/example-lab/provision.sh) |

## Apply the standard workflow

1. Confirm that Vagrant and VirtualBox are installed on the same host operating system.
2. Check versions with `vagrant --version` and `VBoxManage --version`, then confirm that the installed VirtualBox release is supported by the installed Vagrant release.
3. Work from the directory containing the literal filename `Vagrantfile`.
4. Inspect the `Vagrantfile`, provisioner files, `.vagrant` state, and `vagrant status` before changing anything.
5. Run `vagrant validate` before `vagrant up`.
6. Start explicitly with `vagrant up --provider=virtualbox` when more than one provider may be installed.
7. Verify connectivity with `vagrant ssh -c 'hostname; ip address'` and verify the intended service separately.
8. Make provisioning idempotent so `vagrant provision` can be repeated safely.
9. Capture diagnostics before destructive recovery. Follow the recovery ladder in [troubleshooting.md](troubleshooting.md).

## Preserve lab safety

- Treat `vagrant destroy`, `vagrant snapshot delete`, `vagrant box remove`, `vagrant box prune`, and `vagrant plugin expunge` as destructive. State the impact and obtain confirmation before running them against a user's environment.
- Treat disk removal, `mkfs`, partition-table changes, LVM removal, and filesystem shrinking as destructive. Resolve the exact device and back up non-disposable data first.
- Do not delete `.vagrant` as a first response. It maps the project to provider resources; removing it can orphan a VM.
- Do not commit `.vagrant/`, private keys, passwords, tokens, or unencrypted environment files.
- Bind forwarded ports to `127.0.0.1` unless remote host access is intentional.
- Avoid bridged/public networking unless the VM must appear on the physical LAN. Explain that the VM is then exposed to that network.
- Use snapshots as short-lived lab checkpoints, not as backups.
- Pin a tested box version for reproducible labs and update it deliberately.
- Prefer boxes that already contain compatible VirtualBox Guest Additions. Do not install a Guest Additions management plugin unless the lab actually needs it.

## Use authoritative references

- Vagrant documentation: <https://developer.hashicorp.com/vagrant/docs>
- Vagrant installation: <https://developer.hashicorp.com/vagrant/install>
- VirtualBox provider support: <https://developer.hashicorp.com/vagrant/docs/providers/virtualbox>
- Vagrant disk configuration: <https://developer.hashicorp.com/vagrant/docs/disks/usage>
- Oracle VirtualBox User Guide: <https://www.virtualbox.org/manual/>
- Oracle VirtualBox virtual storage: <https://www.virtualbox.org/manual/ch05.html>
