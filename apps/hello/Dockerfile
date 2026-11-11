# Build the in-house `hello` service FROM golden base images.
#
# GOLDEN_REGISTRY is the private golden mirror (ghcr.io/<owner>/golden, filled
# by golden-image's cgr-sync) — the same registry the runtime manifests pull
# from. Building from it (not docker.io / upstream) is the whole point: the app
# inherits Chainguard's low-CVE, daily-rebuilt bases, and the image-source gate
# in CI is satisfied build-time too. Pulling the bases needs a read:packages
# login (`docker login ghcr.io`); pushing needs write:packages (docs/PROMOTION.md).
#
#   docker build --build-arg GOLDEN_REGISTRY=ghcr.io/cartyc/golden \
#     -t ghcr.io/cartyc/apps/hello:0.1.0 apps/hello
ARG GOLDEN_REGISTRY=ghcr.io/cartyc/golden

# --- build stage: golden Go toolchain (has a shell + go) ---
FROM ${GOLDEN_REGISTRY}/go:latest-dev AS build
WORKDIR /src
COPY src/go.mod ./
COPY src/*.go ./
# Static, stripped binary so it runs on the distroless static runtime.
ENV CGO_ENABLED=0
RUN go build -trimpath -ldflags="-s -w" -o /hello .

# --- runtime stage: golden distroless static (no shell, nonroot) ---
# (golden-image mirrors static from Chainguard's public catalog; it's the one
# golden image from outside the org.)
FROM ${GOLDEN_REGISTRY}/static:latest
COPY --from=build /hello /usr/bin/hello
EXPOSE 8080
ENTRYPOINT ["/usr/bin/hello"]
