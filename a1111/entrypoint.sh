#!/usr/bin/env bash
set -euo pipefail

: "${WEBUI_DIR:=/home/sd/stable-diffusion-webui}"
: "${WEBUI_SRC_DIR:=/home/sd/stable-diffusion-webui-src}"
: "${WEBUI_DATA_DIR:=/data}"
: "${WEBUI_REPO:=https://github.com/AUTOMATIC1111/stable-diffusion-webui.git}"
: "${COMMANDLINE_ARGS:=--listen --port 7860 --api}"

: "${TORCH_INDEX_URL:=https://download.pytorch.org/whl/cu121}"
: "${TORCH_COMMAND:=pip install torch==2.1.2 torchvision==0.16.2 --extra-index-url ${TORCH_INDEX_URL}}"
: "${XFORMERS_PACKAGE:=xformers==0.0.23.post1}"
: "${CLIP_PACKAGE:=https://github.com/openai/CLIP/archive/d50d76daa670286dd6cacf3bcd80b5e4823fc8e1.zip}"
: "${OPENCLIP_PACKAGE:=https://github.com/mlfoundations/open_clip/archive/bb6e834e9c70d9c27d0dc3ecedeebeaeb1ffad6b.zip}"

: "${ASSETS_REPO:=https://github.com/AUTOMATIC1111/stable-diffusion-webui-assets.git}"
: "${ASSETS_COMMIT_HASH:=6f7db241d2f8ba7457bac5ca9753331f0c266917}"

: "${STABLE_DIFFUSION_REPO:=https://github.com/Stability-AI/stablediffusion.git}"
: "${STABLE_DIFFUSION_COMMIT_HASH:=cf1d67a6fd5ea1aa600c4df58e5b47da45f6bdbf}"

: "${STABLE_DIFFUSION_XL_REPO:=https://github.com/Stability-AI/generative-models.git}"
: "${STABLE_DIFFUSION_XL_COMMIT_HASH:=45c443b316737a4ab6e40413d7794a7f5657c19f}"

: "${K_DIFFUSION_REPO:=https://github.com/crowsonkb/k-diffusion.git}"
: "${K_DIFFUSION_COMMIT_HASH:=ab527a9a6d347f364e3d185ba6d714e22d80cb3c}"

: "${BLIP_REPO:=https://github.com/salesforce/BLIP.git}"
: "${BLIP_COMMIT_HASH:=48211a1594f1321b00f14c9f7a5b4813144b2fb9}"

: "${TAMING_TRANSFORMERS_REPO:=https://github.com/CompVis/taming-transformers.git}"

export GIT_TERMINAL_PROMPT=0
export HF_HOME="${HF_HOME:-/opt/hf-cache}"
export TRANSFORMERS_CACHE="${TRANSFORMERS_CACHE:-/opt/hf-cache/transformers}"
export TORCH_HOME="${TORCH_HOME:-/opt/torch-cache}"

echo "[A1111] whoami=$(whoami) uid=$(id -u) gid=$(id -g)"
echo "[A1111] WEBUI_DIR=${WEBUI_DIR}"
echo "[A1111] WEBUI_SRC_DIR=${WEBUI_SRC_DIR}"
echo "[A1111] WEBUI_DATA_DIR=${WEBUI_DATA_DIR}"
echo "[A1111] COMMANDLINE_ARGS=${COMMANDLINE_ARGS}"

mkdir -p "$(dirname "${WEBUI_DIR}")" "$(dirname "${WEBUI_SRC_DIR}")"

# 1) Clone webui to SRC (cached)
if [ ! -f "${WEBUI_SRC_DIR}/launch.py" ] && [ ! -f "${WEBUI_SRC_DIR}/webui.sh" ]; then
  echo "[A1111] Cloning webui into ${WEBUI_SRC_DIR}..."
  rm -rf "${WEBUI_SRC_DIR}" || true
  git clone --depth 1 "${WEBUI_REPO}" "${WEBUI_SRC_DIR}" 2>&1 | sed -u 's/^/[git] /'
fi

# 2) Sync to runtime dir (always idempotent)
mkdir -p "${WEBUI_DIR}"
echo "[A1111] Syncing webui to ${WEBUI_DIR}..."
rsync -a --delete --exclude '.git' "${WEBUI_SRC_DIR}/" "${WEBUI_DIR}/"

# 3) Detect REPO_ROOT (by launch.py)
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

# 4) Prepare /data mounts
mkdir -p "${WEBUI_DATA_DIR}/outputs" \
         "${WEBUI_DATA_DIR}/extensions" \
         "${WEBUI_DATA_DIR}/models/Stable-diffusion" \
         "${WEBUI_DATA_DIR}/models/Lora" \
         "${WEBUI_DATA_DIR}/models/VAE" \
         "${WEBUI_DATA_DIR}/models/ControlNet" \
         "${WEBUI_DATA_DIR}/models/ESRGAN" \
         "${WEBUI_DATA_DIR}/tmp"

rm -rf outputs extensions models || true
ln -s "${WEBUI_DATA_DIR}/outputs" outputs
ln -s "${WEBUI_DATA_DIR}/extensions" extensions
ln -s "${WEBUI_DATA_DIR}/models" models

# 5) Normalize line endings
dos2unix -q "${REPO_ROOT}/webui.sh" 2>/dev/null || true
dos2unix -q "${REPO_ROOT}/webui-user.sh" 2>/dev/null || true
find "${REPO_ROOT}" -maxdepth 2 -type f -name "*.sh" -exec dos2unix -q {} \; 2>/dev/null || true

# 6) Clone required repos (because you run with --skip-install and want deterministic startup)
mkdir -p repositories

clone_or_update() {
  local url="$1"
  local dir="$2"
  local ref="$3"
  local name="$4"

  if [ ! -d "${dir}/.git" ]; then
    echo "[A1111] Cloning ${name}..."
    rm -rf "${dir}" || true
    # IMPORTANT: recurse submodules to avoid missing ldm/modules/midas, etc.
    git clone --config core.filemode=false --recurse-submodules "${url}" "${dir}" 2>&1 | sed -u 's/^/[git] /'
  else
    echo "[A1111] Updating ${name}..."
    git -C "${dir}" fetch --all --tags 2>&1 | sed -u 's/^/[git] /' || true
  fi

  if [ -n "${ref}" ]; then
    echo "[A1111] Checkout ${name}: ${ref}"
    git -C "${dir}" checkout "${ref}" 2>&1 | sed -u 's/^/[git] /' || true
  fi

  # IMPORTANT: submodules must be initialized/updated after checkout as well
  if [ -f "${dir}/.gitmodules" ]; then
    echo "[A1111] Updating submodules for ${name}..."
    git -C "${dir}" submodule sync --recursive 2>&1 | sed -u 's/^/[git] /' || true
    git -C "${dir}" submodule update --init --recursive 2>&1 | sed -u 's/^/[git] /'
  fi
}

# Assets
clone_or_update "${ASSETS_REPO}" "repositories/stable-diffusion-webui-assets" "${ASSETS_COMMIT_HASH}" "assets"

# Stable Diffusion (this one must include midas)
# If you previously cloned without submodules, force re-clone once to fix it
if [ -d "repositories/stable-diffusion-stability-ai/.git" ] && [ ! -d "repositories/stable-diffusion-stability-ai/ldm/modules/midas" ]; then
  echo "[A1111] Detected broken stable-diffusion-stability-ai (missing ldm/modules/midas). Re-cloning with submodules..."
  rm -rf "repositories/stable-diffusion-stability-ai" || true
fi

clone_or_update "${STABLE_DIFFUSION_REPO}" "repositories/stable-diffusion-stability-ai" "${STABLE_DIFFUSION_COMMIT_HASH}" "Stable Diffusion"

if [ ! -d "repositories/stable-diffusion-stability-ai/ldm/modules/midas" ]; then
  echo "[A1111] ERROR: midas module still missing at repositories/stable-diffusion-stability-ai/ldm/modules/midas"
  echo "[A1111] Debug tree:"
  find "repositories/stable-diffusion-stability-ai/ldm/modules" -maxdepth 3 -type d -print || true
  exit 1
fi

# SDXL, k-diffusion, BLIP
clone_or_update "${STABLE_DIFFUSION_XL_REPO}" "repositories/generative-models" "${STABLE_DIFFUSION_XL_COMMIT_HASH}" "Stable Diffusion XL"
clone_or_update "${K_DIFFUSION_REPO}" "repositories/k-diffusion" "${K_DIFFUSION_COMMIT_HASH}" "k-diffusion"
clone_or_update "${BLIP_REPO}" "repositories/BLIP" "${BLIP_COMMIT_HASH}" "BLIP"

# 7) Create venv in REPO_ROOT
if [ ! -x "${REPO_ROOT}/venv/bin/python" ]; then
  echo "[A1111] Creating venv..."
  python3 -m venv "${REPO_ROOT}/venv"
fi

VENV_PY="${REPO_ROOT}/venv/bin/python"

echo "[A1111] Pin pip toolchain..."
"${VENV_PY}" -m pip install -U "pip<25" "setuptools<70" "wheel" 2>&1 | sed -u 's/^/[pip] /'

# 8) Install torch/torchvision (GPU)
echo "[A1111] Installing torch/torchvision via TORCH_COMMAND..."
"${VENV_PY}" -m ${TORCH_COMMAND} 2>&1 | sed -u 's/^/[torch] /'

# 9) Install CLIP + open_clip
echo "[A1111] Installing CLIP..."
"${VENV_PY}" -m pip install --no-cache-dir "${CLIP_PACKAGE}" 2>&1 | sed -u 's/^/[clip] /'

echo "[A1111] Installing open_clip..."
"${VENV_PY}" -m pip install --no-cache-dir "${OPENCLIP_PACKAGE}" 2>&1 | sed -u 's/^/[open_clip] /'

# 10) Install xformers only if user asked for it
if [[ "${COMMANDLINE_ARGS}" == *"--xformers"* ]]; then
  echo "[A1111] Installing xformers (best-effort, no-deps)..."
  "${VENV_PY}" -m pip install --no-cache-dir -U -I --no-deps "${XFORMERS_PACKAGE}" 2>&1 | sed -u 's/^/[xformers] /' || true
fi

# 11) Install webui python requirements
if [ -f "${REPO_ROOT}/requirements_versions.txt" ]; then
  echo "[A1111] Installing requirements_versions.txt..."
  "${VENV_PY}" -m pip install --no-cache-dir -r "${REPO_ROOT}/requirements_versions.txt" 2>&1 | sed -u 's/^/[req] /'
fi

if [ -f "${REPO_ROOT}/requirements.txt" ]; then
  echo "[A1111] Installing requirements.txt..."
  "${VENV_PY}" -m pip install --no-cache-dir -r "${REPO_ROOT}/requirements.txt" 2>&1 | sed -u 's/^/[req] /'
fi

# 12) Ensure `import taming` exists (fixes `No module named taming`)
echo "[A1111] Ensuring taming module is available..."

"${VENV_PY}" -m pip install --no-cache-dir "taming-transformers-rom1504" 2>&1 | sed -u 's/^/[taming-pip] /' || true

if ! "${VENV_PY}" -c "import taming" >/dev/null 2>&1; then
  echo "[A1111] taming not importable after pip; installing from taming-transformers repo..."
  clone_or_update "${TAMING_TRANSFORMERS_REPO}" "repositories/taming-transformers" "" "taming-transformers"
  "${VENV_PY}" -m pip install --no-cache-dir -e "${REPO_ROOT}/repositories/taming-transformers" 2>&1 | sed -u 's/^/[taming-repo] /'
fi

echo "[A1111] Sanity check: taming import..."
"${VENV_PY}" -c "import taming; print('OK taming:', taming.__file__)"

# 13) Start WebUI
echo "[A1111] Starting launch.py..."
exec "${VENV_PY}" -u launch.py ${COMMANDLINE_ARGS}