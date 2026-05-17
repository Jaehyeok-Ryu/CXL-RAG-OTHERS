#!/bin/bash
# 3_request_generator 기동 스크립트
# Usage: ./run.sh [TARGET_QPS] [QUERY_COUNT]

# 1. 스크립트 실행 경로를 본인이 위치한 폴더로 고정
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

TARGET_QPS=${1:-"2.0"}      # 기본값 2.0 QPS
QUERY_COUNT=${2:-"100"}     # 기본값 100 쿼리

NET="cxl_rag_network"
IMAGE_NAME="cxl_rag_reqgen"
CONTAINER_NAME="request_generator_container"
QUESTION_DIR="$(realpath ../Data/NQ_default_question_7830)"

# 네트워크 생성
docker network inspect $NET >/dev/null 2>&1 || docker network create $NET

# 기존 컨테이너 종료
docker rm -f $CONTAINER_NAME >/dev/null 2>&1

echo "🚀 Building Request Generator Image..."
docker build -t $IMAGE_NAME .

echo "🎬 Starting Request Generator Container..."
echo "   - Mounting Question Dataset: $QUESTION_DIR"
echo "   - Target QPS: $TARGET_QPS, Query Count: $QUERY_COUNT"

docker run -d \
  --name $CONTAINER_NAME \
  --network $NET \
  -p 6000:6000 \
  -v "$QUESTION_DIR":/app/questions \
  $IMAGE_NAME python3 /app/app.py \
    --question-dir=/app/questions \
    --target-qps="$TARGET_QPS" \
    --query-count="$QUERY_COUNT" \
    --gpu-server-ip=embedding_container_async
