# Vagrant with VirtualBox Tutorial

## Contents

1. [Mental model](#mental-model)
2. [Host preparation](#host-preparation)
3. [Create the first lab](#create-the-first-lab)
4. [Operate the VM](#operate-the-vm)
5. [Provision software](#provision-software)
6. [Configure networking](#configure-networking)
7. [Share files](#share-files)
8. [Build multi-machine labs](#build-multi-machine-labs)
9. [Make labs reproducible](#make-labs-reproducible)
10. [Maintain the lab](#maintain-the-lab)

## Mental model

Vagrant does not run a virtual machine itself. It reads a `Vagrantfile`, downloads or selects a base **box**, asks the **VirtualBox provider** to create and operate the VM, and runs **provisioners** inside it.

| Component | Responsibility |
|---|---|
| `Vagrantfile` | Desired lab definition: box, resources, networks, folders, and provisioners |
| Vagrant | Lifecycle orchestration and machine state mapping |
| VirtualBox | Hypervisor, virtual hardware, disks, and virtual networks |
| Box | Reusable provider-specific base image |
| Provisioner | Repeatable guest configuration, such as a shell, Ansible, or cloud-init step |
| `.vagrant/` | Local project state that maps Vagrant machine names to provider VM identifiers |

The intended loop is: edit configuration, validate it, start or reload the VM, provision it, test it, and destroy/recreate it when a clean lab is needed.

## Host preparation

### Check prerequisites

1. Enable Intel VT-x or AMD-V in BIOS/UEFI.
2. Install a stable VirtualBox release supported by the chosen Vagrant version.
3. Install Vagrant on the same host operating system as VirtualBox.
4. Reboot if the installer added or replaced hypervisor drivers.
5. Check both command-line tools:

   ```bash
   vagrant --version
   VBoxManage --version
   vagrant plugin list
   ```

Consult the current [Vagrant VirtualBox provider page](https://developer.hashicorp.com/vagrant/docs/providers/virtualbox) rather than assuming that a newly released VirtualBox version is already supported.

### Windows and WSL

When VirtualBox is installed on Windows, run the Windows Vagrant executable from PowerShell or Windows Terminal and keep the project on a Windows filesystem such as `C:\labs\demo`. Installing Linux Vagrant inside WSL does not make it control the Windows VirtualBox installation as a normal same-host provider pair.

Hyper-V, Virtual Machine Platform, Windows Hypervisor Platform, Device Guard, Credential Guard, and Core Isolation may cause VirtualBox to use the Windows hypervisor compatibility path. This can be slower and some combinations fail. Do not disable security features blindly; first capture the exact error and consult [troubleshooting.md](troubleshooting.md).

### Linux

Ensure the running kernel has matching VirtualBox kernel modules. After a kernel update, reinstall/rebuild the modules using the distribution's VirtualBox package procedure before debugging Vagrant.

Add the user to `vboxusers` only for features that require it, commonly USB access. Log out and back in after changing group membership.

### macOS

Approve Oracle's system extension if the operating system requests it, then reboot. On Apple silicon, use guest boxes and VirtualBox builds that support the host architecture; an x86_64 box cannot be assumed to run on an ARM64 host.

## Create the first lab

### Initialize a project

```bash
mkdir vagrant-lab
cd vagrant-lab
vagrant init bento/ubuntu-24.04
```

`vagrant init` creates a starter `Vagrantfile`. A box name identifies a catalog entry; a box is provider-specific, so verify that the selected version includes a VirtualBox build for the host architecture.

For the repository example, copy both files from `assets/example-lab/` into a new directory while preserving the executable bit on `provision.sh` where applicable.

### Review the generated configuration

At minimum, the file contains:

```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-24.04"
end
```

The filename is `Vagrantfile`, not `VagrantFile`. Case matters on case-sensitive filesystems. The file is Ruby code evaluated by Vagrant; do not execute it as a general-purpose Ruby script.

Read [vagrantfile.md](vagrantfile.md) for a full explanation of the configuration model.

### Validate and start

```bash
vagrant validate
vagrant up --provider=virtualbox
vagrant status
```

The first `up` downloads the box if necessary, imports it into VirtualBox, configures virtual hardware and networks, boots it, waits for SSH, mounts synced folders, and runs provisioners.

## Operate the VM

Run lifecycle commands from the directory containing the matching `Vagrantfile`:

```bash
vagrant ssh
vagrant ssh -c 'hostname; uname -a'
vagrant halt
vagrant up
vagrant suspend
vagrant resume
vagrant reload
```

- `halt` performs a guest shutdown and retains the VM.
- `suspend` saves VM state and consumes disk space roughly related to guest RAM.
- `reload` is effectively halt/start and applies many virtual hardware or network changes.
- `destroy` deletes the VM and its Vagrant-managed disks, but normally retains the downloaded box.

Use `vagrant destroy` only when persistent data inside the VM is disposable or backed up.

## Provision software

Provisioners turn a base box into the desired lab. Prefer an external script because it is testable and readable:

```ruby
config.vm.provision "shell", path: "provision.sh"
```

Run provisioning explicitly:

```bash
vagrant provision
vagrant provision --provision-with shell
vagrant reload --provision
```

Make shell provisioning idempotent:

- Check whether a package, file, user, or service already exists.
- Use the package manager's normal idempotent install operation.
- Use deterministic configuration templates rather than appending the same line on every run.
- Fail fast with `set -euo pipefail` on compatible shells.
- Log enough context to locate the failing command.
- Normalize scripts to LF line endings for Linux guests.

Vagrant marks initial provisioning as completed in project state. Changing a script does not necessarily cause it to run on a normal `vagrant up`; use `vagrant provision` or `vagrant reload --provision`.

## Configure networking

Vagrant normally creates adapter 1 as NAT so it can reach the guest over SSH. Add higher-level networks only when needed.

### Forward a service to the host

```ruby
config.vm.network "forwarded_port",
  guest: 8080,
  host: 8080,
  host_ip: "127.0.0.1",
  auto_correct: true
```

Use `host_ip: "127.0.0.1"` for a host-only service. `auto_correct` avoids a collision by selecting a different host port, but scripts must discover or document the actual selected port. Omit it when an exact port is part of the lab contract and a collision should fail visibly.

### Add a host-only private address

```ruby
config.vm.network "private_network", ip: "192.168.56.10"
```

This is useful for host-to-guest and lab-node communication. Choose a subnet that does not overlap the physical LAN, VPN, container networks, or another host-only adapter.

### Bridge to the physical LAN

```ruby
config.vm.network "public_network"
```

Use this only when other physical-network devices must reach the VM. The guest becomes a peer on that network and must be patched, firewalled, and authenticated accordingly. Adapter selection may be interactive unless explicitly configured.

## Share files

By default, Vagrant shares the project directory at `/vagrant`. With the VirtualBox provider, the default folder implementation typically uses VirtualBox shared folders and therefore depends on compatible Guest Additions in the guest.

Add another folder:

```ruby
config.vm.synced_folder "./shared", "/lab", create: true
```

Disable the default share when the lab does not need host files:

```ruby
config.vm.synced_folder ".", "/vagrant", disabled: true
```

When VirtualBox shared folders are unavailable, `rsync` can be a practical one-way alternative:

```ruby
config.vm.synced_folder ".", "/vagrant", type: "rsync"
```

Run `vagrant rsync-auto` for continuous host-to-guest updates. Remember that guest changes are not synchronized back with the `rsync` folder type.

## Build multi-machine labs

Define each node by name and give it a unique hostname, IP, and provider VM name:

```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-24.04"

  { "app" => "192.168.56.21", "db" => "192.168.56.22" }.each do |name, ip|
    config.vm.define name do |node|
      node.vm.hostname = name
      node.vm.network "private_network", ip: ip
      node.vm.provider "virtualbox" do |vb|
        vb.name = "lab-#{name}"
        vb.memory = name == "db" ? 4096 : 2048
        vb.cpus = 2
      end
    end
  end
end
```

Operate all nodes or one named node:

```bash
vagrant up
vagrant status
vagrant ssh app
vagrant provision db
vagrant halt app
```

Avoid provisioning a dependent node before its service dependency is ready. A running VM is not necessarily a ready database or application; add explicit readiness checks.

## Make labs reproducible

- Pin a tested box version with `config.vm.box_version` for stable workshops or CI.
- Record required Vagrant plugins and install only those actually used by the `Vagrantfile`.
- Commit the `Vagrantfile`, provisioning code, and non-secret configuration.
- Ignore `.vagrant/`, generated logs, secrets, and VM disk files.
- Use environment variables only for host-specific, non-secret toggles; use a proper secret delivery mechanism for credentials.
- Give provider VMs deterministic, project-prefixed names to avoid collisions.
- Size CPU and memory for the weakest supported host and document optional overrides.
- Prefer immutable rebuilds for disposable labs over prolonged in-guest drift.

Suggested `.gitignore` entries:

```gitignore
.vagrant/
*.log
.env
*.box
```

## Maintain the lab

Check updates without changing the running VM:

```bash
vagrant box outdated
vagrant plugin list
```

Update deliberately:

```bash
vagrant box update
vagrant plugin update
```

Updating a box does not replace an existing VM. Rebuild the VM to consume the new base box:

```bash
vagrant destroy
vagrant up --provider=virtualbox
```

Back up or export non-disposable data before rebuilding. After validating the new lab, old unused box versions can be reviewed with `vagrant box prune --dry-run` and removed interactively.

