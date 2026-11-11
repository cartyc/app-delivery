# Build the in-house `api` service on the golden python base (distroless,
# nonroot, daily-rebuilt). Stdlib-only, so no dependency install step.
# GOLDEN_REGISTRY: the private golden mirror (see apps/hello/Dockerfile).
ARG GOLDEN_REGISTRY=ghcr.io/cartyc/golden
FROM ${GOLDEN_REGISTRY}/python:latest
WORKDIR /app
COPY src/main.py /app/main.py
EXPOSE 8080
ENTRYPOINT ["python", "/app/main.py"]
