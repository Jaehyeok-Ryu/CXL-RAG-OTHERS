# 🏗️ CXL RAG Evaluation Suite (Monorepo)

이 저장소는 단일 호스트 상에서 RAG(검색 증강 생성) 컴포넌트들을 유기적으로 기동하고, CXL NUMA 아키텍처 및 VectorDB 성능을 미시적으로 프로파일링하기 위한 통합 평가 환경입니다.

각 서비스는 번호 순서(1~5)로 완전히 격리된 독립 디렉터리로 구성되어 있으며, 각자 자신만의 `Dockerfile`과 `run.sh`를 내포하여 극대화된 이식성을 제공합니다.

---

## 📂 저장소 디렉터리 구조

*   `Data/`: [호스트 공유 볼륨] 질문 데이터셋 및 임베딩 모델 가중치 보관 (Git 제외)
*   `scripts/`: 공용 유틸리티 및 도커 네트워크 구성 도구
*   `1_embedding_server/`: 768차원 BGE 임베딩 비동기 API 서버 (Port: 5003)
*   `2_llm_server/`: Llama-3-ChatQA 생성 백배치 API 서버 (Port: 5000)
*   `3_request_generator/`: 실시간 TTFT/RPS 요청 생성 서버 (Port: 6000)
*   `4_load_generator/`: Qdrant 전용 가변 RPS 스트레스 생성기 (NUMA 및 Zipf 지원)
*   `5_dataset_builder/`: NQ 데이터셋 다운로드 및 768차원 전처리 자동화 도구

---

## ⚙️ RAG 구성 요소 통합 실행 가이드

모든 컴포넌트는 단일 물리 호스트에서 기동하며, 오직 **VectorDB (Qdrant) 서버만 별도의 원격지(Server A)**에서 작동한다고 가정합니다.

### 0️⃣ 도커 브리지 네트워크 설정
컴포넌트들이 IP 주소 하드코딩 없이 컨테이너 이름(DNS)으로 통신할 수 있도록 공용 네트워크를 먼저 생성합니다.
```bash
cd scripts
./setup_network.sh
```

### 1️⃣ 데이터셋 및 임베딩 모델 준비 (최초 1회 필수)
RAG 루프와 임베딩 서버 기동에 필수적인 `bge-base-en-v1.5` 모델과 `Google NQ` 768차원 전처리 데이터셋을 생성합니다.

```bash
cd ../5_dataset_builder
./download_and_preprocess.sh
```

> [!NOTE]
> **💡 이미 다른 폴더에 다운로드 받아둔 원본 데이터가 있는 경우 (대기시간 0초 꿀팁)**:
> 매번 Hugging Face에서 수 기가바이트의 데이터셋과 모델을 다운로드받는 것은 시간 낭비입니다.
> 아래 명령어 두 줄로 기존 캐시 폴더를 새 리포지토리의 `Data/` 디렉터리에 링크해주면, 스크립트 실행 시 즉시 감지하여 **0.1초 만에 전 단계를 스마트 패스(Skip)**하고 완료됩니다.
> ```bash
> ln -s /home/cxl_qemu/CXL_2nd_year_mid/Data/NQ_default ../Data/
> ln -s /home/cxl_qemu/CXL_2nd_year_mid/Data/bge-base-en-v1.5 ../Data/
> ```

### 2️⃣ 임베딩 서버 기동 (GPU 사용)
기동 시 원격 VectorDB (Qdrant)가 설치된 서버(Server A)의 물리 IP 주소를 인자값으로 전달합니다.
```bash
cd ../1_embedding_server
# 형식: ./run.sh [VECTORDB_IP]
./run.sh 163.152.48.208
```

### 3️⃣ LLM 추론 서버 기동 (GPU 사용)
```bash
cd ../2_llm_server
./run.sh
```

### 4️⃣ RAG 요청 생성기 (Request Generator) 구동
원하는 Target QPS 및 총 쿼리 숫자를 지정하여 부하를 가동합니다. 
```bash
cd ../3_request_generator
# 형식: ./run.sh [TARGET_QPS] [QUERY_COUNT]
./run.sh 2.0 100
```
이 생성기가 돌아가며 `768차원 NQ 질문` ➔ `임베딩 서버` ➔ `원격 Qdrant` ➔ `컨텍스트 병합` ➔ `LLM 서버` ➔ `생성 및 TTFT 측정` RAG 사이클을 실시간으로 추적합니다.

### 5️⃣ Qdrant 단독 성능 벤치마크 (Load Generator) 구동
NUMA 가중 메모리 인터리빙(CXL Weighted Interleaving)에 따른 Qdrant DB의 순수 검색 레이턴시 및 RPS 한계 성능을 측정하려면 단독 부하 생성기를 사용합니다.
```bash
cd ../4_load_generator
# 형식: ./run.sh [VECTORDB_IP] [TARGET_RPS] [REQUESTS_COUNT] [SCRIPT_TYPE: zipf|normal|no_async_zipf]
./run.sh 163.152.48.208 100.0 2000 zipf
```
> [!TIP]
> NUMA/CPU 물리 코어 고정 옵션을 주어 실행하고 싶은 경우, 환경변수 `LOADGEN_CPUS` 및 `LOADGEN_MEMS`를 주입하여 실행합니다:
> `LOADGEN_CPUS="0-11" LOADGEN_MEMS="0" ./run.sh 163.152.48.208 150.0 5000 zipf`
