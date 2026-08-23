# Prepare a Local AI Lab

## Table of Contents

* [Local Deployment](#local-deployment)

  * [Topology](#topology)
* [Initial Tools Setup](#initial-tools-setup)

  * [Windows Subsystem for Linux](#windows-subsystem-for-linux)
  * [VirtualBox](#virtualbox)
  * [Vagrant](#vagrant)
  * [Podman](#podman)
  * [Git](#git)
  * [Visual Studio Code](#visual-studio-code)
* [Lab Resources](#lab-resources)

  * [Jupyter Lab](#jupyter-lab)

    * [Podman Method](#podman-method)
    * [Visual Studio Code Method](#visual-studio-code-method)
  * [Generative AI Model and Open WebUI](#generative-ai-model-and-open-webui)

    * [Deploy Llama 3.2](#deploy-llama-32)
    * [Deploy Open WebUI](#deploy-open-webui)
    * [Connect Open WebUI to the Local Model](#connect-open-webui-to-the-local-model)
  * [Embedding Model](#embedding-model)
  * [Oracle Database 26ai](#oracle-database-26ai)
* [Troubleshooting](#troubleshooting)

  * [Podman Bridge Network Error](#podman-bridge-network-error)

## Local Deployment

### Topology

The following topology will be created by following this document. The ports may be customized.

| Tool                                       | URL                                                                     |
| ------------------------------------------ | ----------------------------------------------------------------------- |
| Jupyter Lab                                | `http://127.0.0.1:8888/lab?token=<token>` or through Visual Studio Code |
| Generative AI model                        | `http://127.0.0.1:7000`                                                 |
| Generative AI model from another container | `http://host.containers.internal:7000`                                  |
| Open WebUI                                 | `http://127.0.0.1:3000/auth?redirect=%2F`                               |
| Embedding model                            | `http://127.0.0.1:9000`                                                 |
| Embedding model from another container     | `http://host.containers.internal:9000`                                  |

[Back to Table of Contents](#table-of-contents)

## Initial Tools Setup

### Windows Subsystem for Linux

It is recommended to run all command-line steps in Windows Terminal.

This section is not applicable to macOS users.

> Disconnect from the VPN when configuring WSL.

1. Install Windows Terminal through the Microsoft Store.

2. Install WSL:

   ```powershell
   wsl --install
   ```

3. Reboot the laptop.

4. Install a Linux distribution. This example uses Oracle Linux 8.10:

   ```powershell
   # List available distributions
   wsl --list --online

   # Install Oracle Linux 8.10
   wsl --install -d OracleLinux_8_10

   # List installed distributions with details
   wsl --list --verbose

   # Set the distribution to WSL version 2
   wsl --set-version OracleLinux_8_10 2
   ```

5. Access the Linux distribution through Windows Terminal.

6. To switch to the root user, run:

   ```bash
   sudo su -
   ```

   When prompted, enter the password configured for your user during WSL setup.

[Back to Table of Contents](#table-of-contents)

### VirtualBox

1. Download and install VirtualBox:

   https://www.virtualbox.org/wiki/Downloads

2. Set the default machine folder.

[Back to Table of Contents](#table-of-contents)

### Vagrant

For a complete tutorial, command cheat sheet, `Vagrantfile` reference, example lab, and troubleshooting workflow, see [Vagrant with VirtualBox Labs](vagrant-virtualbox/SKILL.md).

> Disconnect from the VPN when installing Vagrant plugins.

1. Download and install Vagrant:

   https://developer.hashicorp.com/vagrant/install

2. Install the required plugins:

   ```bash
   vagrant plugin install vagrant-reload
   vagrant plugin install vagrant-env
   vagrant plugin install vagrant-proxyconf
   vagrant plugin install vagrant-disksize
   vagrant plugin install vagrant-scp
   ```

3. The Ruby dependency used by `vagrant-env` may generate an error similar to:

   ```text
   Path: C:/Users/<user>/.vagrant.d/gems/3.3.8/gems/dotenv-0.11.1/lib/dotenv.rb
   Line number: 0
   Message: undefined method `exists?'
   ```

   To fix it, open the listed `dotenv.rb` file in a text editor and replace every occurrence of `exists` with `exist`.

   Related issue:

   https://github.com/hashicorp/vagrant/issues/13550

4. Useful Vagrant commands:

   ```bash
   vagrant up
   vagrant halt
   vagrant reload
   vagrant suspend
   vagrant resume
   vagrant destroy
   vagrant ssh
   vagrant provision
   vagrant box list
   vagrant box remove <box>
   vagrant box add <box>
   vagrant global-status
   vagrant snapshot save <name>
   vagrant snapshot restore <name>
   ```

[Back to Table of Contents](#table-of-contents)

### Podman

> Disconnect from the VPN when running `yum`.

Install Podman inside the WSL Linux distribution:

```bash
yum install podman
```

[Back to Table of Contents](#table-of-contents)

### Git

Git will be useful during the setup.


[Back to Table of Contents](#table-of-contents)

### Visual Studio Code

1. Install Visual Studio Code

2. Prepare Python inside the WSL instance:

   ```bash
   sudo yum install python3.12 python3.12-pip python3.12-requests
   pip3.12 install ipykernel
   ```

3. Connect Visual Studio Code to the running WSL instance.

4. Install the following extensions:

   * Python
   * Jupyter
   * Cline

[Back to Table of Contents](#table-of-contents)

## Lab Resources

### Jupyter Lab

> Disconnect from the VPN when running `podman pull` or `podman run` for the first time.

When asked to choose a source while downloading an image, select Docker rather than Oracle Container Registry.

#### Podman Method

Jupyter Lab will be deployed as a Podman container. It can be used to experiment with Python code.

Pull the image:

```bash
podman pull jupyter/scipy-notebook:latest
```

Create and run the container:

```bash
podman run \
  --name jupyter \
  --add-host=host.containers.internal:host-gateway \
  -d \
  -v jupvol:/home/jovyan \
  -p 8888:8888 \
  jupyter/scipy-notebook:latest
```

Check the logs to find the full Jupyter URL:

```bash
podman logs jupyter
```

The URL will resemble:

```text
http://127.0.0.1:8888/lab?token=<generated-token>
```

[Back to Table of Contents](#table-of-contents)

#### Visual Studio Code Method

1. Prepare Python inside the WSL instance:

   ```bash
   sudo yum install python3.12 python3.12-pip python3.12-requests
   pip3.12 install ipykernel
   ```

2. Confirm that the following Visual Studio Code extensions are installed:

   * Python
   * Jupyter

3. Press `Ctrl+Shift+P`.

4. Select:

   ```text
   Create: New Jupyter Notebook
   ```

5. Choose the appropriate Python kernel.

[Back to Table of Contents](#table-of-contents)

### Generative AI Model and Open WebUI

> Disconnect from the VPN when running `podman pull` or `podman run` for the first time.

When asked to choose a source while downloading an image, select Docker rather than Oracle Container Registry.

The following instructions deploy a local AI model using Podman and Ollama.

The selected model is Llama 3.2 because it has relatively modest memory requirements:

| Model        | Approximate RAM requirement |
| ------------ | --------------------------: |
| Llama 3.2 1B |                        4 GB |
| Llama 3.2 3B |                        8 GB |

The examples below use Llama 3.2 1B.

Open WebUI provides a web interface for AI models. It can be used to experiment with AI chat and verify that the locally deployed model works.

#### Deploy Llama 3.2

Create the Ollama container:

```bash
podman run \
  -d \
  --name llama \
  -p 7000:11434 \
  --add-host=host.containers.internal:host-gateway \
  -v ollama:/root/.ollama \
  ollama/ollama
```

Start the Llama 3.2 1B model:

```bash
podman exec -d llama ollama run llama3.2:1b
```

[Back to Table of Contents](#table-of-contents)

#### Deploy Open WebUI

```bash
podman run \
  -d \
  -p 3000:8080 \
  --add-host=host.containers.internal:host-gateway \
  -v open-webui3:/app/backend/data \
  --name open-webui \
  ghcr.io/open-webui/open-webui:main
```

[Back to Table of Contents](#table-of-contents)

#### Connect Open WebUI to the Local Model

1. Open Open WebUI:

   http://127.0.0.1:3000/auth?redirect=%2F

2. Select the profile icon in the bottom-left corner.

3. Navigate to:

   ```text
   Admin Panel → Settings → Connections
   ```

4. Enter the following value for the Ollama API:

   ```text
   http://host.containers.internal:7000
   ```

5. Save the connection settings.

[Back to Table of Contents](#table-of-contents)

### Embedding Model

> Disconnect from the VPN when running `podman run` for the first time.

When asked to choose a source while downloading an image, select Docker rather than Oracle Container Registry.

An embedding model is required to experiment with retrieval-augmented generation.

This example uses Nomic Embed Text. Another low-resource option is EmbeddingGemma 300M.

Create the embedding container:

```bash
podman run \
  -d \
  --name embedding \
  --add-host=host.containers.internal:host-gateway \
  -p 9000:11434 \
  -v ollama:/root/.ollama \
  ollama/ollama
```

Start the embedding model:

```bash
podman exec -d embedding ollama run nomic-embed-text
```

[Back to Table of Contents](#table-of-contents)

### Oracle Database 26ai

> Disconnect from the VPN when installing the database.

Oracle Database can be deployed quickly using Vagrant and VirtualBox. Oracle provides Vagrant projects for several products, including Oracle Database.

The projects are available at:

https://github.com/oracle/vagrant-projects

1. Download the ZIP file containing the Oracle Database 26ai software.

2. Go to the directory where the Vagrant projects will be stored.

3. Clone the repository:

   ```bash
   git clone https://github.com/oracle/vagrant-projects
   ```

4. Go to:

   ```text
   vagrant-projects/OracleDatabase/26ai
   ```

5. Copy the downloaded Oracle Database ZIP file into that directory.

6. Review `config.yml`.

   To modify the configuration, copy it to `config.local.yml` and make the changes there.

   Available configuration options include:

   * Virtual machine name
   * Virtual machine memory
   * Virtual machine system timezone
   * `oracle_base`
   * `oracle_home`
   * `oracle_sid`
   * `oracle_pdb`
   * Database character set
   * Listener port
   * Password for `SYS`, `SYSTEM`, and `PDBADMIN`

7. The Vagrant project uses `Vagrantfile` to orchestrate deployment of the virtual machine and database.

   The default settings should produce an operational environment, but it is recommended to add:

   ```ruby
   config.vm.boot_timeout = 10800
   ```

   Add it inside the main configuration section:

   ```ruby
   Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
     # ...
   end
   ```

   For example, add it after:

   ```ruby
   config.vm.hostname = VM_NAME
   ```

8. Deploy the VirtualBox machine with Oracle Database 26ai:

   ```bash
   vagrant up
   ```

[Back to Table of Contents](#table-of-contents)

## Troubleshooting

### Podman Bridge Network Error

Error:

```text
plugin type="bridge" failed (add): cni plugin bridge failed:
failed to set bridge addr: could not set bridge's mac: invalid argument
```

Run the following command whenever the error occurs:

```bash
podman network prune
```

[Back to Table of Contents](#table-of-contents)
