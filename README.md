# DGX uv container

A Docker container for Python development on DGX systems, based on Ubuntu and preconfigured with `uv` for fast dependency management. The container is set up to persist and reuse cached dependencies via a mounted volume.


## User guide:

**Files**

- **README.md**: contains guidelines on the container’s features and usage
- **Dockerfile**: Dockerfile for the container image
- **docker-compose.yaml**: Docker Compose file
- **utils**: contains files and directories to be copied into the container
- **variables.sh**: contains the configuration for some container settings
- **up.sh**: starts the Compose setup
- **down.sh**: stops the Compose setup
- **attach.sh**: opens a shell in the Compose container

**Usage**

Start the compose (single container named: "${USER}-session"):
```bash
source up.sh
```
Attach to a terminal session of the container:
```bash
source attach.sh
```
Inside the container, save inside ~/data the files to be kept persistently:
```bash
la .
```
```bash
Output:

.bash_logout  .bashrc  .cache  .config  .local  .profile  .ssh  README.md  data
```
Terminate the container terminal session:
```bash
exit
```
Stop the compose and remove the container:
```bash
source down.sh
```


## Features
- Ubuntu-based image suitable for DGX environments
- `uv` preinstalled and ready to use
- Persistent `uv` cache via volume mounting to speed up repeated builds
- Automatic `uv` cache pruning at startup to remove unused dependencies without requiring user intervention
- Custom shims to simplify `uv` usage and environment management
- Persistent working directory mounted at ~/data
- Persistent ~/.ssh directory for SSH configuration and keys, useful for repository-specific deploy keys and seamless Git access
- Preinstalled set of commonly used development and system tools, including:
  - bash
  - ca-certificates
  - curl
  - git
  - openssh-client
  - sudo
  - tmux
  - tree
  - build-essential
  - libgmp-dev
  - libcdd-dev
  - micro


## Configuration variables (`variables.sh`)

The behavior of the container and its persistence model is controlled via `variables.sh`:
- **`PROJECT`**: Docker Compose project name. Controls container isolation and naming.
- **`CONTAINER_USER`**: User created and used inside the container (home directory, file ownership, attach user).
- **`HOST_VOLUME_DIR`**: Base directory on the host mounted into the container. All persistent data lives under this path.
- **`WORKDIR_HOST`**: Host directory mapped to `~/data` inside the container.
- **`SSH_HOST`**: Host directory mapped to `~/.ssh` for persistent SSH keys and config.
- **`UV_CACHE_HOST`**: Host directory used to persist the `uv` cache.

These variables define the container’s user, persistence layout, and session isolation.


## Cusom shims to manage uv
- **version**: shown both uv and python versions
- **python**: runs [uv python --python \<uv python selected interpreter\>]
- **pip**: runs [uv pip] or [uv python --python \<uv python selected interpreter\> -m pip] if inside standard Python venv
- **venv**: runs [uv venv .venv && source .venv/bin/activate] or just [source .venv/bin/activate] if environment already exist in cwd
- **gpin**: shows globally pinned Python interpreter version
- **gpin** <python interpreter path / python version>: pins Python interpreter globally
- **gpin** none: unpins globally pinned Python interpreter
- **lpin**: shows locally pinned Python interpreter version
- **lpin** <python interpreter path / python version>: pins Python interpreter locally
- **lpin** none: unpins locally pinned Python interpreter
- **interpreters**: shows all installed Python interpreters (marks with (*) uv python selected one)
- **uncache**: cleans from the uv cache python dependencies unreferenced by uv-manged environments
- **lock**: dumps dependencies installed in the active environment into `pyproject.toml` and `uv.lock`


## How to manage ssh Git credentials

This container supports persistent SSH configuration via the `~/.ssh` volume and includes predefined helper functions that make it easy to use repository-specific deploy keys.

**If the repository is private (requires key for cloning)**

First, generate a new repository-specific SSH deploy key and register it locally:

```bash
register-ssh-keys
```

This command creates a new SSH key pair and prints the public key along with a short alias that will identify the repository in your SSH configuration.

```bash
Output:

Include the following public key in your GitHub repository (Settings → Deploy keys → Add deploy key):
> PUBLIC KEY: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJBgQ+q+aNMCkD+8bRbWkLr/5At0XTpwQh7uJNnr3Yhd deploy-key-repo_3821357898
Then clone the repository, change directory to its root and run:
> register-ssh-host --alias=2v0zkmeriy
```

Clone the repository via ssh:

```bash
git clone git@github.com:<github-username>/<repo-name>.git
cd <repo-name>
```

Once inside the repository, update its Git remote to use the generated SSH host alias:

```bash
register-ssh-host --alias=<alias-given-by-register-ssh-keys>  # in this case it would be: 2v0zkmeriy
```

---

**If the repository is public**

Clone the repository via https:

```bash
git clone https://github.com/<github-username>/<repo-name>.git
```

Change into the repository directory and register it to use a repository-specific SSH deploy key:

```bash
cd <repo-name>
register-ssh-host
```

This will generate a new deploy key, add a corresponding SSH host entry, and print the public key to be added to GitHub:

```bash
Output:

[...]
Include the following public key in your GitHub repository (Settings → Deploy keys → Add deploy key).
> PUBLIC KEY: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGZUiEhN+93/ilUL0o/ran7lfCJWlF46kHnEnPonFU5+ deploy-key-repo_7281203282
Repository registered in ssh config.
```

After adding the key to GitHub, the repository will transparently use SSH with the deploy key for future Git operations.