# ============ Source Stage ============
FROM alpine/git AS source

WORKDIR /repo
RUN git clone --recurse-submodules --depth=1 \
    https://github.com/liuzhao1225/YouDub-webui.git . \
    && rm -rf .git

# ============ Frontend Build Stage ============
FROM node:20-slim AS frontend-builder

WORKDIR /build
COPY --from=source /repo/apps/web/ .
RUN npm ci && npm run build

# ============ Runtime Stage ============
FROM python:3.12-slim-bookworm

WORKDIR /app

# Install system runtime deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg curl ca-certificates build-essential \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Copy entire source tree
COPY --from=source /repo/ .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Overlay built frontend artifacts
COPY --from=frontend-builder /build/.next apps/web/.next
COPY --from=frontend-builder /build/node_modules apps/web/node_modules

# Create runtime data directories
RUN mkdir -p data workfolder

# Install entrypoint
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 7860

ENV DEVICE=cpu
ENV WORKFOLDER=./workfolder
ENV MODEL_CACHE_DIR=./data/modelscope
ENV BACKEND_PORT=8000
ENV FRONTEND_PORT=7860

ENTRYPOINT ["docker-entrypoint.sh"]
