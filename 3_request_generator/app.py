# Basic modules
import argparse
from datasets import load_from_disk, Dataset, load_dataset
import requests
import numpy as np
import random
import time
from flask import Flask, request, jsonify
import os
from threading import Thread

# Load environment variables from .env file
def _load_env():
    paths = [
        os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env"),
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "../.env"),
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../.env"),
    ]
    for p in paths:
        if os.path.exists(p):
            with open(p, "r") as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith("#") and "=" in line:
                        key, val = line.split("=", 1)
                        os.environ[key.strip()] = val.strip().strip('"').strip("'")
            break

_load_env()

# Argument Parser Definition
def argument_parser():
    parser = argparse.ArgumentParser()
    ### Dataset
    parser.add_argument("--question-dir", type=str, help="directory of preprocessed question data")
    ### Benchmark Parameter
    parser.add_argument("--target-qps", type=float, help="target qps to generate request")
    parser.add_argument("--query-count", type=int, help="total query count to generate request")
    parser.add_argument("--gpu-server-ip", type=str, default=os.getenv("REQUEST_GEN_GPU_SERVER_IP", os.getenv("GPU_SERVER_IP", "127.0.0.1")), help="GPU server IP address")
    parser.add_argument("--results-dir", type=str, default="/app/results", help="directory to store TTFT and query log results")

    args = parser.parse_args()
    return args

# Parse arguments at top-level so they are globally accessible to route handlers
args = argument_parser()

request_timings = {}
app = Flask(__name__)

def load_question (dir):
    question_dataset = load_from_disk(dir)

    return question_dataset

def send_request(query_id, query, url, query_count):
    # Communicate with the Retrieval Server
    query_id = int(query_id)
    if query_id == 0:
        message = 'start'
    elif query_id == query_count - 1:
        message = 'end'
    else:
        message = 'normal'
    if query_id not in request_timings:
        request_timings[query_id] = {}

    # start_time 설정
    request_timings[query_id]['start_time'] = time.time()
    response = requests.post(url, json={"message": message, "query_id": query_id, "query": query})
    if response.status_code != 200:
        print(f"Error retrieving data: {response.status_code}")
        print(f"Response details: {response.json()}")
        return

    print(f"response {query_id}: {response}")

    return response

# generate quert_count # of requests following poisson distriution by randomly select question from question_dataset.
def generate_requests(url, question_dataset, qps, query_count):

    lambda_value = 1/qps

    for i in range(query_count):
        # wait 
        wait_interval = np.random.poisson(lambda_value)
        # wait_interval = lambda_value
        time.sleep(wait_interval)
        # time.sleep(0.01)
        index = np.random.zipf(1.2) % len(question_dataset)
        question = question_dataset[index]['question']

        print(f"Sending question to vector DB {i}: {question}")
        send_request(i, question, url, query_count)

def print_timings():
    total_end_time = time.time()
    total_query_time = 0.0
    total_ttft_time = 0.0
    ttft_list = []
    
    summary_lines = []
    summary_lines.append("TTFT Summary:")
    print("\nTTFT Summary:")
    
    for query_id, timings in request_timings.items():
        start_time = timings.get('start_time')
        LLM_TTFT = timings.get('TTFT_time')
        end_time = timings.get('complete_time')
        if start_time is not None and LLM_TTFT is not None and end_time is not None:
            TTFT = LLM_TTFT - start_time
            ttft_list.append(TTFT)
            
            msg = f"Query ID {query_id} TTFT : {TTFT:.4f} seconds"
            print(msg)
            summary_lines.append(msg)
            
            query_time = end_time - start_time
            total_query_time += query_time
            total_ttft_time += TTFT
            
            msg = f"Query ID {query_id} query_time: {query_time:.4f} seconds"
            print(msg)
            summary_lines.append(msg)
        else:
            msg = f"Query ID {query_id}: Incomplete timings"
            print(msg)
            summary_lines.append(msg)
            
    # Query ID 1의 start_time 확인 (문자열로 처리 가능)
    first_start_time = request_timings.get("1", {}).get('start_time') or request_timings.get(1, {}).get('start_time')

    if first_start_time is not None:
        total_duration = total_end_time - first_start_time
        query_count = len(request_timings)
        
        msg = f"Total execution time: {total_duration:.4f} seconds"
        print(msg)
        summary_lines.append(msg)
        
        msg = f"Average query time: {total_query_time/query_count:.4f} seconds"
        print(msg)
        summary_lines.append(msg)

        # RPS 계산
        if query_count > 0:
            rps = query_count / total_duration
            average_TTFT = total_ttft_time / query_count
            
            msg = f"RPS : {rps:.4f} requests/second\n"
            print(msg)
            summary_lines.append(msg)
            
            msg = f"average TTFT: {average_TTFT:.4f} seconds"
            print(msg)
            summary_lines.append(msg)
            
            # P99 TTFT 계산
            if len(ttft_list) > 0:
                p99_ttft = np.percentile(ttft_list, 99)
                msg = f"P99 TTFT: {p99_ttft:.4f} seconds\n"
                print(msg)
                summary_lines.append(msg)
            else:
                msg = "No TTFT data available for P99 calculation."
                print(msg)
                summary_lines.append(msg)
        else:
            msg = "No queries processed."
            print(msg)
            summary_lines.append(msg)
    else:
        msg = "\nQuery ID 1 start time is missing."
        print(msg)
        summary_lines.append(msg)

    # Write summary to file
    results_dir = args.results_dir
    if results_dir and os.path.exists(results_dir):
        summary_file = os.path.join(results_dir, 'ttft_summary.txt')
        try:
            with open(summary_file, 'w') as f:
                f.write("\n".join(summary_lines) + "\n")
            print(f"Summary successfully saved to: {summary_file}", flush=True)
        except Exception as e:
            print(f"Failed to write summary file: {e}", flush=True)

@app.route('/TTFT', methods=['POST'])
def TTFT():
    data = request.json
    query_id = int(data['query_id'])
    current_time = time.time()

    # start_time 확인 및 TTFT_time 저장
    if query_id in request_timings:
        start_time = request_timings[query_id].get('start_time')
        request_timings[query_id]['TTFT_time'] = current_time

        # TTFT 계산 및 출력
        if start_time is not None:
            ttft = current_time - start_time
            if ttft >= 30:
                print(f"TTFT is higher than 30 sec, Current TTFT is {ttft:.4f} seconds", flush=True)
                os._exit(1)
            print(f"Query ID: {query_id}, TTFT: {ttft:.4f} seconds", flush=True)
            
            # Write real-time log to CSV file
            results_dir = args.results_dir
            if results_dir and os.path.exists(results_dir):
                log_file = os.path.join(results_dir, 'ttft_log.csv')
                try:
                    if not os.path.exists(log_file):
                        with open(log_file, 'w') as f:
                            f.write("query_id,start_time,ttft_time,ttft\n")
                    with open(log_file, 'a') as f:
                        f.write(f"{query_id},{start_time:.6f},{current_time:.6f},{ttft:.6f}\n")
                except Exception as e:
                    print(f"Failed to write real-time log: {e}", flush=True)
        else:
            print(f"Query ID: {query_id}, Start time not found.", flush=True)
    else:
        # 만약 request_timings에 없는 query_id라면 새로 추가
        request_timings[query_id] = {'TTFT_time': current_time}
        print(f"Query ID: {query_id}, Start time missing. Added entry.", flush=True)

    return jsonify({'status': 'received'}), 200

@app.route('/complete', methods=['POST'])
def complete():
    data = request.json
    query_id = int(data['query_id'])
    if query_id in request_timings:
        request_timings[query_id]['complete_time'] = time.time()
    else:
        request_timings[query_id] = {'complete_time': time.time()}
    return jsonify({'status': 'received'}), 200

@app.route('/notify_completion', methods=['POST'])
def notify_completion():
    print_timings()
    def delayed_shutdown():
        time.sleep(10)
        os._exit(0)

    shutdown_thread = Thread(target=delayed_shutdown)
    shutdown_thread.start()
    return jsonify({'status': 'received'}), 200

if __name__ == "__main__":
    EMBEDDING_URL = f"http://{args.gpu_server_ip}:5003/retrieve"

    question_dir = args.question_dir

    ### Load question dataset
    question_dataset = load_question(question_dir)

    # Initialize results directory if it doesn't exist (in-container)
    if args.results_dir and not os.path.exists(args.results_dir):
        try:
            os.makedirs(args.results_dir, exist_ok=True)
        except Exception as e:
            print(f"Failed to create results dir inside container: {e}", flush=True)

    # Clean existing result files inside the results directory
    if args.results_dir and os.path.exists(args.results_dir):
        for fname in ['ttft_log.csv', 'ttft_summary.txt']:
            fpath = os.path.join(args.results_dir, fname)
            if os.path.exists(fpath):
                try:
                    os.remove(fpath)
                except Exception:
                    pass

    # Define function for generate_requests
    def run_generate_requests():
        target_qps = args.target_qps
        query_count = args.query_count
        generate_requests(EMBEDDING_URL, question_dataset, target_qps, query_count)

    # Start Flask server in main thread
    app_thread = Thread(target=app.run, kwargs={'host': '0.0.0.0', 'port': 6000})
    app_thread.start()

    # Start generate_requests in another thread
    request_thread = Thread(target=run_generate_requests)
    request_thread.start()
