#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status[cite: 3]

# --- Configuration ---
cd /workspace[cite: 3]

# --- 1. System Setup & ComfyUI Clone ---
if [ ! -d "ComfyUI" ]; then
    echo "Cloning ComfyUI..."
    git clone https://github.com/comfyanonymous/ComfyUI.git[cite: 3]
fi

cd ComfyUI[cite: 3]
echo "Updating ComfyUI..."
git pull[cite: 3]

# --- 2. Smart Dependency Caching ---
if [ ! -f ".requirements_installed" ]; then
    echo "Installing Python dependencies..."
    pip install --upgrade pip[cite: 3]
    pip install -r requirements.txt[cite: 3]
    pip install imageio-ffmpeg torchaudio dynamicprompts huggingface_hub requests[cite: 3]
    touch .requirements_installed[cite: 3]
else
    echo "Dependencies already installed. Skipping pip install."[cite: 3]
fi

# --- 3. GPU Verification ---
echo "Checking CUDA availability..."
python -c "import torch; print('CUDA Available:', torch.cuda.is_available(), '| GPU:', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'None')" || {
    echo "ERROR: Torch/CUDA check failed!"
    exit 1
}

# --- 4. Directory Setup ---
mkdir -p models/checkpoints[cite: 3]
mkdir -p models/diffusion_models[cite: 3]
mkdir -p models/text_encoders[cite: 3]
mkdir -p models/loras[cite: 3]
mkdir -p models/latent_upscale_models[cite: 3]
mkdir -p workflows

# --- 5. Custom Nodes Setup ---
cd custom_nodes[cite: 3]

if [ ! -d "ComfyUI-Manager" ]; then
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git[cite: 3]
fi

if [ ! -d "ComfyUI-LTXVideo" ]; then
    git clone https://github.com/Lightricks/ComfyUI-LTXVideo.git[cite: 3]
fi

if [ ! -d "ComfyUI-KJNodes" ]; then
    git clone https://github.com/kijai/ComfyUI-KJNodes.git[cite: 3]
fi

# Endpoint node for UI-to-API JSON conversion on port 8188
if [ ! -d "comfyui-workflow-to-api-converter-endpoint" ]; then
    git clone https://github.com/SethRobinson/comfyui-workflow-to-api-converter-endpoint.git
fi

# Install custom node requirements safely
if [ ! -f ".nodes_installed" ]; then
    [ -f "ComfyUI-LTXVideo/requirements.txt" ] && pip install -r ComfyUI-LTXVideo/requirements.txt[cite: 3]
    [ -f "ComfyUI-KJNodes/requirements.txt" ] && pip install -r ComfyUI-KJNodes/requirements.txt[cite: 3]
    touch .nodes_installed[cite: 3]
fi

cd ..[cite: 3]

# --- 6. Download GitHub Repo Files (With Fail-Safes) ---
echo "Fetching workflow and script files from GitHub..."
wget -q "https://raw.githubusercontent.com/asaf2019/script_test/main/workflow.json" -O workflows/workflow.json || {
    echo "ERROR: Failed to download workflow.json from GitHub!"
    exit 1
}

wget -q "https://raw.githubusercontent.com/asaf2019/script_test/main/run_workflow_api.py" -O run_workflow_api.py || {
    echo "ERROR: Failed to download run_workflow_api.py from GitHub!"
    exit 1
}

# --- 7. HuggingFace Authentication & Download Helper ---
AUTH_HEADER=""
if [ -n "$HF_TOKEN" ]; then
    echo "Using HuggingFace token..."[cite: 3]
    AUTH_HEADER="--header=Authorization: Bearer $HF_TOKEN"[cite: 3]
fi

download_model () {
    URL=$1
    OUTPUT=$2
    if [ -f "$OUTPUT" ]; then
        echo "Already exists: $OUTPUT"[cite: 3]
    else
        echo "Downloading: $OUTPUT"[cite: 3]
        wget $AUTH_HEADER "$URL" -O "$OUTPUT" || {[cite: 3]
            echo "ERROR: Failed to download model from $URL"
            exit 1
        }
    fi
}

# --- 8. Download LTX Essential Models ---
echo "Downloading LTX essential models..."[cite: 3]

download_model \
"https://huggingface.co/Lightricks/LTX-2.3-fp8/resolve/main/ltx-2.3-22b-distilled-fp8.safetensors" \
"models/diffusion_models/ltx-2.3-22b-distilled-fp8.safetensors"[cite: 3]

download_model \
"https://huggingface.co/Comfy-Org/ltx-2/resolve/main/split_files/text_encoders/gemma_3_12B_it_fp4_mixed.safetensors" \
"models/text_encoders/gemma_3_12B_it_fp4_mixed.safetensors"[cite: 3]

download_model \
"https://huggingface.co/Comfy-Org/ltx-2.3/resolve/main/split_files/loras/ltx_2.3_22b_distilled_1.1_lora_dynamic_fro09_avg_rank_111_bf16.safetensors" \
"models/loras/ltx_2.3_22b_distilled_1.1_lora_dynamic_fro09_avg_rank_111_bf16.safetensors"[cite: 3]

download_model \
"https://huggingface.co/Lightricks/LTX-2.3/resolve/main/ltx-2.3-spatial-upscaler-x2-1.1.safetensors" \
"models/latent_upscale_models/ltx-2.3-spatial-upscaler-x2-1.1.safetensors"[cite: 3]

# --- 9. Launch Auto-Trigger Background Worker ---
python run_workflow_api.py &

# --- 10. Start ComfyUI Server ---
echo "Setup complete! Launching ComfyUI..."[cite: 3]
python main.py \
  --listen 0.0.0.0 \
  --port 8188 \
  --enable-cors-header \
  --cuda-malloc[cite: 3]
