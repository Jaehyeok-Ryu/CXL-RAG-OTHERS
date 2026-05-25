# 🏗️ RAG Request & Load Generator 통합 벤치마크 가이드 (Basic Tool)

이 디렉터리는 RAG Request Generator(`3_request_generator`)와 Qdrant Load Generator(`4_load_generator`)를 유기적으로 조합하여 **동시성 환경에서의 VectorDB 성능 및 RAG 추론 레이턴시(TTFT)**를 분석하기 위해 구성된 통합 오케스트레이션 도구입니다.

---

## 🗺️ 동작 메커니즘 (Under the Hood)

전체 목표 RPS를 $n$으로 설정하여 스크립트를 기동할 경우, Poisson 분포 기반 요청 생성이 다음 규칙에 맞춰 자동 분할 인가됩니다:
1. **Request Generator (실제 RAG 쿼리 발송):** 
   * **`0.5 QPS` 고정** 비율로 총 **`1000개`**의 실시간 RAG 추론 쿼리를 생성합니다.
   * `질문 ➔ 임베딩 ➔ VectorDB 검색 ➔ LLM 답변 생성 ➔ TTFT 측정` 루프를 모두 타며 가동 시간을 결정합니다 (약 2000초 소요).
2. **Load Generator (백그라운드 스트레스):**
   * **`n - 0.5 RPS` 동적 계산**된 비율로 백그라운드 VectorDB 쿼리 스트레스를 무제한으로 뿜어냅니다.
   * 만약 전체 목표 RPS $n \le 0.5$ 로 입력될 경우, 로드 제너레이터는 가동되지 않고 리스폰스 요청기만 단독 동작합니다.
3. **Warm-up 단계 (15초):**
   * 로드 제너레이터의 멀티프로세스 자원 적재 및 클라이언트 초기화 시간 확보를 위해, 배경 부하가 완벽히 안정화(Steady-State)될 때까지 **15초의 웜업 대기**를 거친 뒤 본 측정을 시작하여 노이즈를 차단합니다.

---

## 🚀 사용법 (Execution Command)

### 1️⃣ 사전 요구사항 (Prerequisites)
실험 가동 전에 원격/로컬 물리 장치에서 아래 백엔드 서버들이 도커 브리지 네트워크 `cxl_rag_network` 안에서 구동 중이어야 합니다:
* **VectorDB (Qdrant):** 듀얼 인스턴스 (Port: 6333 및 6343)
* **Embedding Server:** `embedding_container_async` 기동 중 (Port: 5003)
* **LLM Inference Server:** `llm_inference_container` 기동 중 (Port: 5000)

### 2️⃣ 실행 명령어
`run_basic_benchmark.sh`를 실행할 때 인자로 `TOTAL_RPS`, `SOCKET_0_IP`, `SOCKET_1_IP`, `QUERY_COUNT` 순서로 주입할 수 있습니다.

```bash
# 형식: ./run_basic_benchmark.sh [TOTAL_RPS] [SOCKET_0_IP] [SOCKET_1_IP] [QUERY_COUNT]

# 예시 1) 전체 목표 15.0 RPS (백그라운드 로드: 14.5 RPS, RAG 요청: 0.5 QPS)
./run_basic_benchmark.sh 15.0 127.0.0.1 127.0.0.1 1000

# 예시 2) 백그라운드 부하 없이 순수 RAG Request Generator 단독 측정 (n <= 0.5)
./run_basic_benchmark.sh 0.5 127.0.0.1 127.0.0.1 1000
```

### 3️⃣ RPS Sweep 자동화 실행 명령어 (`run_sweep_benchmark.sh`)
대량의 다양한 RPS 실험군을 한 번에 스크립트로 순차 수행하려는 경우, `run_sweep_benchmark.sh`를 사용합니다. 
이 스크립트는 여러 개의 값을 파라미터로 길게 적어야 하는 불편함을 해소하기 위해 **두 가지 편리한 지정 방식**을 지원합니다:

#### 💡 방법 A: 아무 옵션 없이 기본값으로 돌리기
인자를 넣지 않으면 기본 정의된 대표 실험 구간(`5.0`부터 `40.0`까지 `5.0` 단위씩 총 8개 케이스)을 차례대로 수행합니다.
```bash
./run_sweep_benchmark.sh
```

#### 💡 방법 B: 공백으로 구분된 임의의 값 목록(Pool) 직접 주입하기
테스트하고 싶은 값들을 공백 구분 문자열로 한 번에 전달하여 실행합니다.
```bash
# 예: 10.0, 15.0, 20.0, 25.0, 30.0 RPS 연속 측정
./run_sweep_benchmark.sh --pool "10.0 15.0 20.0 25.0 30.0"
```

* **공통 파라미터 재정의:** `--ip1`, `--ip2`, `--query-count` 옵션을 결합하여 타겟 Qdrant 서버 주소 및 쿼리 수를 함께 변경할 수 있습니다:
  ```bash
  ./run_sweep_benchmark.sh --pool "10 20 30" --ip1 127.0.0.1 --ip2 127.0.0.1 --query-count 500
  ```

---


## 📊 저장되는 결과 및 파일 구조

벤치마크 테스트가 완료되면 설정된 `TOTAL_RPS` 수치와 타임스탬프를 조합하여 아래 디렉터리에 결과물이 안전하게 아카이빙됩니다.

📂 **결과 경로:** `Hypothesis/Basic_Tool/results/run_RPS_[목표RPS]_[년월일_시분초]/`

### 1) 생성되는 결과 파일
* **`ttft_summary.txt` (요약 보고서):**
  전체 테스트 진행 시간, 평균 쿼리 시간, 최종 측정 RPS, 그리고 모든 쿼리의 **평균 TTFT(초)** 및 **P99 TTFT(초)** 수치를 한눈에 보기 쉽게 요약 정리합니다.
* **`ttft_log.csv` (상세 수치 데이터):**
  발송된 모든 쿼리(1~1000번)에 대한 타임 트랙커입니다:
  ```csv
  query_id,start_time,ttft_time,ttft
  0,1716570000.123456,1716570001.345678,1.222222
  1,1716570002.567890,1716570003.890123,1.322233
  ```

---

## 🛡️ 안정성 및 보안 가이드 (Security Guard)
실험용 로컬 스크립트지만, 쉘 주입 취약점(CWE-78)을 방지하기 위해 엄격한 정형성 검사를 수행합니다. 
* 정수 및 소수 형식을 벗어난 문자열이 `TOTAL_RPS`로 전달되거나, 세미콜론 및 파이프를 이용한 쉘 탈출 시도가 감지되면 다음과 같이 에러 메시지를 내며 즉시 안전 정지합니다:
  > `❌ [Error] Invalid TOTAL_RPS: '10; rm -rf /'. 숫자(정수/소수)만 입력 가능합니다.`
