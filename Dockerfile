# FROM ubuntu:noble

# ARG UID=1098
# ARG GID=1002
# ARG USERNAME=guest

# ENV DEBIAN_FRONTEND=noninteractive

# RUN apt-get update \
#     && apt-get install -y --no-install-recommends \
#         bash \
#         ca-certificates \
#         curl \
#         git \
#         openssh-client \
#         sudo \
#         tmux \
#         tree \
#         build-essential \
#         libgmp-dev \
#         libcdd-dev \
#         micro \
#     && rm -rf /var/lib/apt/lists/*

# # Create user/group with requested UID/GID, reusing existing GID if needed
# RUN set -eux; \
#     if getent group "${GID}" >/dev/null; then \
#         EXISTING_GROUP="$(getent group "${GID}" | cut -d: -f1)"; \
#         useradd --uid "${UID}" --gid "${GID}" -m -s /bin/bash "${USERNAME}"; \
#         echo "Reused existing group ${EXISTING_GROUP} (GID=${GID})"; \
#     else \
#         groupadd --gid "${GID}" "${USERNAME}"; \
#         useradd --uid "${UID}" --gid "${GID}" -m -s /bin/bash "${USERNAME}"; \
#     fi; \
#     usermod -aG sudo "${USERNAME}"; \
#     echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# # Home scaffolding
# RUN mkdir -p "/home/${USERNAME}/.ssh" "/home/${USERNAME}/.config" "/home/${USERNAME}/.cache" \
#     && chmod 700 "/home/${USERNAME}/.ssh" \
#     && chown -R "${UID}:${GID}" "/home/${USERNAME}"

# # User shell config
# COPY --chown=${UID}:${GID} ./utils/bash.bashrc "/etc/bash.bashrc"
# COPY --chown=${UID}:${GID} ./utils/.bashrc "/home/${USERNAME}/.bashrc"

# # Copy .config dir
# COPY --chown=${UID}:${GID} ./utils/.config/ "/home/${USERNAME}/.config/"

# # Copy README.md
# COPY --chown=${UID}:${GID} ./README.md "/home/${USERNAME}/README.md"

# USER ${USERNAME}

# ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"
# # Compose can override; keep a default
# ENV UV_CACHE_DIR="/home/${USERNAME}/.cache/uv"

# RUN bash "/home/${USERNAME}/.config/uv/install.sh"

# CMD ["bash", "-lc", "sleep infinity"]







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
COPY --chown=${UID}:${GID} ./utils/bash.bashrc "/etc/bash.bashrc"
COPY --chown=${UID}:${GID} ./utils/.bashrc "/home/${USERNAME}/.bashrc"

# Copy .config dir
COPY --chown=${UID}:${GID} ./utils/.config/ "/home/${USERNAME}/.config/"

# Copy README.md
COPY --chown=${UID}:${GID} ./README.md "/home/${USERNAME}/README.md"

USER ${USERNAME}

ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"
# Compose can override; keep a default
ENV UV_CACHE_DIR="/home/${USERNAME}/.cache/uv"

RUN bash "/home/${USERNAME}/.config/uv/install.sh"

CMD ["bash", "-lc", "sleep infinity"]
