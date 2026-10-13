FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY signaling.py .
USER 65534:65534
ENV PYTHONDONTWRITEBYTECODE=1
CMD ["python", "-B", "signaling.py"]
