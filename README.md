# DGX uv container

A Docker container for Python development on DGX systems, based on Ubuntu and preconfigured with `uv` for fast dependency management. The container is set up to persist and reuse cached dependencies via a mounted volume.


## Features
- Ubuntu-based image suitable for DGX environments
- `uv` preinstalled and ready to use
- Persistent `uv` cache via volume mounting to speed up repeated builds
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


## How to manage ssh Git credentials
This container supports persistent SSH configuration via the `~/.ssh` volume, making it easy to use
repository-specific deploy keys.

**1. Generate an ed25519 deploy key**

Generate a dedicated key per repository:

```bash
ssh-keygen -t ed25519 \
  -C "deploy-key-<repo-name>" \
  -f ~/.ssh/id_ed25519_<repo-name> \
  -N ""
```

Set secure permissions:

```bash
chmod 600 ~/.ssh/id_ed25519_<repo-name>
chmod 644 ~/.ssh/id_ed25519_<repo-name>.pub
```

**2. Add the deploy key to GitHub**

In the GitHub repository:
`Settings → Deploy keys → Add deploy key`

Paste the contents of:

```bash
cat ~/.ssh/id_ed25519_<repo-name>.pub
```

Enable **“Allow write access”** if needed.

**3. Configure `~/.ssh/config`**

Map the repository to its deploy key:

```ssh
Host <custom-id-related-with-repo>  # e.g.: github.com-<repo-name>
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_<repo-name>
  IdentitiesOnly yes
  StrictHostKeyChecking yes
```

Set permissions and verify access:

```bash
chmod 600 ~/.ssh/config
ssh-keyscan -H <custom-id-related-with-repo> >> ~/.ssh/known_hosts
ssh -T git@github.com
```

> Note. Uncomment ./utils/.bashrc line [# DISPLAY_README_AT_STARTUP=false] to avoid displaying README.md at container startup.