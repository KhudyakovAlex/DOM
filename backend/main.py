from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, Response
from sqlalchemy import text
from database import engine, Base
from config import get_settings

settings = get_settings()

# Создаём схемы
with engine.connect() as conn:
    conn.execute(text("CREATE SCHEMA IF NOT EXISTS dom_auth"))
    conn.execute(text("CREATE SCHEMA IF NOT EXISTS dom_domain"))
    conn.commit()

# Создаём таблицы
Base.metadata.create_all(bind=engine)

# FastAPI приложение
app = FastAPI(title=settings.app_name, debug=settings.debug)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://localhost:5173"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health_check():
    """Health check endpoint"""
    return {"status": "ok"}


# --- Tiles (PMTiles) ---
TILES_DIR = Path(__file__).resolve().parent / "app" / "static" / "pmtiles"


@app.get("/api/tiles/{filename}", tags=["tiles"])
async def get_pmtiles(filename: str, request: Request):
    """
    Отдаёт PMTiles файл для MapLibre GL JS / pmtiles protocol.
    """
    if not filename.endswith(".pmtiles"):
        raise HTTPException(status_code=400, detail="Only .pmtiles files are supported")

    # Защита от path traversal
    safe_filename = Path(filename).name
    file_path = TILES_DIR / safe_filename

    if not file_path.exists():
        raise HTTPException(
            status_code=404,
            detail=f"File {safe_filename} not found in {TILES_DIR}. Place it there.",
        )

    # Если клиент просит Range — отдаём 206 Partial Content (нужно для PMTiles)
    range_header = request.headers.get("range") or request.headers.get("Range")
    if range_header:
        try:
            unit, rng = range_header.split("=", 1)
            if unit.strip().lower() != "bytes":
                raise ValueError("Only bytes ranges supported")
            start_s, end_s = (rng.split("-", 1) + [""])[:2]
            file_size = file_path.stat().st_size

            start = int(start_s) if start_s else 0
            end = int(end_s) if end_s else min(start + 1024 * 1024 - 1, file_size - 1)

            if start < 0 or end < start or start >= file_size:
                raise ValueError("Invalid range")

            end = min(end, file_size - 1)
            length = end - start + 1

            with open(file_path, "rb") as f:
                f.seek(start)
                chunk = f.read(length)

            return Response(
                content=chunk,
                status_code=206,
                media_type="application/octet-stream",
                headers={
                    "Accept-Ranges": "bytes",
                    "Content-Range": f"bytes {start}-{end}/{file_size}",
                    "Content-Length": str(len(chunk)),
                    "Access-Control-Allow-Origin": "*",
                    "Access-Control-Expose-Headers": "Content-Length, Content-Range",
                    "Cache-Control": "public, max-age=86400",
                },
            )
        except Exception:
            raise HTTPException(status_code=416, detail="Invalid Range header")

    # Иначе отдаём целиком
    return FileResponse(
        path=file_path,
        media_type="application/octet-stream",
        headers={
            "Accept-Ranges": "bytes",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Expose-Headers": "Content-Length, Content-Range",
            "Cache-Control": "public, max-age=86400",
        },
    )
