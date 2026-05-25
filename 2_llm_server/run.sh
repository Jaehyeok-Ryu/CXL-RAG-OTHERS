#!/bin/bash
# 2_llm_server 기동 스크립트

# 1. 스크립트 실행 경로를 본인이 위치한 폴더로 고정
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

NET="cxl_rag_network"
IMAGE_NAME="cxl_rag_llm"
CONTAINER_NAME="llm_inference_container"
LOG_DIR="$(pwd)/logs"
MODEL_DIR="$(realpath ../Data/Llama3-ChatQA-1.5-8B)"

# 네트워크 생성
docker network inspect $NET >/dev/null 2>&1 || docker network create $NET

# 로그 폴더 생성
mkdir -p "$LOG_DIR"

# 기존 컨테이너 종료
docker rm -f $CONTAINER_NAME >/dev/null 2>&1

echo " Building LLM Server Image..."
docker build -t $IMAGE_NAME .

echo " Starting LLM Container (Llama3-ChatQA-1.5-8B)..."
echo "   - Mounting Model: $MODEL_DIR"

docker run -d \
  --name $CONTAINER_NAME \
  --network $NET \
  -p 5000:5000 \
  -v "$MODEL_DIR":/app/model \
  -v "$LOG_DIR":/app/log \
  --gpus '"device=0"' \
  $IMAGE_NAME python3 /app/app.py \
    --cpu-server-ip=request_generator_container
