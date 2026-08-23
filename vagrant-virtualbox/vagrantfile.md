# `Vagrantfile` Reference and Explanation

## Contents

1. [Purpose and filename](#purpose-and-filename)
2. [Evaluation model](#evaluation-model)
3. [Core settings](#core-settings)
4. [Annotated single-machine example](#annotated-single-machine-example)
5. [Provisioning](#provisioning)
6. [Networking](#networking)
7. [Synced folders](#synced-folders)
8. [Provider configuration](#provider-configuration)
9. [Multi-machine configuration](#multi-machine-configuration)
10. [Review checklist](#review-checklist)

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
- Are provisioners ordered, named where useful, and idempotent?
- Are scripts using LF line endings for Linux guests?
- Are secrets absent from the file, arguments, logs, and committed environment files?
- Are `.vagrant/` and generated VM artifacts ignored by version control?

