#!/bin/bash
set -e

# --- Configuration ---
# Add HF_TOKEN in RunPod Environment Variables if downloading gated files
cd /workspace

# --- 1. System Setup & ComfyUI Clone ---
if [ ! -d "ComfyUI" ]; then
    echo "Cloning ComfyUI..."
    git clone https://github.com/comfyanonymous/ComfyUI.git
fi

cd ComfyUI

echo "Updating ComfyUI..."
git pull

# --- 2. Smart Dependency Caching ---
if [ ! -f ".requirements_installed" ]; then
    echo "Installing Python dependencies (First-time setup)..."
    pip install --upgrade pip
    pip install -r requirements.txt
    pip install imageio-ffmpeg torchaudio dynamicprompts huggingface_hub
    touch .requirements_installed
else
    echo "Dependencies already installed. Skipping pip install."
fi

# --- 3. Directory Setup ---
mkdir -p models/checkpoints
mkdir -p models/diffusion_models
mkdir -p models/text_encoders
mkdir -p models/loras
mkdir -p models/latent_upscale_models

# --- 4. Custom Nodes Setup ---
cd custom_nodes

if [ ! -d "ComfyUI-Manager" ]; then
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git
fi

if [ ! -d "ComfyUI-LTXVideo" ]; then
    git clone https://github.com/Lightricks/ComfyUI-LTXVideo.git
fi

if [ ! -d "ComfyUI-KJNodes" ]; then
    git clone https://github.com/kijai/ComfyUI-KJNodes.git
fi

# Install custom node requirements safely
if [ ! -f ".nodes_installed" ]; then
    [ -f "ComfyUI-LTXVideo/requirements.txt" ] && pip install -r ComfyUI-LTXVideo/requirements.txt
    [ -f "ComfyUI-KJNodes/requirements.txt" ] && pip install -r ComfyUI-KJNodes/requirements.txt
    touch .nodes_installed
fi

cd ..

# --- 5. HuggingFace Authentication & Download Helper ---
AUTH_HEADER=""
if [ -n "$HF_TOKEN" ]; then
    echo "Using HuggingFace token..."
    AUTH_HEADER="--header=Authorization: Bearer $HF_TOKEN"
fi

download_model () {
    URL=$1
    OUTPUT=$2
    if [ -f "$OUTPUT" ]; then
        echo "Already exists: $OUTPUT"
    else
        echo "Downloading: $OUTPUT"
        wget $AUTH_HEADER "$URL" -O "$OUTPUT"
    fi
}

# --- 6. Download LTX Essential Models ---
echo "Downloading LTX essential models..."

# Placed in diffusion_models for native ComfyUI / LTXVModelLoader compatibility
download_model \
"https://huggingface.co/Lightricks/LTX-2.3-fp8/resolve/main/ltx-2.3-22b-distilled-fp8.safetensors" \
"models/diffusion_models/ltx-2.3-22b-distilled-fp8.safetensors"

download_model \
"https://huggingface.co/Comfy-Org/ltx-2/resolve/main/split_files/text_encoders/gemma_3_12B_it_fp4_mixed.safetensors" \
"models/text_encoders/gemma_3_12B_it_fp4_mixed.safetensors"

download_model \
"https://huggingface.co/Comfy-Org/ltx-2.3/resolve/main/split_files/loras/ltx_2.3_22b_distilled_1.1_lora_dynamic_fro09_avg_rank_111_bf16.safetensors" \
"models/loras/ltx_2.3_22b_distilled_1.1_lora_dynamic_fro09_avg_rank_111_bf16.safetensors"

download_model \
"https://huggingface.co/Lightricks/LTX-2.3/resolve/main/ltx-2.3-spatial-upscaler-x2-1.1.safetensors" \
"models/latent_upscale_models/ltx-2.3-spatial-upscaler-x2-1.1.safetensors"

# --- 7. GPU Verification ---
python - <<EOF
import torch
print("PyTorch Version:", torch.__version__)
if torch.cuda.is_available():
    print("GPU:", torch.cuda.get_device_name(0))
    print("VRAM:", round(torch.cuda.get_device_properties(0).total_memory / 1024**3,2),"GB")
else:
    print("WARNING: CUDA not detected")
EOF

# --- 8. Start ComfyUI Server ---
echo "Setup complete! Launching ComfyUI..."
python main.py \
  --listen 0.0.0.0 \
  --port 8188 \
  --enable-cors-header \
  --cuda-malloc