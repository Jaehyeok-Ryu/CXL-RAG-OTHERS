FROM python:3.9-slim
RUN pip install --no-cache-dir requests flask
RUN pip install --no-cache-dir datasets numpy
WORKDIR /app

COPY app.py /app/app.py