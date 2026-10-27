FROM python:3.13-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY collector.py .

RUN useradd --create-home app
USER app

EXPOSE 8000
CMD ["python", "-u", "collector.py"]
