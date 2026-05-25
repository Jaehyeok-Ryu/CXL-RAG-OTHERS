# Use a base image with Python (adjust as needed)
FROM python:3.9-slim

# Install necessary dependencies
RUN pip install --no-cache-dir flask qdrant-client qdrant-client[fastembed] sentence-transformers datasets

# Set the working directory
WORKDIR /app

COPY load_generator.py /app/load_generator.py
