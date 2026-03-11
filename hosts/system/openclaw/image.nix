{ pkgs, ... }:
let
  baseImage = "ghcr.io/phioranex/openclaw-docker:latest";
  customImage = "openclaw-custom:latest";
in
{
  # Build custom image on-device (native docker build, no qemu)
  systemd.services.openclaw-builder = {
    description = "Build custom OpenClaw image with Docker CLI";
    before = [
      "docker-openclaw-gateway.service"
      "docker-openclaw-cli.service"
    ];
    requiredBy = [
      "docker-openclaw-gateway.service"
      "docker-openclaw-cli.service"
    ];
    path = [ pkgs.docker ];
    script = ''
        docker build -t ${customImage} - <<'EOF'
      FROM ${baseImage}
      USER root
      # Clean apt cache first + update (robust against partial state)
      RUN rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* && \
          apt-get update && \
          apt-get install -y --no-install-recommends \
            git curl jq nodejs python3-pip build-essential ca-certificates && \
          rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*
      # Install uv to /usr/local/bin (accessible by non-root user)
      RUN curl -LsSf https://github.com/astral-sh/uv/releases/download/0.5.0/uv-aarch64-unknown-linux-gnu.tar.gz | \
          tar -xzf - --strip-components=1 -C /usr/local/bin uv-aarch64-unknown-linux-gnu/uv uv-aarch64-unknown-linux-gnu/uvx && \
          chmod +x /usr/local/bin/uv /usr/local/bin/uvx
      # Install Docker CLI binary (arm64 variant for rocknas)
      RUN curl -fsSL https://download.docker.com/linux/static/stable/aarch64/docker-26.1.3.tgz | \
          tar -xzf - --strip-components=1 -C /usr/local/bin docker/docker && \
          chmod +x /usr/local/bin/docker && \
          ln -sf /usr/local/bin/docker /usr/bin/docker
      # Make node user member of docker group (for docker.sock access)
      RUN groupadd -g 131 docker 2>/dev/null || true && \
          usermod -aG docker node
      # Ensure docker binary is executable by non-root (redundant after chmod +x above, but safe)
      RUN chmod 755 /usr/local/bin/docker
      # Pre-create dirs for non-root agent + fix perms
      RUN mkdir -p /var/lib/apt/lists/partial /var/cache/apt/archives/partial \
                   /home/node/.cache/uv /home/node/.local/share/uv \
                   /tmp /dev/shm && \
          chown -R 1000:1000 /home/node /tmp && \
          chmod -R 1777 /tmp /dev/shm && \
          chown -R _apt:root /var/lib/apt /var/cache/apt 2>/dev/null || true
      # Your openclaw wrapper
      RUN printf '#!/bin/sh\nexec node /app/dist/index.js "$@"\n' > /usr/local/bin/openclaw && \
          chmod +x /usr/local/bin/openclaw
      # Pre-install ClawSec skill to staging dir (copied to workspace/skills by openclaw-setup)
      # clawhub creates: /opt/openclaw-skills/skills/<name>/ and /opt/openclaw-skills/.clawhub/
      RUN mkdir -p /opt/openclaw-skills && \
          cd /opt/openclaw-skills && \
          npx clawhub@latest install clawsec-suite
      # Optional: global git safe if cloning inside containers later
      RUN git config --global --add safe.directory '*'
      USER 1000:1000
      EOF
    '';
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "300";
    };
  };
}
