#!/bin/bash
# ==============================================================================
# run_sweep_benchmark.sh
# ==============================================================================
# 이 스크립트는 여러 RPS 실험군을 연속으로 측정하기 위한 Sweep 자동화 도구입니다.
# 기본값으로 지정된 테스트 군을 수행하거나, dynamic range(--start, --end, --step)
# 또는 커스텀 풀(--pool) 지정을 통해 간편하게 대량의 sweep 실험을 관리할 수 있습니다.
# ==============================================================================

set -e

# 스크립트 실행 경로를 본인이 위치한 폴더로 고정
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# 기본 매개변수 설정
# Load environment variables from root .env file if it exists
if [ -f "$SCRIPT_DIR/../../../.env" ]; then
  export $(grep -v '^#' "$SCRIPT_DIR/../../../.env" | xargs)
fi

VECTORDB_IP_1=${VECTORDB_IP_1:-"127.0.0.1"}
VECTORDB_IP_2=${VECTORDB_IP_2:-"127.0.0.1"}
QUERY_COUNT="1000"

# Sweep 범위 설정을 위한 변수 초기화
CUSTOM_POOL=""

# 도움말 함수
show_help() {
  echo "사용법: $0 [옵션]"
  echo ""
  echo "옵션:"
  echo "  --pool \"값1 값2 ...\"     공백으로 구분된 커스텀 RPS 실험 리스트 지정"
  echo "  --ip1 <IP>                Socket 0 Qdrant IP (기본값: $VECTORDB_IP_1)"
  echo "  --ip2 <IP>                Socket 1 Qdrant IP (기본값: $VECTORDB_IP_2)"
  echo "  --query-count <개수>      RAG 추론 총 쿼리 수 (기본값: $QUERY_COUNT)"
  echo "  -h, --help                이 도움말 메시지 출력"
  echo ""
  echo "예시:"
  echo "  1) 기본 Sweep 범위 (5.0에서 40.0까지 5.0 단위로 측정) 가동:"
  echo "     $0"
  echo ""
  echo "  2) 커스텀 RPS 풀 지정 및 Qdrant IP 변경 적용:"
  echo "     $0 --pool \"10 15 20 25 30\" --ip1 127.0.0.1 --ip2 127.0.0.1"
  exit 0
}

# 파라미터 파싱
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --pool) CUSTOM_POOL="$2"; shift ;;
    --ip1) VECTORDB_IP_1="$2"; shift ;;
    --ip2) VECTORDB_IP_2="$2"; shift ;;
    --query-count) QUERY_COUNT="$2"; shift ;;
    -h|--help) show_help ;;
    *) echo " [Error] 알 수 없는 옵션: $1"; show_help ;;
  esac
  shift
done

# ------------------------------------------------------------------------------
# [입력 인자 정합성 검증 - Security Input Validation]
# ------------------------------------------------------------------------------
IP_REGEX="^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$"
HOST_REGEX="^[a-zA-Z0-9.-]+$"
if [[ ! "$VECTORDB_IP_1" =~ $IP_REGEX ]] && [[ ! "$VECTORDB_IP_1" =~ $HOST_REGEX ]]; then
  echo " [Error] Invalid IP/Hostname for ip1: '$VECTORDB_IP_1'" >&2
  exit 1
fi
if [[ ! "$VECTORDB_IP_2" =~ $IP_REGEX ]] && [[ ! "$VECTORDB_IP_2" =~ $HOST_REGEX ]]; then
  echo " [Error] Invalid IP/Hostname for ip2: '$VECTORDB_IP_2'" >&2
  exit 1
fi
if [[ ! "$QUERY_COUNT" =~ ^[0-9]+$ ]] || [ "$QUERY_COUNT" -eq 0 ]; then
  echo " [Error] Invalid QUERY_COUNT: '$QUERY_COUNT'. 1 이상의 정수만 가능합니다." >&2
  exit 1
fi
# ------------------------------------------------------------------------------

# Sweep 할 RPS 배열 생성
RPS_SWEEP_POOL=()

if [ ! -z "$CUSTOM_POOL" ]; then
  # 1. 사용자가 직접 공백 구분 리스트를 제공한 경우
  echo "[INFO] 커스텀 RPS 풀이 지정되었습니다: $CUSTOM_POOL"
  for rps in $CUSTOM_POOL; do
    if [[ ! "$rps" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
      echo " [Error] RPS 값 '$rps'은 숫자 형식이 아닙니다." >&2
      exit 1
    fi
    RPS_SWEEP_POOL+=("$rps")
  done

else
  # 2. 아무것도 지정되지 않았을 때 기본값으로 Sweep 진행
  echo "[INFO] 인자가 입력되지 않아 기본 RPS Sweep 풀을 사용합니다."
  RPS_SWEEP_POOL=(5.0 10.0 15.0 20.0 25.0 30.0 35.0 40.0)
fi


# 최종 점검
if [ ${#RPS_SWEEP_POOL[@]} -eq 0 ]; then
  echo " [Error] Sweep 할 RPS가 정의되지 않았습니다. 옵션을 다시 확인해 주세요." >&2
  exit 1
fi

echo "========================================================================="
echo " Starting RPS Sweep Benchmark Run"
echo "========================================================================="
echo "   - Sweep RPS Pool    : [ ${RPS_SWEEP_POOL[*]} ]"
echo "   - VectorDB IP 1     : $VECTORDB_IP_1"
echo "   - VectorDB IP 2     : $VECTORDB_IP_2"
echo "   - RAG Query Count   : $QUERY_COUNT"
echo "   - Total Experiments : ${#RPS_SWEEP_POOL[@]} cases"
echo "========================================================================="

# 루프 돌며 순차적 벤치마크 수행
CASE_NUM=1
for rps in "${RPS_SWEEP_POOL[@]}"; do
  echo "-------------------------------------------------------------------------"
  echo " [Sweep Case $CASE_NUM/${#RPS_SWEEP_POOL[@]}] Testing target total RPS: $rps"
  echo "-------------------------------------------------------------------------"
  
  # 기본 벤치마크 스크립트 실행
  ./run_basic_benchmark.sh "$rps" "$VECTORDB_IP_1" "$VECTORDB_IP_2" "$QUERY_COUNT"
  
  echo " Completed Case $CASE_NUM [RPS: $rps]"
  CASE_NUM=$((CASE_NUM + 1))
done

echo "========================================================================="
echo " All Sweep Benchmark Runs completed successfully!"
echo "   아카이빙된 결과 경로: $SCRIPT_DIR/results/"
echo "========================================================================="
