#!/bin/bash
# cxl_rag_network 네트워크 생성 (이미 존재하면 경고 무시)
NET_NAME="cxl_rag_network"
docker network inspect $NET_NAME >/dev/null 2>&1 || docker network create $NET_NAME
echo " Docker bridge network '$NET_NAME' is ready."
