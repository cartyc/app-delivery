# Build the in-house `api` service on the golden python base (distroless,
# nonroot, daily-rebuilt). Stdlib-only, so no dependency install step.
ARG GOLDEN_REGISTRY=us-central1-docker.pkg.dev/gc-golden-demo/golden
FROM ${GOLDEN_REGISTRY}/python:latest
WORKDIR /app
COPY src/main.py /app/main.py
EXPOSE 8080
ENTRYPOINT ["python", "/app/main.py"]
