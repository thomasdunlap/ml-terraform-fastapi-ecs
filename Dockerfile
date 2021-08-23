FROM tiangolo/uvicorn-gunicorn-fastapi:python3.8-slim

RUN pip install joblib sklearn

COPY ./app/ /app/app/
