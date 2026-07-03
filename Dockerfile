# ── Backend runtime only (Flutter frontend runs natively) ──
FROM python:3-slim

WORKDIR /app

# Copy backend source
COPY backend/ ./backend/

# Create runtime directories (bind-mounted as volumes)
RUN mkdir -p backend/downloads backend/requests

EXPOSE 8088

CMD ["python", "backend/main.py", "--host", "0.0.0.0", "--save-request-info"]
