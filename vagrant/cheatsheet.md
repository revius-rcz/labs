# Vagrant and VirtualBox Cheat Sheet

Run project commands from the directory containing `Vagrantfile`. Add a machine name for a multi-machine lab, for example `vagrant ssh db`.

## Project and lifecycle

| Goal | Command | Notes |
|---|---|---|
| Create starter file | `vagrant init <box>` | Creates `Vagrantfile` |
| Validate configuration | `vagrant validate` | Does not create a VM |
| Start/create VM | `vagrant up --provider=virtualbox` | Downloads the box if missing |
| Show project state | `vagrant status` | Uses local `.vagrant` mapping |
| Show all known environments | `vagrant global-status` | Cache may contain stale entries |
| Remove stale global entries | `vagrant global-status --prune` | Does not destroy active VMs |
| Graceful shutdown | `vagrant halt` | Keeps VM and disks |
| Force power off | `vagrant halt --force` | Equivalent to pulling power; risk of guest corruption |
| Suspend/resume | `vagrant suspend` / `vagrant resume` | Saves/restores runtime state |
| Restart and apply config | `vagrant reload` | Add `--provision` to rerun provisioners |
| Delete project VM | `vagrant destroy` | Destructive; downloaded box remains |

## Access and diagnostics

```bash
vagrant ssh
vagrant ssh -c 'hostname; ip address'
vagrant ssh-config
vagrant port
vagrant status
vagrant global-status --prune
```

Enable detailed Vagrant logging for one command:

```bash
VAGRANT_LOG=info vagrant up
VAGRANT_LOG=debug vagrant up 2>&1 | tee vagrant-debug.log
```

PowerShell:

```powershell
$env:VAGRANT_LOG = "debug"
vagrant up 2>&1 | Tee-Object vagrant-debug.log
Remove-Item Env:VAGRANT_LOG
```

Do not publish debug logs without reviewing them for paths, usernames, tokens, proxy credentials, and other secrets.

## Provisioning

| Goal | Command |
|---|---|
| Run all configured provisioners | `vagrant provision` |
| Run a named provisioner | `vagrant provision --provision-with <name>` |
| Restart, then provision | `vagrant reload --provision` |
| Start and force provisioning | `vagrant up --provision` |
| Skip provisioning | `vagrant up --no-provision` |

Name a provisioner in the `Vagrantfile` when it must be selectable:

```ruby
config.vm.provision "shell", name: "base", path: "provision.sh"
```

## Boxes

```bash
vagrant box list
vagrant box add <organization>/<box> --provider virtualbox
vagrant box outdated
vagrant box outdated --global
vagrant box update
vagrant box update --box <organization>/<box> --provider virtualbox
vagrant box prune --dry-run
vagrant box remove <organization>/<box> --provider virtualbox --box-version <version>
```

`box update` changes the locally available base image, not an already-created VM.

## Plugins

```bash
vagrant plugin list
vagrant plugin install <plugin>
vagrant plugin update
vagrant plugin repair
vagrant plugin expunge --reinstall
```

Use `plugin expunge` only after `plugin repair` fails. It removes installed plugin state and is disruptive, especially in offline or proxy-restricted environments.

## Snapshots

```bash
vagrant snapshot list
vagrant snapshot save before-upgrade
vagrant snapshot restore before-upgrade
vagrant snapshot delete before-upgrade
vagrant snapshot push
vagrant snapshot pop
```

Snapshots are provider-local checkpoints, not portable backups. Restoring one also restores old disk state and may invalidate application data relationships outside the VM.

## Synced folders

```bash
vagrant rsync
vagrant rsync-auto
```

Useful definitions:

```ruby
config.vm.synced_folder "./shared", "/lab", create: true
config.vm.synced_folder ".", "/vagrant", disabled: true
config.vm.synced_folder ".", "/vagrant", type: "rsync"
```

## Provider and environment selection

Bash:

```bash
export VAGRANT_DEFAULT_PROVIDER=virtualbox
export VAGRANT_HOME="$PWD/.vagrant-home"
```

PowerShell:

```powershell
$env:VAGRANT_DEFAULT_PROVIDER = "virtualbox"
$env:VAGRANT_HOME = "$PWD\.vagrant-home"
```

Use a custom `VAGRANT_HOME` only deliberately; it changes where boxes, plugins, and global state are found.

## Read-only VirtualBox checks

```bash
VBoxManage --version
VBoxManage list vms
VBoxManage list runningvms
VBoxManage list hostonlyifs
VBoxManage list hostonlynets
VBoxManage showvminfo "<vm-name>"
VBoxManage showvminfo "<vm-name>" --machinereadable
```

Prefer letting Vagrant change a Vagrant-managed VM. Direct `VBoxManage modifyvm`, `unregistervm --delete`, and host-only network removal can desynchronize Vagrant state and are destructive.

## What to run after changing `Vagrantfile`

| Change | Typical action |
|---|---|
| Provisioning script | `vagrant provision` |
| CPU, memory, NIC, forwarded port | `vagrant reload` |
| Box name/version | `vagrant destroy` then `vagrant up` |
| Synced folder | `vagrant reload` |
| Shell environment variable read by config | Rerun the intended command with the variable set |
| Multi-machine node definition | `vagrant up <node>` or `vagrant up` |

