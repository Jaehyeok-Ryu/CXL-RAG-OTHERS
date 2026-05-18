#!/bin/bash
set -e

# =========================================================================
# 🚀 CXL 2nd Year Mid - Dataset & Model Setup Automation Script
# =========================================================================
# * Description: Uses the pre-built 'loadgen_image' to download and preprocess
#                everything within a clean, isolated docker container.
# * Output directories under CXL_2nd_year_mid/Data/:
#     1) NQ_default_question_7830 (Raw text questions)
#     2) NQ_default_embedded_question_7830 (1024-dim BGE embeddings)
# =========================================================================

# 1. Determine script directory and resolve project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

echo "========================================================================="
echo "⚙️  Start Zero-Dependency Dataset & Model Setup (Containerized Method)"
echo "========================================================================="

# 2. Create host Data directory if it doesn't exist
mkdir -p Data

# 3. Check and build preprocess image
if ! docker image inspect cxl_rag_preprocess:latest >/dev/null 2>&1; then
    echo "⚙️ Building cxl_rag_preprocess Docker image..."
    docker build -t cxl_rag_preprocess -f "$SCRIPT_DIR/Dockerfile" "$SCRIPT_DIR"
fi

echo "✅ cxl_rag_preprocess image detected."

# 4. Step 1: Download Google Natural Questions (NQ) dataset
echo "-------------------------------------------------------------------------"
echo "📥 Step 1: Downloading Google NQ Dataset from Hugging Face..."
echo "-------------------------------------------------------------------------"
if [ -d "$PROJECT_ROOT/Data/NQ_default" ]; then
    echo "⚠️  [Skip] Data/NQ_default already exists. Skipping download."
    echo "✅ Step 1 Complete."
else
    docker run --rm \
      -u $(id -u):$(id -g) \
      -e HF_HOME=/hf_cache \
      -v ~/.cache/huggingface:/hf_cache \
      -v "$PROJECT_ROOT":/workspace \
      cxl_rag_preprocess python3 /workspace/5_dataset_builder/download_huggingface.py \
                            --hf-dir="google-research-datasets/natural_questions" \
                            --save-dir="/workspace/Data/NQ_default"
    echo "✅ Step 1 Complete."
fi

# 5. Step 2: Download 768-dimensional BGE-base-en-v1.5 Embedding Model
echo "-------------------------------------------------------------------------"
echo "📥 Step 2: Downloading BGE-base-en-v1.5 Embedding Model..."
echo "-------------------------------------------------------------------------"
if [ -d "$PROJECT_ROOT/Data/bge-base-en-v1.5" ]; then
    echo "⚠️  [Skip] Data/bge-base-en-v1.5 already exists. Skipping download."
    echo "✅ Step 2 Complete."
else
    docker run --rm \
      -u $(id -u):$(id -g) \
      -e HF_HOME=/hf_cache \
      -v ~/.cache/huggingface:/hf_cache \
      -v "$PROJECT_ROOT":/workspace \
      cxl_rag_preprocess python3 /workspace/5_dataset_builder/download_huggingface.py \
                            --embedding-model "BAAI/bge-base-en-v1.5" \
                            --save-dir="/workspace/Data/bge-base-en-v1.5"
    echo "✅ Step 2 Complete."
fi

# 6. Step 3: Preprocess NQ dataset and generate 768-dim BGE Embeddings
echo "-------------------------------------------------------------------------"
echo "🧠 Step 3: Preprocessing NQ Dataset & Generating 768-dim Embeddings..."
echo "-------------------------------------------------------------------------"
if [ -d "$PROJECT_ROOT/Data/NQ_default_question_7830" ] && [ -d "$PROJECT_ROOT/Data/NQ_default_embedded_question_7830" ]; then
    echo "⚠️  [Skip] Preprocessed datasets (7830 questions & embeddings) already exist."
else
    docker run --rm \
      -u $(id -u):$(id -g) \
      -v "$PROJECT_ROOT":/workspace \
      cxl_rag_preprocess python3 /workspace/5_dataset_builder/question_to_embedding.py \
                            --dataset-dir="/workspace/Data/NQ_default" \
                            --split="validation" \
                            --embedding-model-dir="/workspace/Data/bge-base-en-v1.5" \
                            --store-question \
                            --store-embedding
fi

# 7. Step 4: Download and serialize Llama3-ChatQA-1.5-8B LLM model (Real Physical Files)
echo "-------------------------------------------------------------------------"
echo "📥 Step 4: Downloading & Serializing Llama3-ChatQA-1.5-8B LLM (Real Files)..."
echo "-------------------------------------------------------------------------"
if [ -d "$PROJECT_ROOT/Data/Llama3-ChatQA-1.5-8B" ] && [ -f "$PROJECT_ROOT/Data/Llama3-ChatQA-1.5-8B/config.json" ]; then
    echo "⚠️  [Skip] Data/Llama3-ChatQA-1.5-8B already exists. Skipping download."
    echo "✅ Step 4 Complete."
else
    # 기존 빈 폴더 혹은 깨진 링크 강제 청소
    rm -rf "$PROJECT_ROOT/Data/Llama3-ChatQA-1.5-8B"
    
    docker run --rm \
      -u $(id -u):$(id -g) \
      -e HF_HOME=/hf_cache \
      -v ~/.cache/huggingface:/hf_cache \
      -v "$PROJECT_ROOT":/workspace \
      cxl_rag_preprocess python3 /workspace/5_dataset_builder/download_huggingface.py \
                            --llm "nvidia/Llama3-ChatQA-1.5-8B" \
                            --save-dir="/workspace/Data/Llama3-ChatQA-1.5-8B"
    
    # 토크나이저 클래스 오버라이드 버그 즉시 패치 적용 (CXL 안정성 확보)
    if [ -f "$PROJECT_ROOT/Data/Llama3-ChatQA-1.5-8B/tokenizer_config.json" ]; then
        echo "🔧 Applying tokenizer class patch to prevent class load failures..."
        sed -i 's/"tokenizer_class": "TokenizersBackend"/"tokenizer_class": "PreTrainedTokenizerFast"/g' "$PROJECT_ROOT/Data/Llama3-ChatQA-1.5-8B/tokenizer_config.json"
    fi
    echo "✅ Step 4 Complete."
fi

echo "========================================================================="
echo "🎉 Setup Complete! All Data and Real Model Weights are ready for Experiments."
echo "Created directories under Data/:"
echo "  📂 Data/NQ_default (Natural Questions Dataset)"
echo "  📂 Data/bge-base-en-v1.5 (768-dim Embedding Model)"
echo "  📂 Data/NQ_default_question_7830 (Preprocessed Questions)"
echo "  📂 Data/NQ_default_embedded_question_7830 (BGE Embeddings)"
echo "  📂 Data/Llama3-ChatQA-1.5-8B (Raw LLM Weights & Tokenizer - Pure Real Files)"
echo "========================================================================="

