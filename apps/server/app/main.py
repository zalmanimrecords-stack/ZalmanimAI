import os

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.api.audience_routes import router as audience_router
from app.api.routes import router
from app.core.config import settings
from app.services.system_log import append_system_log

app = FastAPI(title=settings.app_name)


def _log_category(path: str) -> str:
    """Use 'artist_portal' for public/artist endpoints, else 'api' (LB)."""
    if "/api/public/" in path or "/public/" in path:
        return "artist_portal"
    return "api"


@app.exception_handler(StarletteHTTPException)
async def http_exception_handler(request: Request, exc: StarletteHTTPException) -> JSONResponse:
    """Log every HTTP error (4xx/5xx) to system log so Settings > Logs shows LB and artist portal errors."""
    path = request.url.path or ""
    category = _log_category(path)
    status_code = exc.status_code
    detail = getattr(exc, "detail", None)
    if isinstance(detail, dict):
        detail_str = str(detail)[:400]
    else:
        detail_str = str(detail)[:400] if detail else ""
    message = f"{request.method} {path} → {status_code}"
    details = detail_str if detail_str else None
    append_system_log("error", category, message, details=details)
    return JSONResponse(status_code=status_code, content={"detail": exc.detail})


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    """Log unhandled exceptions to system log so Settings > Logs shows all LB/artist portal errors."""
    path = request.url.path or ""
    category = _log_category(path)
    message = f"{request.method} {path} → 500"
    details = f"{type(exc).__name__}: {str(exc)}"[:500]
    append_system_log("error", category, message, details=details)
    return JSONResponse(status_code=500, content={"detail": "Internal server error"})

# Allow Flutter web (e.g. localhost:port) to call the API from the browser.
# Cannot use allow_origins=["*"] with allow_credentials=True (browser rejects it).
# Explicit headers help some browsers with preflight for multipart + Authorization.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=[
        "Authorization",
        "Content-Type",
        "Accept",
        "Origin",
        "x-demo-token",
        "x-labelops-demo-token",
    ],
    expose_headers=[],
)

app.include_router(router, prefix="/api")
app.include_router(audience_router, prefix="/api")


@app.get("/", response_class=HTMLResponse)
def root() -> str:
    """Clarify that this is the API; the login page is the Flutter app (different URL)."""
    return """
    <!DOCTYPE html>
    <html><head><meta charset="utf-8"><title>LabelOps API</title></head>
    <body style="font-family: sans-serif; max-width: 480px; margin: 2rem auto; padding: 1rem;">
      <h1>LabelOps API</h1>
      <p>This is the backend API. There is no login page here.</p>
      <p><strong>To open the login page:</strong> run the Flutter app (e.g. <code>flutter run -d chrome</code> from <code>apps/client</code>)
         or use the restart script. The app will open in a new window at a URL like <code>http://localhost:XXXXX</code> &mdash; that tab is the login.</p>
      <p>API docs: <a href="/docs">/docs</a> &middot; Health: <a href="/health">/health</a></p>
    </body></html>
    """


@app.get("/health")
def health() -> dict:
    out: dict = {"status": "ok"}
    last = os.environ.get("GIT_LAST_UPDATE")
    if last:
        out["last_git_update"] = last
    build_number = os.environ.get("BUILD_NUMBER")
    if build_number:
        out["build_number"] = build_number
    return out
