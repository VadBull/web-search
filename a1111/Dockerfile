# syntax=docker/dockerfile:1

FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    GIT_TERMINAL_PROMPT=0 \
    WEBUI_REPO="https://github.com/AUTOMATIC1111/stable-diffusion-webui.git" \
    WEBUI_DIR="/home/sd/stable-diffusion-webui" \
    WEBUI_SRC_DIR="/home/sd/stable-diffusion-webui-src" \
    WEBUI_DATA_DIR="/data" \
    HF_HOME="/opt/hf-cache" \
    TRANSFORMERS_CACHE="/opt/hf-cache/transformers" \
    TORCH_HOME="/opt/torch-cache"

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    curl \
    wget \
    bzip2 \
    xz-utils \
    unzip \
    rsync \
    ffmpeg \
    libgl1 \
    libglib2.0-0 \
    python3 \
    python3-venv \
    python3-pip \
    python3-dev \
    build-essential \
    pkg-config \
    libffi-dev \
    libssl-dev \
    dos2unix \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m pip install --no-cache-dir -U pip setuptools wheel

ARG USERNAME=sd
ARG UID=1000
ARG GID=1000

RUN groupadd -g ${GID} ${USERNAME} \
 && useradd -m -u ${UID} -g ${GID} -s /bin/bash ${USERNAME} \
 && mkdir -p /opt/scripts /data /opt/hf-cache /opt/torch-cache \
 && mkdir -p /home/${USERNAME}/stable-diffusion-webui /home/${USERNAME}/stable-diffusion-webui-src \
 && chown -R ${USERNAME}:${USERNAME} /data /opt/hf-cache /opt/torch-cache /opt/scripts \
      /home/${USERNAME}/stable-diffusion-webui /home/${USERNAME}/stable-diffusion-webui-src \
 && chmod -R 775 /data

# IMPORTANT: entrypoint.sh лежит рядом с Dockerfile (в build context)
COPY entrypoint.sh /opt/scripts/entrypoint.sh

RUN chmod +x /opt/scripts/entrypoint.sh \
 && dos2unix -q /opt/scripts/entrypoint.sh || true \
 && chown ${USERNAME}:${USERNAME} /opt/scripts/entrypoint.sh

USER sd
WORKDIR /home/sd
EXPOSE 7860
ENTRYPOINT ["/opt/scripts/entrypoint.sh"]