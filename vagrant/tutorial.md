# Vagrant with VirtualBox Tutorial

## Contents

1. [Mental model](#mental-model)
2. [Host preparation](#host-preparation)
3. [Create the first lab](#create-the-first-lab)
4. [Modify CPU, RAM, disks, and filesystems](#modify-cpu-ram-disks-and-filesystems)
5. [Operate the VM](#operate-the-vm)
6. [Provision software](#provision-software)
7. [Configure networking](#configure-networking)
8. [Share files](#share-files)
9. [Build multi-machine labs](#build-multi-machine-labs)
10. [Make labs reproducible](#make-labs-reproducible)
11. [Maintain the lab](#maintain-the-lab)

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

## Modify CPU, RAM, disks, and filesystems

### Understand the storage layers

Changing storage is not one operation. Work through the relevant layers in order:

| Layer | Controlled by | Typical action |
|---|---|---|
| Virtual CPU and RAM | VirtualBox provider configuration | Change `vb.cpus` or `vb.memory`, then reload the powered-off VM |
| Virtual disk capacity/attachment | Vagrant disk configuration and VirtualBox | Change `config.vm.disk`, then reload the VM |
| Partition or LVM physical volume | Guest operating system | Grow the partition or physical volume after the virtual disk grows |
| Logical volume | Guest LVM | Extend the intended logical volume |
| Filesystem | Guest filesystem tools | Grow ext4, XFS, or another filesystem with its own supported tool |

`df -h` reports filesystem capacity, not raw virtual disk capacity. A successfully enlarged VirtualBox disk can therefore remain invisible to `df` until the guest partition, LVM, and filesystem layers are extended.

### Change RAM and virtual CPUs

Set resources in the VirtualBox provider block:

```ruby
config.vm.provider "virtualbox" do |vb|
  vb.memory = 8192 # MiB
  vb.cpus = 4
end
```

Environment-variable overrides make one lab definition usable on different hosts:

```ruby
config.vm.provider "virtualbox" do |vb|
  vb.memory = Integer(ENV.fetch("LAB_MEMORY_MB", "4096"), 10)
  vb.cpus = Integer(ENV.fetch("LAB_CPUS", "2"), 10)
end
```

Apply and verify the change:

```bash
vagrant validate
vagrant reload
vagrant ssh -c 'printf "CPUs: "; nproc; free -h'
```

If reload cannot change the hardware cleanly, use `vagrant halt` followed by `vagrant up`. Leave enough CPU and RAM for the host OS and other workloads. More virtual CPUs can reduce performance when the host is oversubscribed.

### Grow the primary virtual disk

Declare the desired total size, not an increment:

```ruby
config.vm.disk :disk, size: "80GB", primary: true
```

Then apply the VirtualBox disk change while the guest is powered off:

```bash
vagrant validate
vagrant halt
vagrant up
```

Vagrant can grow a VirtualBox primary disk but cannot shrink it. Many boxes use VMDK; Vagrant may temporarily convert the disk to VDI, resize it, and convert it back. Back up non-disposable data and do not interrupt this operation.

Inspect the guest layout before changing partitions or filesystems:

```bash
vagrant ssh
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
findmnt -no SOURCE,FSTYPE /
df -hT
sudo pvs 2>/dev/null || true
sudo vgs 2>/dev/null || true
sudo lvs 2>/dev/null || true
```

Resolve the actual disk, partition, LVM, filesystem, and mount point from this output. Device names such as `/dev/sda`, `/dev/sda3`, `/dev/vda`, and `/dev/nvme0n1p3` are examples, not interchangeable commands.

#### Plain partition with ext4

For an identified root partition such as `/dev/sda1`:

```bash
sudo growpart /dev/sda 1
sudo resize2fs /dev/sda1
df -hT /
```

`growpart` is commonly supplied by `cloud-guest-utils` on Debian/Ubuntu and `cloud-utils-growpart` on RHEL-compatible systems.

#### Plain partition with XFS

Grow the identified partition, then grow XFS by mount point:

```bash
sudo growpart /dev/sda 1
sudo xfs_growfs /
df -hT /
```

XFS can grow while mounted but cannot be shrunk.

#### LVM-backed filesystem

For an identified LVM physical-volume partition such as `/dev/sda3`:

```bash
sudo growpart /dev/sda 3
sudo pvresize /dev/sda3
sudo pvs
sudo vgs
sudo lvs
sudo lvextend -r -l +100%FREE /dev/<vg>/<lv>
```

Replace the example device and logical-volume path with values verified by `pvs` and `lvs`. `lvextend -r` extends both the logical volume and a supported filesystem. Do not allocate all free extents when the volume group intentionally reserves capacity for snapshots or other logical volumes.

### Attach an additional data disk

Add a named disk to the `Vagrantfile`:

```ruby
config.vm.disk :disk, size: "20GB", name: "lab-data"
```

Apply and identify it:

```bash
vagrant reload
vagrant ssh
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,SERIAL
```

Do not assume that the new device is `/dev/sdb`. Compare the before/after inventory and confirm that the selected device is empty. The following example is destructive and is valid only after `/dev/sdb` has been positively identified as the new disk:

```bash
sudo parted /dev/sdb --script mklabel gpt mkpart primary 0% 100%
sudo partprobe /dev/sdb
sudo mkfs.xfs /dev/sdb1
sudo install -d -m 0755 /data
sudo mount /dev/sdb1 /data
findmnt /data
```

Persist the mount by UUID rather than a device name:

```bash
sudo blkid /dev/sdb1
```

Add the verified UUID and filesystem type to `/etc/fstab`:

```fstab
UUID=<verified-uuid> /data xfs defaults,nofail 0 2
```

Validate before rebooting:

```bash
sudo umount /data
sudo mount -a
findmnt /data
```

Provisioning can automate this workflow only after it verifies the expected disk identity, existing filesystem, UUID, and `/etc/fstab` entry so reruns cannot reformat data.

### Remove or shrink storage

Before removing a secondary disk, stop applications, back up its data, unmount it, and remove its `/etc/fstab` entry. Removing a Vagrant-managed disk from `Vagrantfile` and running `vagrant reload` detaches it and deletes its host-side virtual medium.

Do not attempt to shrink a virtual disk by setting a smaller `size`. XFS cannot shrink, ext4 shrinking is an offline multi-layer operation, and VirtualBox/Vagrant do not support shrinking the primary virtual disk through this configuration. For disposable labs, create a correctly sized replacement disk or rebuild the VM and restore only required data.

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
