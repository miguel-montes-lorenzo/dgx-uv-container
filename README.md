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

Define the following shell aliases to simplify the usage of the container helper scripts. It is recommended to add these lines to your host `~/.bashrc` (or equivalent shell configuration file) so they are always available.

```bash
alias up="chmod +x ./up.sh && ./up.sh"
alias attach="chmod +x ./attach.sh && ./attach.sh"
alias down="chmod +x ./down.sh && ./down.sh"
```

Start the compose (single container named: `${USER}-session`):
```bash
up
```
Attach to a terminal session of the container:
```bash
attach
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
down
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


## UV helpers (shell functions)

This project exposes a small set of shell helpers (added to `PATH`) to make common `uv` workflows feel like standard Python tooling, while respecting pins and virtual environments.

### `python`

Runs Python in the current context via `uv run` (honors pins / active project settings). If the project requires a pinned Python that is not installed, it may prompt to install it.

### `pip`

`pip`-like interface backed by `uv pip`.

* `-p, --python <path|version>`: pick the interpreter explicitly
* otherwise, uses the interpreter resolved for `uv run`

### `version`

Prints the `uv` version and the active Python version (prefers the current venv if one is active).

### `venv`

Create and/or activate a venv (default: `.venv`) in the current directory.

* `venv`: create `.venv` if missing, otherwise just activate it
* `venv <dir>`: create/replace and activate a venv at `<dir>`
* `-p, --python <path|version>`: choose interpreter for venv creation
* refuses to run if you are already inside a venv

### `lpin`

Show or set a local Python pin (`.python-version`) by walking up the directory tree.

* `lpin`: show the nearest pin (`(none)` if there is none)
* `lpin <path|version>`: set the local pin in the current directory
* `lpin none`: remove the nearest pin found in the parent chain

### `gpin`

Show or set the global Python pin.

* `gpin`: show global pin (`(none)` if unset)
* `gpin <path|version>`: set global pin
* `gpin none`: remove global pin

### `interpreters`

List detected Python interpreters (`cpython-X.Y.Z <path>`), marking the one currently used by `uv run` with `*`.

Environment knobs: `UV_SHIMS_SCAN_MNT`, `UV_SHIMS_FAST`, `UV_SHIMS_SKIP_UVDATA`.

### `uncache`

Garbage-collect the `uv` cache (archives, wheels, and `.rkyv` metadata), deleting entries that are not referenced by any installed environments. Set `UV_SHIMS_DEBUG=1` for verbose output.

### `environments`

Find and list Python virtual environments under a root directory (default: `~`). Marks likely uv-managed envs with `[uv]`.

* `UV_ENVS_ROOT`: scan root
* `UV_ENVS_WORKERS`: parallelism

### `lock`

Sync dependencies into `pyproject.toml` from the active environment (or from source imports), then run `uv lock`. Optionally emits a pinned `requirements.txt`.

* default: infer deps from the active env
* `--src` / `-s`: infer deps by scanning imports
* `--txt` / `-t`: also write `requirements.txt`



## How to manage SSH GitHub credentials

This container supports persistent SSH configuration via the `~/.ssh` volume and includes helper functions to create and manage repository-specific GitHub deploy keys.

Each repository uses its own SSH host alias instead of sharing a single `Host github.com` entry. The function writes a dedicated block to `~/.ssh/config`:

* `Host <generated-hostname>`
* `HostName github.com`
* `IdentityFile ~/.ssh/<keyname>`
* `IdentitiesOnly yes`

It also records an entry in `~/.ssh/github-repo-index`:

```
<abs_repo_path> <hostname> <keyname>
```

This index allows `prune-github-credentials` to safely remove stale configuration. The SSH config file is also normalized so it never contains more than one consecutive blank line.

---

**Registering the current local repository (no flags)**

From inside an existing Git repository:

```bash
register-github-repo
```

This will:

* Generate a new deploy key.
* Create or update a repo-specific `Host github-<...>` block in `~/.ssh/config`.
* Append `<abs_repo_path> <hostname> <keyname>` to `~/.ssh/github-repo-index`.
* Rewrite `origin` to the SSH host-alias form
  (`git@github-<...>:<owner>/<repo>.git`).
* Print the public key to add to GitHub:

```bash
Include the following public key in your GitHub repository (Settings → Deploy keys → Add deploy key).
> PUBLIC KEY: ssh-ed25519 AAAA... deploy-key-repo_<10-digit-id>
```

After adding the key in GitHub, normal `git fetch/pull/push` operations will work transparently through SSH.

---

**Registering the current local repository with an existing key (`--key`)**

If a private key already exists under `~/.ssh/<keyname>`:

```bash
register-github-repo --key=<keyname>
```

This will:

* Reuse the existing key (no new key is generated).
* Create/update the repo-specific `Host` block.
* Record the repo in `~/.ssh/github-repo-index`.
* Rewrite `origin` to the host-alias SSH form.

No public key is printed, since the key is assumed to already be installed in GitHub.

---

**Cloning a repository from GitHub (`--remote`)**

From the directory where the repository should be created:

```bash
register-github-repo --remote=git@github.com:<github-username>/<repo-name>.git
```

This will:

* Generate a new deploy key.
* Create/update a repo-specific `Host github-<...>` block.
* Print the public key and the GitHub deploy-key settings URL:

```bash
Include the following public key in your GitHub repository (Settings → Deploy keys → Add deploy key).
> ENDPOINT: https://github.com/<github-username>/<repo-name>/settings/keys
> PUBLIC KEY: ssh-ed25519 AAAA... deploy-key-repo_<10-digit-id>
Continue with cloning [y/n]?
```

After confirming with `y`, the function clones using the host alias
(`git@github-<...>:<owner>/<repo>.git`).
If cloning fails, it keeps prompting to retry, which is useful immediately after adding the deploy key.
On success, the repository is recorded in `~/.ssh/github-repo-index`.

---

**Cloning with an existing key (`--remote --key`)**

To reuse an existing private key:

```bash
register-github-repo \
  --remote=git@github.com:<github-username>/<repo-name>.git \
  --key=<keyname>
```

This will:

* Verify the key can access the repository (`git ls-remote` with that key).
* Create/update the repo-specific `Host` block.
* Clone using the host alias.
* Register the repo in `~/.ssh/github-repo-index`.

No new key is generated.

---

Notes:

* Deploy keys are scoped to a single repository, which is safer than sharing keys.
* If a repository directory is later removed, running `prune-github-credentials` cleans up unused SSH config entries and keys.