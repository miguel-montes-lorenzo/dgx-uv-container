FROM ubuntu:noble

# TO BE PARSED FROM docker-compose.yaml
ARG UID=
ARG GID=
ARG USERNAME=


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
        gawk \
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

USER ${USERNAME}

CMD ["bash", "-lc", "sleep infinity"]
