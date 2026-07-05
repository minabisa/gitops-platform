# Stage 1: builder — install dependencies
FROM python:3.12-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --upgrade pip && \
    pip install --user --no-cache-dir -r requirements.txt

# Stage 2: final — only copy what's needed, no build tools
FROM python:3.12-slim
WORKDIR /app

# Non-root user for security
RUN useradd -m -u 1000 appuser

COPY --from=builder /root/.local /home/appuser/.local
COPY src/ .

RUN chown -R appuser:appuser /app
USER appuser

ENV PATH=/home/appuser/.local/bin:$PATH
ENV APP_ENV=production

EXPOSE 5000

# gunicorn is production-grade — never use flask dev server in containers
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "app:app"]
