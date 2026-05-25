#!/bin/bash
# ==============================================================================
# run_basic_benchmark.sh
# ==============================================================================
# 이 스크립트는 RAG Request Generator와 Qdrant Load Generator를 유기적으로 연동하여
# 동시성 테스트를 수행합니다. 
# 
# 전체 목표 RPS가 n일 때:
#   - Request Generator (실제 RAG 쿼리): 0.5 QPS 고정 (1000 쿼리 발송)
#   - Load Generator (백그라운드 스트레스): n - 0.5 RPS 동적 할당
# ==============================================================================

set -e

# 스크립트 실행 경로를 본인이 위치한 폴더로 고정
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# 기본 매개변수 설정
TOTAL_RPS=${1:-"10.0"}

# Load environment variables from root .env file if it exists
if [ -f "$SCRIPT_DIR/../../../.env" ]; then
  export $(grep -v '^#' "$SCRIPT_DIR/../../../.env" | xargs)
fi

VECTORDB_IP_1=${2:-${VECTORDB_IP_1:-"127.0.0.1"}}
VECTORDB_IP_2=${3:-${VECTORDB_IP_2:-"127.0.0.1"}}
QUERY_COUNT=${4:-"1000"}

# ------------------------------------------------------------------------------
# [입력 인자 검증 - Security Input Validation]
# ------------------------------------------------------------------------------
# 1. TOTAL_RPS 검증: 숫자 또는 소수점 형식만 허용 (Command Injection 방지)
if [[ ! "$TOTAL_RPS" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  echo "❌ [Error] Invalid TOTAL_RPS: '$TOTAL_RPS'. 숫자(정수/소수)만 입력 가능합니다." >&2
  exit 1
fi

# 2. VECTORDB_IP_1 / IP_2 검증: 유효한 IPv4 주소 또는 호스트네임 형식만 허용
IP_REGEX="^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$"
HOST_REGEX="^[a-zA-Z0-9.-]+$"
if [[ ! "$VECTORDB_IP_1" =~ $IP_REGEX ]] && [[ ! "$VECTORDB_IP_1" =~ $HOST_REGEX ]]; then
  echo "❌ [Error] Invalid VECTORDB_IP_1: '$VECTORDB_IP_1'. 올바른 IP 또는 호스트명을 입력하십시오." >&2
  exit 1
fi
if [[ ! "$VECTORDB_IP_2" =~ $IP_REGEX ]] && [[ ! "$VECTORDB_IP_2" =~ $HOST_REGEX ]]; then
  echo "❌ [Error] Invalid VECTORDB_IP_2: '$VECTORDB_IP_2'. 올바른 IP 또는 호스트명을 입력하십시오." >&2
  exit 1
fi

# 3. QUERY_COUNT 검증: 자연수만 허용
if [[ ! "$QUERY_COUNT" =~ ^[0-9]+$ ]] || [ "$QUERY_COUNT" -eq 0 ]; then
  echo "❌ [Error] Invalid QUERY_COUNT: '$QUERY_COUNT'. 1 이상의 정수만 허용됩니다." >&2
  exit 1
fi
# ------------------------------------------------------------------------------


# RPS 배분 계산 (Float 계산을 위해 bc 사용)
REQGEN_RPS="0.5"
LOADGEN_RPS=$(echo "$TOTAL_RPS - $REQGEN_RPS" | bc -l)

# Load Generator 가동 기준 검증 (n <= 0.5 이면 비활성화)
IS_LOADGEN_ACTIVE=1
if (( $(echo "$LOADGEN_RPS <= 0" | bc -l) )); then
  IS_LOADGEN_ACTIVE=0
  LOADGEN_RPS="0"
fi

# 경로 정의 (절대 경로 보장)
QUESTION_DIR="$(realpath ../../Data/NQ_default_question_7830)"
DATASET_DIR="$(realpath ../../Data/NQ_default_embedded_question_7830)"
REQGEN_DIR="$(realpath ../../3_request_generator)"
LOADGEN_DIR="$(realpath ../../4_load_generator)"

echo "========================================================================="
echo "⚙️  Starting RAG & Load Generator Integrated Orchestration"
echo "========================================================================="
echo "   - Total Target RPS (n)  : $TOTAL_RPS"
echo "   - Request Generator RPS : $REQGEN_RPS (Query Count: $QUERY_COUNT)"
echo "   - Load Generator RPS    : $LOADGEN_RPS (Active: $IS_LOADGEN_ACTIVE)"
echo "   - Qdrant VectorDB 1     : $VECTORDB_IP_1:6333"
echo "   - Qdrant VectorDB 2     : $VECTORDB_IP_2:6343"
echo "   - Mounting Question Dir : $QUESTION_DIR"
echo "   - Mounting Dataset Dir  : $DATASET_DIR"
echo "========================================================================="

# 1. 기존 컨테이너 깔끔하게 정리
echo "[INFO] Cleaning up any existing containers..."
docker rm -f request_generator_container load_generator_container >/dev/null 2>&1 || true

# 2. 공용 도커 브리지 네트워크 확인 및 구성
NET="cxl_rag_network"
docker network inspect $NET >/dev/null 2>&1 || docker network create $NET

# 3. Request Generator 결과 디렉토리 초기화
mkdir -p "$REQGEN_DIR/results"
chmod 777 "$REQGEN_DIR/results"
rm -f "$REQGEN_DIR/results"/*

# 4. 각 디렉토리에서 최신 소스코드로 도커 이미지 빌드
echo "[INFO] Building Docker Images..."
docker build -t cxl_rag_reqgen "$REQGEN_DIR"
if [ $IS_LOADGEN_ACTIVE -eq 1 ]; then
  docker build -t cxl_rag_loadgen "$LOADGEN_DIR"
fi

# 5. Load Generator 시작 및 웜업 (15초 대기)
if [ $IS_LOADGEN_ACTIVE -eq 1 ]; then
  echo "[INFO] Launching Load Generator (Background Stress) at $LOADGEN_RPS RPS..."
  docker run -d \
    --name load_generator_container \
    --network $NET \
    -v "$DATASET_DIR":/app/loadgen_dataset \
    cxl_rag_loadgen python3 /app/load_generator.py \
      --dataset-dir='/app/loadgen_dataset' \
      --collection-name='wiki_passages' \
      --target-rps="$LOADGEN_RPS" \
      --requests-count="1000000" \
      --qdrant-host-1="$VECTORDB_IP_1" \
      --qdrant-port-1=6333 \
      --qdrant-host-2="$VECTORDB_IP_2" \
      --qdrant-port-2=6343

  echo "[INFO] Waiting 15 seconds for the load generator to stabilize (Warm-up)..."
  sleep 15
else
  echo "[INFO] Load Generator is bypassed (Target RPS <= 0.5)."
fi

# 6. Request Generator 실행
echo "[INFO] Launching Request Generator (RAG Queries) at $REQGEN_RPS QPS..."
docker run -d \
  --name request_generator_container \
  --network $NET \
  -p 6000:6000 \
  -v "$QUESTION_DIR":/app/questions \
  -v "$REQGEN_DIR/results":/app/results \
  cxl_rag_reqgen python3 /app/app.py \
    --question-dir=/app/questions \
    --target-qps="$REQGEN_RPS" \
    --query-count="$QUERY_COUNT" \
    --gpu-server-ip=embedding_container_async \
    --results-dir=/app/results

echo "[INFO] Both components started successfully!"
echo "[INFO] Monitoring Request Generator execution status..."

# 7. Request Generator 컨테이너 종료 대기
START_TIME=$(date +%s)
while true; do
  if ! docker ps --format '{{.Names}}' | grep -q "^request_generator_container$"; then
    echo "[SUCCESS] Request Generator completed and exited."
    break
  fi
  ELAPSED=$(( $(date +%s) - START_TIME ))
  echo "⏱️  Running benchmark... [Elapsed: ${ELAPSED}s]"
  sleep 10
done

# 8. Load Generator 정지 및 정리
if [ $IS_LOADGEN_ACTIVE -eq 1 ]; then
  echo "[INFO] Stopping background Load Generator..."
  docker stop load_generator_container >/dev/null 2>&1 || true
  docker rm load_generator_container >/dev/null 2>&1 || true
fi

# 9. 결과 백업 및 이동
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_SAVE_DIR="$SCRIPT_DIR/results/run_RPS_${TOTAL_RPS}_${TIMESTAMP}"
mkdir -p "$RESULT_SAVE_DIR"

if [ -d "$REQGEN_DIR/results" ] && [ "$(ls -A "$REQGEN_DIR/results")" ]; then
  cp "$REQGEN_DIR/results"/* "$RESULT_SAVE_DIR/"
  echo "========================================================================="
  echo "🎉 Benchmark results successfully archived!"
  echo "   - Output Directory: $RESULT_SAVE_DIR"
  echo "========================================================================="
  cat "$RESULT_SAVE_DIR/ttft_summary.txt" 2>/dev/null || true
  echo "========================================================================="
else
  echo "❌ [Error] No result files found under $REQGEN_DIR/results."
fi

# 컨테이너 자원 정리
docker rm -f request_generator_container >/dev/null 2>&1 || true

echo "[INFO] Orchestration benchmark script run complete."
