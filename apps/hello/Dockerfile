# Build the in-house `hello` service FROM golden base images.
#
# GOLDEN_REGISTRY is your Artifact Registry golden mirror (the cgr-sync
# destination) — the same registry the runtime manifests pull from. Building
# from it (not docker.io / upstream) is the whole point: the app inherits
# Chainguard's low-CVE, daily-rebuilt bases, and the image-source gate in CI is
# satisfied build-time too.
#
#   docker build --build-arg GOLDEN_REGISTRY=us-central1-docker.pkg.dev/gc-golden-demo/golden \
#     -t us-central1-docker.pkg.dev/gc-golden-demo/apps/hello:0.1.0 apps/hello
ARG GOLDEN_REGISTRY=us-central1-docker.pkg.dev/gc-golden-demo/golden

# --- build stage: golden Go toolchain (has a shell + go) ---
FROM ${GOLDEN_REGISTRY}/go:latest-dev AS build
WORKDIR /src
COPY src/go.mod ./
COPY src/*.go ./
# Static, stripped binary so it runs on the distroless static runtime.
ENV CGO_ENABLED=0
RUN go build -trimpath -ldflags="-s -w" -o /hello .

# --- runtime stage: golden distroless static (no shell, nonroot) ---
FROM ${GOLDEN_REGISTRY}/static:latest
COPY --from=build /hello /usr/bin/hello
EXPOSE 8080
ENTRYPOINT ["/usr/bin/hello"]
