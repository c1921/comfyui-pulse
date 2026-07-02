# ── Stage 1: Build frontend ──
FROM node:22-alpine AS frontend-builder

WORKDIR /build
COPY frontend/package.json frontend/pnpm-lock.yaml frontend/pnpm-workspace.yaml ./
RUN npm install -g pnpm@latest && pnpm install --frozen-lockfile

COPY frontend/ ./
RUN pnpm build

# ── Stage 2: Backend runtime ──
FROM python:3-slim

WORKDIR /app

# Copy backend source
COPY backend/ ./backend/

# Copy built frontend from stage 1
COPY --from=frontend-builder /build/dist ./frontend/dist

# Create runtime directories (bind-mounted as volumes)
RUN mkdir -p backend/downloads backend/requests

EXPOSE 8088

CMD ["python", "backend/main.py", \
     "--host", "0.0.0.0", \
     "--frontend-dir", "frontend/dist", \
     "--save-request-info"]
