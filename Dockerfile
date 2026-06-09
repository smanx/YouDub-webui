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

# Create basic auth middleware (WEB_USERNAME / WEB_PASSWORD at runtime)
RUN mkdir -p src && cat > src/middleware.ts << 'MIDEOF'
import { NextRequest, NextResponse } from "next/server";

export function middleware(req: NextRequest) {
  const password = process.env.WEB_PASSWORD;
  if (!password) return NextResponse.next();

  const header = req.headers.get("authorization");
  if (header) {
    const [user, pwd] = atob(header.slice(6)).split(":");
    if (user === (process.env.WEB_USERNAME || "admin") && pwd === password)
      return NextResponse.next();
  }

  return new NextResponse("Unauthorized", {
    status: 401,
    headers: { "WWW-Authenticate": "Basic realm=\"YouDub WebUI\"" },
  });
}

export const config = { matcher: "/:path*" };
MIDEOF

RUN npm ci && npm run build

# ============ Runtime Stage ============
FROM python:3.12-slim-bookworm

# Build args for pre-downloading models (all default to skip)
# 分离人声与背景音
ARG PRE_DOWNLOAD_DEMUCS=true
# 语音识别
ARG PRE_DOWNLOAD_WHISPER=true
# 生成配音
ARG PRE_DOWNLOAD_VOXCPM=true

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

# Pre-download Demucs model (htdemucs_ft, 4 sub-models ~700 MB total) - 分离人声与背景音
RUN if [ "$PRE_DOWNLOAD_DEMUCS" = "true" ]; then \
        python -c 'import torch, os; model_dir = os.path.expanduser("~/.cache/torch/hub/checkpoints"); os.makedirs(model_dir, exist_ok=True); [torch.hub.load_state_dict_from_url(url, model_dir=model_dir, check_hash=False) for url in ["https://dl.fbaipublicfiles.com/demucs/hybrid_transformer/f7e0c4bc-ba3fe64a.th", "https://dl.fbaipublicfiles.com/demucs/hybrid_transformer/d12395a8-e57c48e6.th", "https://dl.fbaipublicfiles.com/demucs/hybrid_transformer/92cfc3b6-ef3bcb9c.th", "https://dl.fbaipublicfiles.com/demucs/hybrid_transformer/04573f0d-f3cf25b2.th"]]'; \
    fi

# Pre-download Whisper model (large-v3-turbo, ~3 GB) - 语音识别
RUN if [ "$PRE_DOWNLOAD_WHISPER" = "true" ]; then \
        python -c 'import whisper; whisper._download(whisper._MODELS["large-v3-turbo"], "/root/.cache/whisper")'; \
    fi

# Pre-download VoxCPM2 model (~several GB) - 生成配音
RUN if [ "$PRE_DOWNLOAD_VOXCPM" = "true" ]; then \
        python -c 'from modelscope import snapshot_download; snapshot_download("OpenBMB/VoxCPM2", local_dir="/app/data/modelscope/OpenBMB__VoxCPM2")'; \
    fi

# Install entrypoint
COPY docker-entrypoint-youduo.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 7860

ENV DEVICE=cpu
ENV WORKFOLDER=./workfolder
ENV MODEL_CACHE_DIR=./data/modelscope
ENV BACKEND_PORT=8000
ENV FRONTEND_PORT=7860
ENV WEB_USERNAME=admin
ENV WEB_PASSWORD=admin

ENTRYPOINT ["docker-entrypoint.sh"]
