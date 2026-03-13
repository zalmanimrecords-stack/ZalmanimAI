from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse

from app.api.audience_routes import router as audience_router
from app.api.routes import router
from app.core.config import settings

app = FastAPI(title=settings.app_name)

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
    return {"status": "ok"}
