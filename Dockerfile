FROM ubuntu:noble

ARG UID=1098
ARG GID=1002
ARG USERNAME=guest

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        git \
        openssh-client \
        sudo \
        tmux \
        tree \
        build-essential \
        libgmp-dev \
        libcdd-dev \
        micro \
    && rm -rf /var/lib/apt/lists/*

# Create user/group with requested UID/GID, reusing existing GID if needed
RUN set -eux; \
    if getent group "${GID}" >/dev/null; then \
        EXISTING_GROUP="$(getent group "${GID}" | cut -d: -f1)"; \
        useradd --uid "${UID}" --gid "${GID}" -m -s /bin/bash "${USERNAME}"; \
        echo "Reused existing group ${EXISTING_GROUP} (GID=${GID})"; \
    else \
        groupadd --gid "${GID}" "${USERNAME}"; \
        useradd --uid "${UID}" --gid "${GID}" -m -s /bin/bash "${USERNAME}"; \
    fi; \
    usermod -aG sudo "${USERNAME}"; \
    echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Home scaffolding
RUN mkdir -p "/home/${USERNAME}/.ssh" "/home/${USERNAME}/.config" "/home/${USERNAME}/.cache" \
    && chmod 700 "/home/${USERNAME}/.ssh" \
    && chown -R "${UID}:${GID}" "/home/${USERNAME}"

# User shell config
COPY --chown=${UID}:${GID} ./utils/system/bash.bashrc "/etc/bash.bashrc"
COPY --chown=${UID}:${GID} ./utils/system/.bashrc "/home/${USERNAME}/.bashrc"

# Copy .config dir
COPY --chown=${UID}:${GID} ./utils/.config/ "/home/${USERNAME}/.config/"

# Copy README.md
COPY --chown=${UID}:${GID} ./README.md "/home/${USERNAME}/README.md"

USER ${USERNAME}

ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"
# Compose can override; keep a default
ENV UV_CACHE_DIR="/home/${USERNAME}/.cache/uv"

# This installs uv
RUN bash "/home/${USERNAME}/.config/uv/install.sh"

# Ensure uv is visible in non-interactive RUN steps
ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"
ENV UV_TOOL_BIN_DIR="/home/${USERNAME}/.local/bin"

# Install ruff as a uv-managed tool
RUN uv tool install ruff --force
RUN uv tool install ty --force
RUN uv tool install pytest --force
RUN uv tool install "dvc[ssh,s3,gcs,azure]" --force

CMD ["bash", "-lc", "sleep infinity"]
