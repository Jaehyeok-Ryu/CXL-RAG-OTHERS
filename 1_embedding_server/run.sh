#!/bin/bash
# 1_embedding_server 기동 스크립트
# Usage: ./run.sh [VECTORDB_IP]

# 1. 스크립트 실행 경로를 본인이 위치한 폴더로 고정
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

VECTORDB_IP=${1:-"163.152.48.208"} # 기본값으로 기존 CPU/Qdrant IP 지정

NET="cxl_rag_network"
IMAGE_NAME="cxl_rag_embedding"
CONTAINER_NAME="embedding_container_async"
LOG_DIR="$(pwd)/logs"
MODEL_DIR="$(realpath ../Data/bge-base-en-v1.5)"

# 네트워크 생성
docker network inspect $NET >/dev/null 2>&1 || docker network create $NET

# 로그 폴더 생성
mkdir -p "$LOG_DIR"

# 기존 컨테이너 종료
docker rm -f $CONTAINER_NAME >/dev/null 2>&1

echo "🚀 Building Embedding Server Image..."
docker build -t $IMAGE_NAME .

echo "🎬 Starting Embedding Container (BGE 768-dim)..."
echo "   - Mounting Model: $MODEL_DIR"
echo "   - Connecting Qdrant at: $VECTORDB_IP:6333"

docker run -d \
  --name $CONTAINER_NAME \
  --network $NET \
  -p 5003:5003 \
  -v "$MODEL_DIR":/app/model \
  -v "$LOG_DIR":/app/log \
  --gpus '"device=0"' \
  $IMAGE_NAME python3 /app/app.py \
    --cpu-server-ip=request_generator_container \
    --gpu-server-ip=llm_inference_container \
    --vectordb-ip="$VECTORDB_IP"
