# Vagrant with VirtualBox Troubleshooting

## Contents

1. [Start with evidence](#start-with-evidence)
2. [Use the recovery ladder](#use-the-recovery-ladder)
3. [Provider or version errors](#provider-or-version-errors)
4. [Hardware virtualization and hypervisor conflicts](#hardware-virtualization-and-hypervisor-conflicts)
5. [VM boot or SSH timeout](#vm-boot-or-ssh-timeout)
6. [Networking failures](#networking-failures)
7. [Synced folder and Guest Additions failures](#synced-folder-and-guest-additions-failures)
8. [Provisioning failures](#provisioning-failures)
9. [Box download, TLS, proxy, and DNS failures](#box-download-tls-proxy-and-dns-failures)
10. [Plugin failures](#plugin-failures)
11. [State mismatch or inaccessible VM](#state-mismatch-or-inaccessible-vm)
12. [Collect a support bundle](#collect-a-support-bundle)

## Start with evidence

Run non-destructive checks first:

```bash
vagrant --version
VBoxManage --version
vagrant validate
vagrant status
vagrant global-status --prune
vagrant plugin list
vagrant box list
VBoxManage list runningvms
VBoxManage list vms
```

Then reproduce once with detailed logging:

```bash
VAGRANT_LOG=debug vagrant up 2>&1 | tee vagrant-debug.log
```

On PowerShell:

```powershell
$env:VAGRANT_LOG = "debug"
vagrant up 2>&1 | Tee-Object vagrant-debug.log
Remove-Item Env:VAGRANT_LOG
```

Record the host OS and architecture, Vagrant and VirtualBox versions, box name/version/provider, exact command, first meaningful error, and recent host changes. Redact secrets before sharing logs.

## Use the recovery ladder

Stop at the first successful level:

1. Validate configuration and correct the reported line.
2. Retry the failed command once after closing conflicting VirtualBox Manager dialogs.
3. Gracefully restart with `vagrant halt` and `vagrant up`.
4. Apply configuration with `vagrant reload` or rerun provisioning with `vagrant provision`.
5. Repair only the failing subsystem: port, host-only network, Guest Additions, proxy, or plugin.
6. Restore a known-good Vagrant snapshot when its data semantics are understood.
7. Back up non-disposable guest data, then `vagrant destroy` and `vagrant up`.

Do not begin by deleting `.vagrant`, unregistering the VM, removing host-only networks, or expunging plugins. Those actions can make diagnosis harder or orphan resources.

## Provider or version errors

### Symptoms

- Vagrant cannot detect VirtualBox.
- `The provider 'virtualbox' could not be found`.
- Installed VirtualBox version is reported as unsupported.
- `VBoxManage` is not found.

### Checks and fixes

```bash
vagrant --version
VBoxManage --version
vagrant up --provider=virtualbox
```

- Confirm both applications are installed natively on the same host OS.
- Confirm the installed VirtualBox release is listed on the current [Vagrant VirtualBox provider page](https://developer.hashicorp.com/vagrant/docs/providers/virtualbox).
- Reopen the terminal after installation so `PATH` changes take effect.
- On Windows, use Windows Vagrant with Windows VirtualBox; do not expect Linux Vagrant inside WSL to discover the Windows provider normally.
- Avoid beta/pre-release VirtualBox releases for lab automation.
- If an upgrade introduced the failure, align to a supported stable pair rather than patching Vagrant's version check.

## Hardware virtualization and hypervisor conflicts

### Symptoms

- `VT-x is not available`, `AMD-V is not available`, `VERR_VMX_NO_VMX`, or `VERR_SVM_NO_SVM`.
- A VM aborts immediately or runs extremely slowly.

### Checks and fixes

- Confirm hardware virtualization is enabled in BIOS/UEFI.
- Reboot after changing firmware or hypervisor settings.
- Check whether another hypervisor is active.
- On Windows, collect `systeminfo` output and review Hyper-V, Virtual Machine Platform, Windows Hypervisor Platform, Device Guard, Credential Guard, and Core Isolation status.
- VirtualBox can use a Windows Hyper-V compatibility path on supported combinations, but performance and feature behavior can differ.
- Prefer upgrading to a supported Vagrant/VirtualBox pair before considering removal of Windows security features.
- If disabling a security feature is proposed, explain the security impact and obtain explicit approval; do not make it a routine fix.
- Nested virtualization also depends on the outer hypervisor exposing virtualization extensions.

Oracle documents known coexistence limitations in the [VirtualBox User Guide](https://www.virtualbox.org/manual/topics/KnownIssues.html).

## VM boot or SSH timeout

### Symptoms

- `Timed out while waiting for the machine to boot`.
- Repeated SSH authentication or connection retries.

### Diagnose

```bash
vagrant status
vagrant ssh-config
VBoxManage list runningvms
VBoxManage showvminfo "<vm-name>"
```

Temporarily enable the console:

```ruby
config.vm.provider "virtualbox" do |vb|
  vb.gui = true
end
```

Then `vagrant reload` and observe guest boot errors.

### Common causes

- Guest is slow and `config.vm.boot_timeout` is too short.
- Box does not support the host architecture or selected provider.
- Adapter 1/NAT or SSH settings were changed directly in VirtualBox.
- Guest filesystem requires recovery after a forced power-off.
- Disk is full.
- Firewall or endpoint security blocks VirtualBox networking.
- Custom box has invalid SSH keys, user, or communicator configuration.

Increase the timeout only when the guest is genuinely progressing:

```ruby
config.vm.boot_timeout = 1200
```

A larger timeout hides a stuck boot; inspect the console first.

## Networking failures

### Forwarded port collision

Check the intended mappings:

```bash
vagrant port
```

Find the process using the host port with the host OS network tools, then stop it or change the host port. Use `auto_correct: true` only when a dynamically selected host port is acceptable.

### Host-only address rejected or unreachable

```bash
VBoxManage list hostonlyifs
VBoxManage list hostonlynets
```

- Choose a non-overlapping subnet.
- Check overlap with VPN, Wi-Fi/Ethernet, container, and other host-only networks.
- On Linux/macOS, review the VirtualBox host-only network range policy, including `/etc/vbox/networks.conf` where applicable.
- Let Vagrant create/manage the required host-only network where possible.
- Do not remove a shared host-only interface while other VMs use it.

### VPN, proxy, or endpoint security interference

Compare behavior on and off the VPN only when organizational policy permits it. Prefer configuring approved proxy and network exclusions over disabling endpoint protection. Record routes before and after VPN connection to find overlapping subnets.

### Bridged adapter failure

- Confirm the selected physical adapter exists and is active.
- Wi-Fi drivers and corporate policy may restrict bridging.
- Avoid bridge mode if host-only plus forwarded ports meets the requirement.
- Treat a bridged guest as a LAN host and configure its firewall.

## Synced folder and Guest Additions failures

### Symptoms

- `/vagrant` is absent.
- `mount: unknown filesystem type 'vboxsf'`.
- Vagrant reports that Guest Additions do not match the host.

### Diagnose

```bash
vagrant ssh -c 'mount | grep -E "vboxsf|/vagrant" || true'
vagrant ssh -c 'modinfo vboxsf 2>/dev/null || true'
```

### Fix options

1. Prefer an updated box that ships compatible Guest Additions.
2. Rebuild the guest modules after a guest kernel update using that distribution's supported process.
3. Temporarily disable the folder to isolate boot from mount failure:

   ```ruby
   config.vm.synced_folder ".", "/vagrant", disabled: true
   ```

4. Use `type: "rsync"` when one-way host-to-guest synchronization is sufficient.

Do not install `vagrant-vbguest` automatically in every project. Modern boxes may already manage Guest Additions, and another plugin adds a separate compatibility surface.

## Provisioning failures

### Diagnose

Run only the failing named provisioner and preserve its output:

```bash
vagrant provision --provision-with <name>
```

Then test commands interactively:

```bash
vagrant ssh
sudo -i
```

### Common causes

- Windows CRLF endings produce `/bin/bash^M: bad interpreter`.
- Script is not executable when execution mode requires it.
- Package manager is locked by cloud-init or automatic updates.
- DNS, proxy, repository, or certificate settings fail inside the guest.
- Script assumes an interactive TTY.
- A previous partial run makes a non-idempotent command fail.
- A required file path is relative to a different directory than expected.

Normalize a Linux guest script in Git:

```gitattributes
*.sh text eol=lf
Vagrantfile text eol=lf
```

Do not use `|| true` broadly. Handle only expected, safe non-zero outcomes or the lab may appear provisioned while required steps failed.

## Box download, TLS, proxy, and DNS failures

```bash
vagrant box list
vagrant box add <organization>/<box> --provider virtualbox
```

- Confirm the catalog entry and provider build exist.
- Confirm host date/time and CA trust are correct.
- Configure approved `HTTP_PROXY`, `HTTPS_PROXY`, and `NO_PROXY` values when required.
- Avoid `--insecure`; it disables certificate verification.
- For a direct `.box` URL, use the publisher's checksum with `--checksum` and `--checksum-type`.
- On restricted networks, download through an approved path and add the verified local box file with an explicit name.
- A partial download can often resume. Use `--clean` only when the cached download is known to be corrupt or the remote artifact changed.

## Plugin failures

### Symptoms

- Ruby gem dependency errors during Vagrant startup.
- A plugin cannot initialize after a Vagrant upgrade.

### Recovery

```bash
vagrant plugin list
vagrant plugin repair
```

If repair fails, record the plugin list and verify network/proxy access before the destructive reset:

```bash
vagrant plugin expunge --reinstall
```

Remove unnecessary plugins from the lab dependency list. Do not manually edit Ruby gems as a durable fix; prefer a maintained plugin release compatible with the installed Vagrant version.

## State mismatch or inaccessible VM

### Symptoms

- Vagrant says a VM is missing while VirtualBox still lists it.
- VirtualBox says a machine UUID already exists.
- VM is `inaccessible` after files were moved or renamed.

### Diagnose

```bash
vagrant status
vagrant global-status --prune
VBoxManage list vms
VBoxManage showvminfo "<vm-name>"
```

Inspect `.vagrant/machines/<machine>/virtualbox/id` without changing it. Compare the stored UUID to VirtualBox inventory.

### Recovery principles

- Back up the project state and any non-disposable virtual disks.
- If the Vagrant state points to the correct existing VM, repair the underlying VirtualBox registration/path issue first.
- If the VM is disposable, the cleanest recovery is usually `vagrant destroy` followed by `vagrant up`.
- If Vagrant no longer owns an orphaned VM, unregistering/deleting it directly is destructive and must be explicitly confirmed after exact VM and disk paths are verified.
- Do not copy another VM's UUID into `.vagrant` as a guess.

## Collect a support bundle

Collect text outputs into a directory, then inspect and redact them before sharing:

```bash
vagrant --version
VBoxManage --version
vagrant validate
vagrant status
vagrant global-status --prune
vagrant box list
vagrant plugin list
VBoxManage list vms
VBoxManage list runningvms
VBoxManage list hostonlyifs
VBoxManage list hostonlynets
```

Also include:

- Sanitized `Vagrantfile` and provisioning scripts
- The first meaningful error plus surrounding log lines
- Host OS name, release, and CPU architecture
- Box name, version, and provider
- Whether the project is on a local, network, synchronized, WSL, or removable filesystem
- Recent Vagrant, VirtualBox, kernel, firmware, VPN, security, or OS changes

