# `Vagrantfile` Reference and Explanation

## Contents

1. [Purpose and filename](#purpose-and-filename)
2. [Evaluation model](#evaluation-model)
3. [Core settings](#core-settings)
4. [Annotated single-machine example](#annotated-single-machine-example)
5. [Provisioning](#provisioning)
6. [Networking](#networking)
7. [Synced folders](#synced-folders)
8. [CPU and memory](#cpu-and-memory)
9. [Disks and filesystems](#disks-and-filesystems)
10. [Provider configuration](#provider-configuration)
11. [Multi-machine configuration](#multi-machine-configuration)
12. [Review checklist](#review-checklist)

## Purpose and filename

The `Vagrantfile` is the project-level declaration of the machines Vagrant must create, configure, and provision. The conventional literal filename is `Vagrantfile`. `VagrantFile` is a common misspelling and fails on case-sensitive filesystems.

Keep the file in the project root with provisioning scripts and configuration templates. Run Vagrant from that directory or pass an environment path deliberately.

## Evaluation model

The file is Ruby code evaluated by Vagrant:

```ruby
Vagrant.configure("2") do |config|
  # configuration
end
```

- `"2"` selects the stable Vagrant configuration API version. It is not the installed Vagrant version.
- `config` is the root configuration object.
- `config.vm` contains machine settings that should work across providers where possible.
- `config.vm.provider "virtualbox"` contains VirtualBox-specific settings.
- Blocks may use loops and environment variables, but excessive Ruby logic makes a lab hard to audit.

Vagrant can merge configuration from boxes, the project, and other supported locations. Project settings normally refine or override box defaults. Inspect the effective behavior through `vagrant validate`, normal command output, and provider VM information rather than assuming that only one file contributes defaults.

## Core settings

| Setting | Meaning | Example |
|---|---|---|
| `config.vm.box` | Provider-specific base image catalog name | `"bento/ubuntu-24.04"` |
| `config.vm.box_version` | Version or version constraint | `"202502.21.0"` |
| `config.vm.hostname` | Guest hostname | `"lab01"` |
| `config.vm.boot_timeout` | Seconds to wait for boot/communicator | `900` |
| `config.vm.network` | Forwarded, private, or public network | See below |
| `config.vm.synced_folder` | Host/guest shared path | `"./shared", "/lab"` |
| `config.vm.provision` | Guest configuration step | `"shell", path: "provision.sh"` |
| `config.vm.disk` | Grow the primary disk or attach another disk | `:disk, size: "20GB", name: "data"` |
| `config.vm.define` | Named machine in a multi-machine environment | `"db"` |

Do not copy a box version from this reference without checking the catalog. Pin the version actually tested by the lab owner.

## Annotated single-machine example

```ruby
# frozen_string_literal: true

Vagrant.configure("2") do |config|
  # Base image. Confirm that the chosen version has a VirtualBox provider build
  # for the host architecture.
  config.vm.box = "bento/ubuntu-24.04"

  # Pin after testing when reproducibility is more important than automatically
  # consuming the newest available box.
  # config.vm.box_version = "<tested-version>"

  config.vm.hostname = "lab01"
  config.vm.boot_timeout = 900

  # Expose guest service 8080 only to the local host.
  config.vm.network "forwarded_port",
    guest: 8080,
    host: 8080,
    host_ip: "127.0.0.1",
    auto_correct: true

  # Stable host-only address for host-to-guest access.
  config.vm.network "private_network", ip: "192.168.56.10"

  # Share a host directory with the guest. Vagrant creates the host directory.
  config.vm.synced_folder "./shared", "/lab", create: true

  # Keep installation logic outside the Vagrantfile.
  config.vm.provision "shell", name: "base", path: "provision.sh"

  config.vm.provider "virtualbox" do |vb|
    vb.name = "vagrant-lab-lab01"
    vb.gui = false
    vb.memory = 4096
    vb.cpus = 2
  end
end
```

The ready-to-copy version is [assets/example-lab/Vagrantfile](assets/example-lab/Vagrantfile).

## Provisioning

### External shell script

```ruby
config.vm.provision "shell", path: "provision.sh"
```

By default, the shell provisioner commonly uploads the script and runs it with elevated privileges according to guest capabilities. Set intent explicitly where it matters:

```ruby
config.vm.provision "shell",
  name: "application",
  path: "scripts/application.sh",
  privileged: true,
  args: ["--environment", "lab"],
  env: { "APP_PORT" => "8080" }
```

Avoid passing secrets in arguments because they may appear in process lists or logs.

### Inline shell

Use inline code for only a few stable commands:

```ruby
config.vm.provision "shell", inline: <<-SHELL
  install -d -m 0755 /opt/lab
  printf '%s\n' 'lab ready' > /opt/lab/status
SHELL
```

Move longer logic to a script. Provisioning must be safe to rerun with `vagrant provision`.

### Ordering and selection

Provisioners run in declaration order. Give important provisioners names:

```ruby
config.vm.provision "shell", name: "base", path: "base.sh"
config.vm.provision "shell", name: "app", path: "app.sh"
```

Then target one:

```bash
vagrant provision --provision-with app
```

## Networking

### Forwarded port

```ruby
config.vm.network "forwarded_port",
  guest: 80,
  host: 8080,
  host_ip: "127.0.0.1"
```

Traffic to host `127.0.0.1:8080` reaches guest port 80. Binding to all host interfaces can expose the guest service to the physical network.

### Private network

Static host-only address:

```ruby
config.vm.network "private_network", ip: "192.168.56.10"
```

DHCP host-only address:

```ruby
config.vm.network "private_network", type: "dhcp"
```

Static addresses simplify multi-node labs but must be unique and non-overlapping with other host networks.

### Public network

```ruby
config.vm.network "public_network"
```

This usually maps to a bridged VirtualBox adapter. Use it only when the VM must be present on the physical LAN and the network owner permits it.

## Synced folders

The first parameter is the host path, relative to the project root if not absolute. The second is an absolute guest path:

```ruby
config.vm.synced_folder "./src", "/srv/src", create: true
```

VirtualBox shared folders depend on Guest Additions. An alternative is:

```ruby
config.vm.synced_folder "./src", "/srv/src", type: "rsync"
```

`rsync` is normally one-way from host to guest. Do not edit the guest copy expecting the change to return to the host.

## CPU and memory

CPU count and memory are VirtualBox provider settings:

```ruby
config.vm.provider "virtualbox" do |vb|
  vb.memory = 8192 # MiB
  vb.cpus = 4
end
```

For host-specific sizing without editing the file:

```ruby
config.vm.provider "virtualbox" do |vb|
  vb.memory = Integer(ENV.fetch("LAB_MEMORY_MB", "4096"), 10)
  vb.cpus = Integer(ENV.fetch("LAB_CPUS", "2"), 10)
end
```

Run `vagrant reload` to apply a change. If the provider cannot reconfigure cleanly, use `vagrant halt` followed by `vagrant up`. Verify inside the guest with `nproc` and `free -h`.

## Disks and filesystems

### Grow the primary virtual disk

Set the desired total virtual-disk size:

```ruby
config.vm.disk :disk, size: "80GB", primary: true
```

`primary: true` identifies the existing boot disk. Without it, Vagrant creates and attaches a new disk. Vagrant and VirtualBox can grow the primary disk but cannot shrink it.

Apply disk changes with a powered-off guest:

```bash
vagrant validate
vagrant reload
```

Vagrant may convert a VMDK temporarily to resize it. Back up non-disposable data and do not interrupt the operation.

### Attach another hard disk

```ruby
config.vm.disk :disk, size: "20GB", name: "lab-data"
```

Each Vagrant-managed disk needs a stable, unique `name`. The VirtualBox storage controller limits how many disks can be attached.

Vagrant also supports attaching an ISO as a virtual DVD:

```ruby
config.vm.disk :dvd, name: "installer", file: "./installer.iso"
```

Removing a Vagrant-managed disk definition and reloading the VM causes Vagrant to detach and delete that virtual disk medium. Back up and unmount it first.

### Grow the guest storage layers

The `Vagrantfile` controls virtual capacity and attachments; it does not reliably grow every guest partition, LVM layout, or filesystem. Inspect the guest:

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
findmnt -no SOURCE,FSTYPE /
df -hT
sudo pvs 2>/dev/null || true
sudo vgs 2>/dev/null || true
sudo lvs 2>/dev/null || true
```

Then use the correct guest workflow:

| Layout | Required sequence |
|---|---|
| Plain ext4 partition | Grow partition → `resize2fs <partition>` |
| Plain XFS partition | Grow partition → `xfs_growfs <mount-point>` |
| LVM with ext4/XFS | Grow partition if present → `pvresize` → `lvextend -r` |
| New disk | Identify disk → partition if desired → create filesystem → mount by UUID → validate `/etc/fstab` |

Never infer a device path from an example. Resolve it from `lsblk`, `findmnt`, and LVM commands. See [tutorial.md](tutorial.md#modify-cpu-ram-disks-and-filesystems) for complete examples.

## Provider configuration

```ruby
config.vm.provider "virtualbox" do |vb|
  vb.name = "project-node"
  vb.memory = 4096
  vb.cpus = 2
  vb.gui = false
end
```

Keep generic configuration outside this block. Provider-specific `customize` calls are available, but they couple the project to VirtualBox internals and may break across releases:

```ruby
config.vm.provider "virtualbox" do |vb|
  vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
end
```

Use `customize` only when the high-level Vagrant setting cannot express the requirement, document why it exists, and test it after VirtualBox upgrades.

## Multi-machine configuration

```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-24.04"

  config.vm.define "app" do |app|
    app.vm.hostname = "app"
    app.vm.network "private_network", ip: "192.168.56.21"
  end

  config.vm.define "db" do |db|
    db.vm.hostname = "db"
    db.vm.network "private_network", ip: "192.168.56.22"
    db.vm.provider "virtualbox" do |vb|
      vb.memory = 4096
    end
  end
end
```

Root-level settings become defaults for both nodes. Settings inside a `define` block apply to that node. Use unique ports, addresses, hostnames, and `vb.name` values.

## Review checklist

- Is the file named exactly `Vagrantfile`?
- Does `vagrant validate` pass?
- Is the chosen box available for VirtualBox and the host CPU architecture?
- Is the box version pinned when reproducibility is required?
- Do VM names, hostnames, addresses, and forwarded host ports avoid collisions?
- Are forwarded services bound to `127.0.0.1` unless remote access is intentional?
- Are public networks justified and secured?
- Are CPU and memory reasonable for the host?
- Is the primary disk only being grown, never shrunk?
- Are additional disks uniquely named and within the controller limit?
- Does the guest provisioning safely and idempotently handle partitions, LVM, filesystems, UUID mounts, and reruns?
- Are provisioners ordered, named where useful, and idempotent?
- Are scripts using LF line endings for Linux guests?
- Are secrets absent from the file, arguments, logs, and committed environment files?
- Are `.vagrant/` and generated VM artifacts ignored by version control?

