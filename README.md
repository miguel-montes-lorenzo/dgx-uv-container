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
- **prune**: cleans from the uv cache python dependencies unreferenced by uv-manged environments


## How to manage ssh Git credentials
This container supports persistent SSH configuration via the `~/.ssh` volume, making it easy to use
repository-specific deploy keys.

**1. Generate an ed25519 deploy key**

Generate a dedicated key per repository:

```bash
ssh-keygen -t ed25519 \
  -C "deploy-key-<repo-alias>" \
  -f ~/.ssh/id_ed25519_<repo-alias> \
  -N ""
```

Set secure permissions:

```bash
chmod 600 ~/.ssh/id_ed25519_<repo-alias>
chmod 644 ~/.ssh/id_ed25519_<repo-alias>.pub
```

**2. Add the deploy key to GitHub**

In the GitHub repository:
`Settings → Deploy keys → Add deploy key`

Paste the contents of:

```bash
cat ~/.ssh/id_ed25519_<repo-alias>.pub
```

Enable **“Allow write access”** if needed.

**3. Configure `~/.ssh/config`**

Map the repository to its deploy key:

```ssh
Host <host-alias>  # e.g.: github.com-<repo-alias>
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_<repo-alias>
  IdentitiesOnly yes
  StrictHostKeyChecking yes
```

Set permissions and verify access:

```bash
chmod 600 ~/.ssh/config
ssh-keyscan -H <host-alias> >> ~/.ssh/known_hosts
ssh -T git@github.com
```

**4. Point the repository remote to the SSH host alias**

Update origin to use the host alias:

```bash
cd <repo-local-dir>
git remote get-url origin  # this shows remote direction
# e.g. git@github.com-dgx-uv:miguel-montes-lorenzo/dgx-uv-container.git
git remote set-url origin <host-alias>:<owner>/<repo>.git
```

or in one line:

```bash
cd <repo-local-dir>
git remote set-url origin "$(git remote get-url origin | sed 's/^git@github\.com:/git@github.com-<repo-name>:/')"
```

Push the commits to the remote:

```bash
git remote -v  # check remote direction is correctly set
git push
```
