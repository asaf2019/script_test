#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# --- Configuration ---
cd /workspace

# --- 0. Network & DNS Readiness Check ---
echo "Verifying network connectivity..."
until getent hosts raw.githubusercontent.com &>/dev/null; do
    echo "Waiting for DNS and network to initialize..."
    sleep 2
done
echo "Network connection established!"

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
    echo "Installing Python dependencies..."
    pip install --upgrade pip
    pip install -r requirements.txt
    pip install imageio-ffmpeg torchaudio dynamicprompts huggingface_hub requests
    touch .requirements_installed
else
    echo "Dependencies already installed. Skipping pip install."
fi

# --- 3. GPU Verification ---
echo "Checking CUDA availability..."
python -c "import torch; print('CUDA Available:', torch.cuda.is_available(), '| GPU:', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'None')" || {
    echo "ERROR: Torch/CUDA check failed!"
    exit 1
}

# --- 4. Directory Setup ---
mkdir -p models/checkpoints
mkdir -p models/diffusion_models
mkdir -p models/text_encoders
mkdir -p models/loras
mkdir -p models/latent_upscale_models
mkdir -p workflows

# --- 5. Custom Nodes Setup ---
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

# Endpoint node for UI-to-API JSON conversion on port 8188
if [ ! -d "comfyui-workflow-to-api-converter-endpoint" ]; then
    git clone https://github.com/SethRobinson/comfyui-workflow-to-api-converter-endpoint.git
fi

# Install custom node requirements safely
if [ ! -f ".nodes_installed" ]; then
    [ -f "ComfyUI-LTXVideo/requirements.txt" ] && pip install -r ComfyUI-LTXVideo/requirements.txt
    [ -f "ComfyUI-KJNodes/requirements.txt" ] && pip install -r ComfyUI-KJNodes/requirements.txt
    touch .nodes_installed
fi

cd ..

# --- 6. Download GitHub Repo Files (With Fail-Safes & Retries) ---
echo "Fetching workflow and script files from GitHub..."
wget --tries=5 --retry-connrefused -q "https://raw.githubusercontent.com/asaf2019/script_test/main/workflow.json" -O workflows/workflow.json || {
    echo "ERROR: Failed to download workflow.json from GitHub!"
    exit 1
}

wget --tries=5 --retry-connrefused -q "https://raw.githubusercontent.com/asaf2019/script_test/main/run_workflow_api.py" -O run_workflow_api.py || {
    echo "ERROR: Failed to download run_workflow_api.py from GitHub!"
    exit 1
}

# --- 7. HuggingFace Authentication & Download Helper ---
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
        wget --tries=5 --retry-connrefused $AUTH_HEADER "$URL" -O "$OUTPUT" || {
            echo "ERROR: Failed to download model from $URL"
            exit 1
        }
    fi
}

# --- 8. Download LTX Essential Models ---
echo "Downloading LTX essential models..."

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

# --- 9. Launch Auto-Trigger Background Worker ---
python run_workflow_api.py &

# --- 10. Start ComfyUI Server ---
echo "Setup complete! Launching ComfyUI..."
python main.py \
  --listen 0.0.0.0 \
  --port 8188 \
  --enable-cors-header \
  --cuda-malloc
