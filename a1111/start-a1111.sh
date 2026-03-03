#!/bin/bash
set -euo pipefail

WEBUI_DIR=/opt/stable-diffusion-webui
VENV_DIR=/opt/venv
CLIP_URL=https://github.com/openai/CLIP/archive/d50d76daa670286dd6cacf3bcd80b5e4823fc8e1.zip
TORCH_INDEX_URL=https://download.pytorch.org/whl/cu124

# -----------------------------
# Models to auto-download
# -----------------------------
MODEL_DIR="${WEBUI_DIR}/models/Stable-diffusion"
VAE_DIR="${WEBUI_DIR}/models/VAE"

PONY_CKPT_URL="https://huggingface.co/LyliaEngine/Pony_Diffusion_V6_XL/resolve/main/ponyDiffusionV6XL_v6StartWithThisOne.safetensors"
PONY_CKPT_NAME="ponyDiffusionV6XL_v6StartWithThisOne.safetensors"

PONY_VAE_URL="https://huggingface.co/LyliaEngine/Pony_Diffusion_V6_XL/resolve/main/sdxl_vae.safetensors"
PONY_VAE_NAME="sdxl_vae.pony.safetensors"

ENVY_URL="https://civitai.com/api/download/models/303767?type=Model&format=SafeTensor&size=pruned&fp=bf16"
ENVY_NAME="EnvyGachaXL01_pruned_bf16.safetensors"

cd "${WEBUI_DIR}"

download_file() {
  local url="$1"
  local out="$2"
  local tmp="${out}.part"

  if [ -s "${out}" ]; then
    echo "[models] Exists: ${out}"
    return 0
  fi

  mkdir -p "$(dirname "${out}")"
  echo "[models] Downloading: ${url}"
  echo "[models] -> ${out}"

  # Prefer wget if available, otherwise curl
  if command -v wget >/dev/null 2>&1; then
    # If CIVITAI_TOKEN is set and url is civitai, add Authorization header
    if [[ "${url}" == *"civitai.com"* ]] && [[ -n "${CIVITAI_TOKEN:-}" ]]; then
      wget --tries=5 --timeout=30 --no-verbose \
        --header="Authorization: Bearer ${CIVITAI_TOKEN}" \
        -O "${tmp}" "${url}"
    else
      wget --tries=5 --timeout=30 --no-verbose -O "${tmp}" "${url}"
    fi
  else
    if [[ "${url}" == *"civitai.com"* ]] && [[ -n "${CIVITAI_TOKEN:-}" ]]; then
      curl -L --fail --retry 5 --retry-delay 3 \
        -H "Authorization: Bearer ${CIVITAI_TOKEN}" \
        -o "${tmp}" "${url}"
    else
      curl -L --fail --retry 5 --retry-delay 3 -o "${tmp}" "${url}"
    fi
  fi

  mv -f "${tmp}" "${out}"
  echo "[models] Saved: $(ls -lh "${out}")"
}

# Ensure folders exist (they are bind-mounted from your host)
mkdir -p "${MODEL_DIR}" "${VAE_DIR}"

# Download models/vae if missing
download_file "${PONY_CKPT_URL}" "${MODEL_DIR}/${PONY_CKPT_NAME}"
download_file "${PONY_VAE_URL}" "${VAE_DIR}/${PONY_VAE_NAME}"
download_file "${ENVY_URL}"      "${MODEL_DIR}/${ENVY_NAME}"

# -----------------------------
# Your existing bootstrap
# -----------------------------
if [ ! -x "${VENV_DIR}/bin/python" ]; then
  echo "[bootstrap] Creating virtualenv at ${VENV_DIR}"
  python3 -m venv "${VENV_DIR}"
fi

BOOTSTRAP_STAMP="${VENV_DIR}/.bootstrap-cu124-v3"

if [ ! -f "${BOOTSTRAP_STAMP}" ]; then
  echo "[bootstrap] Repairing pip/setuptools/wheel"
  "${VENV_DIR}/bin/python" -m ensurepip --upgrade
  "${VENV_DIR}/bin/python" -m pip install --no-cache-dir --upgrade pip
  "${VENV_DIR}/bin/python" -m pip install --no-cache-dir --upgrade "setuptools==69.5.1" wheel packaging

  echo "[bootstrap] Installing CUDA PyTorch wheels"
  "${VENV_DIR}/bin/python" -m pip install --no-cache-dir \
    torch torchvision torchaudio \
    --index-url "${TORCH_INDEX_URL}"

  echo "[bootstrap] Installing CLIP workaround"
  "${VENV_DIR}/bin/python" -m pip install --no-cache-dir --no-build-isolation "${CLIP_URL}"
  "${VENV_DIR}/bin/python" -m pip install --no-cache-dir open-clip-torch

  touch "${BOOTSTRAP_STAMP}"
fi

echo "[bootstrap] Starting A1111"
echo "[bootstrap] COMMANDLINE_ARGS=${COMMANDLINE_ARGS:-<empty>}"

exec "${VENV_DIR}/bin/python" launch.py ${COMMANDLINE_ARGS:-}