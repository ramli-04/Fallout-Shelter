FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
WORKDIR /app
COPY ai_service/requirements.txt /app/ai_service/requirements.txt
RUN pip install --no-cache-dir -r ai_service/requirements.txt
COPY ai_service /app/ai_service
EXPOSE 8765
CMD ["python", "-m", "uvicorn", "ai_service.main:app", "--host", "0.0.0.0", "--port", "8765", "--workers", "1"]
