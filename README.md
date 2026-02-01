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


## UV shims (command wrappers)

This project installs small command wrappers (“shims”) into `~/.local/uv-shims` and prepends that directory to `PATH`. They are designed to make `uv` behave like a drop-in replacement for standard Python tooling, while consistently respecting pins and virtual environments.

### `python`

Runs Python via `uv run`, explicitly binding execution to the interpreter resolved by `uv`. This avoids ambiguity between system Pythons, uv-managed interpreters, and active pins. If the project requires a pinned Python version that is not installed, it may prompt to install it interactively.



### `pip`

Thin wrapper around `uv pip`, always operating on an explicitly selected interpreter.

* `-p, --python <path|version>`: select the interpreter explicitly
* if not provided, the interpreter resolved by `uv run python` is used



### `version`

Prints two lines: the `uv` version and the Python version. Python resolution follows this order: active virtual environment, `uv run` (with downloads disabled), system fallback, or `Python (none)` if nothing is available.



### `venv`

Shell function to create and/or activate a virtual environment in the current directory (default: `.venv`). If a venv already exists, it is simply activated; if you are already inside a venv, it refuses to nest. The prompt is adjusted to match `uv venv` behavior.

* `venv <dir>`: use a custom venv directory instead of `.venv`
* `-p, --python <path|version>`: select the interpreter for venv creation



### `lpin`

Shows or manages the **local** Python pin (`.python-version`) by walking up the directory tree.

* `lpin`:

  * prints `<version>` if pinned in the current directory
  * prints `(~path) <version>` if inherited from a parent
  * prints `(none)` if no local pin exists
* `lpin <path|version>`: set or update the local pin



### `gpin`

Shows or manages the **global** Python pin.

* `gpin`: prints the global pin or `(none)`
* `gpin <path|version>`: set the global pin
* `gpin none`: remove the global pin



### `interpreters`

Lists all detected Python interpreters at patch level (`cpython-X.Y.Z <path>`), marking one with `*`. Preference order is: current interpreter resolved by `uv run`, exact pinned version, highest patch of a pinned minor version.

Environment knobs are available to tune scanning behavior (`UV_SHIMS_SCAN_MNT`, `UV_SHIMS_FAST`, `UV_SHIMS_SKIP_UVDATA`).



### `uncache`

Garbage-collects the `uv` cache without assuming a fixed project layout.

Archive objects are removed when all contained files have a single hard link (`nlink == 1`). For cached wheels, only projects that are actually installed in **UV-managed virtual environments** are kept. Candidate projects are discovered under `~`, but only directories containing an exact `<dir>/.venv/pyvenv.cfg` are considered (no recursive project scanning).

Uses `UV_CACHE_DIR` if set, otherwise defaults to `~/.cache/uv`. Debug output can be enabled by setting `DEBUG=1` inside the script.



### `lock`

Exports dependencies from the active virtual environment into `pyproject.toml` and generates `uv.lock`. Requires `VIRTUAL_ENV` to be set.

* `--deps=env` (default): infer dependencies from installed distributions
* `--deps=src` / `-s`: infer dependencies by scanning Python imports in source files
* `--txt` / `-t`: additionally write a pinned `requirements.txt`

CUDA-related dependencies (names containing `nvidia` or `cuda`) are automatically placed under the optional dependency group `cuda`.


## How to manage SSH GitHub credentials

This container supports persistent SSH configuration via the `~/.ssh` volume and includes helper functions to create and manage repository-specific GitHub deploy keys.

Each private repository can have its own deploy key, while SSH still connects to the same host (`github.com`). The mechanism is: the container adds the generated key as an `IdentityFile` under the `Host github.com` block in `~/.ssh/config`, and keeps a local index mapping repositories to key names in `~/.ssh/github-repo-index`. This allows `prune-github-credentials` to remove unused keys safely.

**If the repository must be cloned from GitHub**

From the directory where you want the repository to be cloned, run `register-github-repo` with `--remote`:

```bash
register-github-repo --remote=git@github.com:<github-username>/<repo-name>.git
```

This will generate a new deploy key, add it as an `IdentityFile` under the `Host github.com` entry in `~/.ssh/config`, and print the public key you must add to the GitHub repository:

```bash
Output:

Generating public/private ed25519 key pair.
Your identification has been saved in /home/guest/.ssh/id_ed25519_repo_7892722528
Your public key has been saved in /home/guest/.ssh/id_ed25519_repo_7892722528.pub
The key fingerprint is:
SHA256:kF4Q9j9Jw7+Clt8hS5zE/tZQHcLpaiGchrRTFrVcVdY deploy-key-repo_7892722528
The key's randomart image is:
+--[ED25519 256]--+
|      +. .o...o.=|
|     . = +. o+ oE|
|      + O =o. ...|
|     . * O = .. .|
|      . S B +.   |
|         * =..   |
|        + O oo   |
|       . o *...  |
|          o.o    |
+----[SHA256]-----+
Include the following public key in your GitHub repository (Settings → Deploy keys → Add deploy key).
> ENDPOINT: https://github.com/<github-username>/<repo-name>/settings/keys
> PUBLIC KEY: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDzb6UYyc0qxw+VxWDJDHDPdeZ0mGjshoaZqP6wRD3X2 deploy-key-repo_7892722528
Continue with cloning [y/n]?
```

Open the `ENDPOINT` URL, add the shown `PUBLIC KEY` under “Deploy keys”, and then type `y` to continue. The function will retry cloning until it succeeds (useful if you just added the key and GitHub hasn’t propagated it yet):

```bash
Output:

Cloning into '<repo-name>'...
remote: Enumerating objects: 186, done.
remote: Counting objects: 100% (186/186), done.
remote: Compressing objects: 100% (136/136), done.
remote: Total 186 (delta 36), reused 181 (delta 31), pack-reused 0 (from 0)
Receiving objects: 100% (186/186), 311.15 KiB | 1.09 MiB/s, done.
Resolving deltas: 100% (36/36), done.
Repository registered in ssh config.
```

After this, the repository is already configured: future `git fetch/pull/push` will use SSH and the generated deploy key transparently.

---

**If the repository already exists locally (e.g., public repos cloned via HTTPS)**

Change directory into the local repository and register it to use a repository-specific deploy key:

```bash
cd <repo-name>
register-github-repo
```

This will generate a new deploy key, add it as an `IdentityFile` under the `Host github.com` entry in `~/.ssh/config`, and print the public key to be added to GitHub:

```bash
Output:

[...]
Include the following public key in your GitHub repository (Settings → Deploy keys → Add deploy key).
> PUBLIC KEY: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGZUiEhN+93/ilUL0o/ran7lfCJWlF46kHnEnPonFU5+ deploy-key-repo_7281203282
Repository registered in ssh config.
```

Add the key in GitHub (Repository → Settings → Deploy keys → Add deploy key). From that point on, Git operations in this repository will use SSH with the generated deploy key. If your `origin` was previously HTTPS, `register-github-repo` will switch it to the SSH form automatically.

Notes:

* Deploy keys are scoped to a single repository. This is generally safer than reusing one key across multiple repos.
* If you later delete a repository directory, you can run `prune-github-credentials` to remove unreferenced keys and keep `~/.ssh` tidy.
