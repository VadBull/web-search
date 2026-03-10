# syntax=docker/dockerfile:1

FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    GIT_TERMINAL_PROMPT=0 \
    PIP_DEFAULT_TIMEOUT=1000 \
    WEBUI_REPO="https://github.com/AUTOMATIC1111/stable-diffusion-webui.git" \
    STABLE_DIFFUSION_REPO="https://github.com/w-e-w/stablediffusion.git" \
    GENERATIVE_MODELS_REPO="https://github.com/Stability-AI/generative-models.git" \
    BLIP_REPO="https://github.com/salesforce/BLIP.git" \
    K_DIFFUSION_REPO="https://github.com/crowsonkb/k-diffusion.git" \
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
 && chown -R ${USERNAME}:${USERNAME} \
      /data \
      /opt/hf-cache /opt/torch-cache \
      /opt/scripts \
      /home/${USERNAME}/stable-diffusion-webui \
      /home/${USERNAME}/stable-diffusion-webui-src \
 && chmod -R 775 /data

RUN cat > /opt/scripts/entrypoint.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${STABLE_DIFFUSION_COMMIT_HASH:=main}"
: "${GENERATIVE_MODELS_COMMIT_HASH:=45c443b316737a4ab6e40413d7794a7f5657c19f}"
: "${BLIP_COMMIT_HASH:=48211a1594f1321b00f14c9f7a5b4813144b2fb9}"
: "${K_DIFFUSION_COMMIT_HASH:=ab527a9a6d347f364e3d185ba6d714e22d80cb3c}"

: "${WEBUI_DIR:=/home/sd/stable-diffusion-webui}"
: "${WEBUI_SRC_DIR:=/home/sd/stable-diffusion-webui-src}"
: "${WEBUI_DATA_DIR:=/data}"

: "${WEBUI_REPO:=https://github.com/AUTOMATIC1111/stable-diffusion-webui.git}"
: "${STABLE_DIFFUSION_REPO:=https://github.com/w-e-w/stablediffusion.git}"
: "${GENERATIVE_MODELS_REPO:=https://github.com/Stability-AI/generative-models.git}"
: "${BLIP_REPO:=https://github.com/salesforce/BLIP.git}"
: "${K_DIFFUSION_REPO:=https://github.com/crowsonkb/k-diffusion.git}"

: "${COMMANDLINE_ARGS:=--listen --port 7860 --api}"

export GIT_TERMINAL_PROMPT=0
export PIP_DEFAULT_TIMEOUT="${PIP_DEFAULT_TIMEOUT:-1000}"

echo "[A1111] whoami=$(whoami) uid=$(id -u) gid=$(id -g)"
echo "[A1111] WEBUI_DIR=${WEBUI_DIR}"
echo "[A1111] WEBUI_SRC_DIR=${WEBUI_SRC_DIR}"
echo "[A1111] WEBUI_DATA_DIR=${WEBUI_DATA_DIR}"
echo "[A1111] COMMANDLINE_ARGS=${COMMANDLINE_ARGS}"

mkdir -p "$(dirname "${WEBUI_DIR}")" "$(dirname "${WEBUI_SRC_DIR}")"

clone_or_update_repo() {
  local repo_url="$1"
  local dir="$2"
  local ref="$3"
  local label="$4"

  if [ ! -d "${dir}/.git" ]; then
    echo "[A1111] Cloning ${label}..."
    rm -rf "${dir}" || true
    git clone "${repo_url}" "${dir}" 2>&1 | sed -u 's/^/[git] /'
  else
    echo "[A1111] Updating ${label}..."
    git -C "${dir}" fetch --all --tags 2>&1 | sed -u 's/^/[git] /' || true
  fi

  echo "[A1111] Checkout ${label}: ${ref}"
  git -C "${dir}" checkout "${ref}" 2>&1 | sed -u 's/^/[git] /' || true
}

# 1) webui source
if [ ! -f "${WEBUI_SRC_DIR}/launch.py" ] && [ ! -f "${WEBUI_SRC_DIR}/webui.sh" ]; then
  echo "[A1111] Cloning webui into ${WEBUI_SRC_DIR}..."
  rm -rf "${WEBUI_SRC_DIR}" || true
  git clone --depth 1 "${WEBUI_REPO}" "${WEBUI_SRC_DIR}" 2>&1 | sed -u 's/^/[git] /'
fi

# 2) sync into runtime dir
mkdir -p "${WEBUI_DIR}"
if [ ! -f "${WEBUI_DIR}/launch.py" ] && [ ! -f "${WEBUI_DIR}/webui.sh" ]; then
  echo "[A1111] Syncing webui to ${WEBUI_DIR}..."
  rsync -a --delete --exclude '.git' "${WEBUI_SRC_DIR}/" "${WEBUI_DIR}/"
fi

# 3) detect repo root
if [ -f "${WEBUI_DIR}/launch.py" ]; then
  REPO_ROOT="${WEBUI_DIR}"
elif [ -f "${WEBUI_DIR}/stable-diffusion-webui/launch.py" ]; then
  REPO_ROOT="${WEBUI_DIR}/stable-diffusion-webui"
else
  echo "[A1111] ERROR: launch.py not found under ${WEBUI_DIR}"
  find "${WEBUI_DIR}" -maxdepth 4 -name launch.py -print || true
  exit 1
fi

echo "[A1111] REPO_ROOT=${REPO_ROOT}"
cd "${REPO_ROOT}"

# 4) volume-backed dirs
mkdir -p "${WEBUI_DATA_DIR}/outputs" \
         "${WEBUI_DATA_DIR}/extensions" \
         "${WEBUI_DATA_DIR}/models/Stable-diffusion" \
         "${WEBUI_DATA_DIR}/models/Lora" \
         "${WEBUI_DATA_DIR}/models/VAE" \
         "${WEBUI_DATA_DIR}/models/ControlNet" \
         "${WEBUI_DATA_DIR}/models/ESRGAN"

rm -rf outputs extensions models || true
ln -s "${WEBUI_DATA_DIR}/outputs" outputs
ln -s "${WEBUI_DATA_DIR}/extensions" extensions
ln -s "${WEBUI_DATA_DIR}/models" models

# 5) normalize line endings
dos2unix -q "${REPO_ROOT}/webui.sh" 2>/dev/null || true
dos2unix -q "${REPO_ROOT}/webui-user.sh" 2>/dev/null || true
find "${REPO_ROOT}" -maxdepth 2 -type f -name "*.sh" -exec dos2unix -q {} \; 2>/dev/null || true

# 6) required repos
mkdir -p repositories
clone_or_update_repo "${STABLE_DIFFUSION_REPO}" "repositories/stable-diffusion" "${STABLE_DIFFUSION_COMMIT_HASH}" "stable-diffusion"
clone_or_update_repo "${GENERATIVE_MODELS_REPO}" "repositories/generative-models" "${GENERATIVE_MODELS_COMMIT_HASH}" "generative-models"
clone_or_update_repo "${BLIP_REPO}" "repositories/BLIP" "${BLIP_COMMIT_HASH}" "BLIP"
clone_or_update_repo "${K_DIFFUSION_REPO}" "repositories/k-diffusion" "${K_DIFFUSION_COMMIT_HASH}" "k-diffusion"

# 7) force legacy path to point at working repo
rm -rf "repositories/stable-diffusion-stability-ai" || true
ln -sfn "${REPO_ROOT}/repositories/stable-diffusion" "${REPO_ROOT}/repositories/stable-diffusion-stability-ai"
echo "[A1111] stable-diffusion-stability-ai -> stable-diffusion symlink set"

# 8) venv
if [ ! -x "${REPO_ROOT}/venv/bin/python" ]; then
  echo "[A1111] Creating venv..."
  python3 -m venv "${REPO_ROOT}/venv"
fi

echo "[A1111] Pinning pip toolchain..."
"${REPO_ROOT}/venv/bin/python" -m pip install -U "pip<25" "setuptools<70" "wheel" 2>&1 | sed -u 's/^/[pip] /'

echo "[A1111] Installing base runtime deps..."
"${REPO_ROOT}/venv/bin/python" -m pip install \
  packaging \
  taming-transformers-rom1504 \
  --timeout 1000 \
  --retries 20 \
  2>&1 | sed -u 's/^/[pip] /'

echo "[A1111] Sanity check imports..."
"${REPO_ROOT}/venv/bin/python" -c "import packaging.version, taming; print('packaging+taming OK')"

echo "[A1111] Installing torch/torchvision (cu121) with retries..."
"${REPO_ROOT}/venv/bin/python" -m pip install \
  --timeout 1000 \
  --retries 20 \
  --index-url "https://download.pytorch.org/whl/cu121" \
  "torch==2.1.2" "torchvision==0.16.2" \
  2>&1 | sed -u 's/^/[torch] /'

# clear pip cache before requirements to avoid broken cached artifacts
"${REPO_ROOT}/venv/bin/python" -m pip cache purge || true

# 9) install requirements without --hash
if [ -f "${REPO_ROOT}/requirements_versions.txt" ]; then
  echo "[A1111] Installing sanitized requirements_versions.txt (without --hash)..."
  awk '
    {
      gsub(/ --hash=sha256:[^ ]+/, "")
      if ($0 !~ /^[[:space:]]*$/) print
    }
  ' "${REPO_ROOT}/requirements_versions.txt" > /tmp/requirements_versions.nohash.txt

  "${REPO_ROOT}/venv/bin/python" -m pip install \
    --timeout 1000 \
    --retries 20 \
    -r /tmp/requirements_versions.nohash.txt \
    2>&1 | sed -u 's/^/[req] /'
fi

# 10) clip without deps
echo "[A1111] Installing CLIP (--no-deps)..."
"${REPO_ROOT}/venv/bin/python" -m pip install \
  --timeout 1000 \
  --retries 20 \
  --no-build-isolation \
  --no-deps \
  "git+https://github.com/openai/CLIP.git@d50d76daa670286dd6cacf3bcd80b5e4823fc8e1" \
  2>&1 | sed -u 's/^/[clip] /'

export PIP_NO_CACHE_DIR=1

# avoid second install pass inside A1111
if [[ "${COMMANDLINE_ARGS}" != *"--skip-install"* ]]; then
  COMMANDLINE_ARGS="${COMMANDLINE_ARGS} --skip-install"
fi

echo "[A1111] Starting launch.py..."
exec "${REPO_ROOT}/venv/bin/python" -u launch.py ${COMMANDLINE_ARGS}
EOF

RUN chmod +x /opt/scripts/entrypoint.sh \
 && dos2unix -q /opt/scripts/entrypoint.sh || true

USER sd
WORKDIR /home/sd
EXPOSE 7860
ENTRYPOINT ["/opt/scripts/entrypoint.sh"]