# ---------------------------------------------------------------------------
# Backend Dockerfile (Flask + gunicorn)
# Security hardening:
#   - Minimal base (python:3.12-slim)
#   - Non-root user (UID 1000)
#   - No build tools left in final image
#   - --no-cache-dir to avoid pip cache layer
# ---------------------------------------------------------------------------
FROM python:3.12-slim AS build

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /build

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH=/install/bin:$PATH \
    PYTHONPATH=/install/lib/python3.12/site-packages

RUN groupadd --system --gid 1000 appuser \
    && useradd  --system --uid 1000 --gid appuser --home /app --shell /sbin/nologin appuser

WORKDIR /app

COPY --from=build /install /install
COPY --chown=appuser:appuser app ./app
COPY --chown=appuser:appuser run.py .

USER appuser

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:5000/health').read()" || exit 1

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--access-logfile", "-", "--error-logfile", "-", "run:app"]
