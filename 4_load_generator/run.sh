#!/bin/bash
# 4_load_generator 기동 스크립트
# Usage: ./run.sh [VECTORDB_IP_1] [VECTORDB_IP_2] [TARGET_RPS] [REQUESTS_COUNT] [SCRIPT_TYPE: normal|zipf|no_async_zipf]

# 1. 스크립트 실행 경로를 본인이 위치한 폴더로 고정
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Load environment variables from .env file if it exists
if [ -f "$SCRIPT_DIR/../.env" ]; then
  export $(grep -v '^#' "$SCRIPT_DIR/../.env" | xargs)
fi

VECTORDB_IP_1=${1:-${VECTORDB_IP_1:-"127.0.0.1"}}    # Socket 0 Qdrant IP (Default: CPU Server)
VECTORDB_IP_2=${2:-${VECTORDB_IP_2:-"127.0.0.1"}}    # Socket 1 Qdrant IP (Default: CPU Server)
TARGET_RPS=${3:-"100.0"}                # Target RPS (요청률)
REQUESTS_COUNT=${4:-"2000"}             # 총 요청 수
SCRIPT_TYPE=${5:-"normal"}              # 실행 모드 (Default: normal - 균등 임의 분포)

# 모드별 타겟 파이썬 파일 매핑
if [ "$SCRIPT_TYPE" == "zipf" ]; then
  PY_SCRIPT="load_generator_zipf.py"
elif [ "$SCRIPT_TYPE" == "normal" ]; then
  PY_SCRIPT="load_generator.py"
elif [ "$SCRIPT_TYPE" == "no_async_zipf" ]; then
  PY_SCRIPT="load_generator_no_async_zipf.py"
else
  echo "❌ Error: Invalid SCRIPT_TYPE '$SCRIPT_TYPE'. Use 'normal', 'zipf', or 'no_async_zipf'."
  exit 1
fi

NET="cxl_rag_network"
IMAGE_NAME="cxl_rag_loadgen"
CONTAINER_NAME="load_generator_container"
DATASET_DIR="$(realpath ../Data/NQ_default_embedded_question_7830)"

# NUMA 및 CPU 바인딩 환경변수 (필요 시 외부에서 주입 가능)
# 예: LOADGEN_CPUS="0-11" LOADGEN_MEM_NODE="0" ./run.sh ...
CPUS_FLAG=""
if [ ! -z "$LOADGEN_CPUS" ]; then
  CPUS_FLAG="--cpuset-cpus=$LOADGEN_CPUS"
fi

MEMS_FLAG=""
if [ ! -z "$LOADGEN_MEMS" ]; then
  MEMS_FLAG="--cpuset-mems=$LOADGEN_MEMS"
fi

# 네트워크 생성
docker network inspect $NET >/dev/null 2>&1 || docker network create $NET

# 기존 컨테이너 종료
docker rm -f $CONTAINER_NAME >/dev/null 2>&1

echo "🚀 Building Load Generator Image..."
docker build -t $IMAGE_NAME .

echo "🎬 Starting Load Generator Container..."
echo "   - Mounting Embedded Dataset: $DATASET_DIR"
echo "   - Running Script: $PY_SCRIPT"
echo "   - Target VectorDB 1: $VECTORDB_IP_1:6333"
echo "   - Target VectorDB 2: $VECTORDB_IP_2:6343"
echo "   - Target RPS: $TARGET_RPS, Request Count: $REQUESTS_COUNT"
if [ ! -z "$CPUS_FLAG" ] || [ ! -z "$MEMS_FLAG" ]; then
  echo "   - NUMA/CPU Bindings: $CPUS_FLAG $MEMS_FLAG"
fi

docker run -d \
  --name $CONTAINER_NAME \
  --network $NET \
  $CPUS_FLAG \
  $MEMS_FLAG \
  -v "$DATASET_DIR":/app/loadgen_dataset \
  $IMAGE_NAME python3 /app/$PY_SCRIPT \
    --dataset-dir='/app/loadgen_dataset' \
    --collection-name='wiki_passages' \
    --target-rps="$TARGET_RPS" \
    --requests-count="$REQUESTS_COUNT" \
    --qdrant-host-1="$VECTORDB_IP_1" \
    --qdrant-port-1=6333 \
    --qdrant-host-2="$VECTORDB_IP_2" \
    --qdrant-port-2=6343
