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
