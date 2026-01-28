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
