import asyncio
import os
import subprocess
from typing import Dict, Iterable, Optional, Tuple

import httpx
from fastapi import FastAPI, Request, WebSocket
from fastapi.responses import RedirectResponse, Response, StreamingResponse

# -----------------------------
# Config
# -----------------------------
APP_HOST = "0.0.0.0"
APP_PORT = int(os.getenv("PORT", "8000"))  # Cerebrium default runtime serves on 8000

JUPYTER_HOST = os.getenv("JUPYTER_HOST", "127.0.0.1")
JUPYTER_PORT = int(os.getenv("JUPYTER_PORT", "8888"))
JUPYTER_URL = f"http://{JUPYTER_HOST}:{JUPYTER_PORT}"
JUPYTER_WS_URL = f"ws://{JUPYTER_HOST}:{JUPYTER_PORT}"

NOTEBOOK_DIR = os.getenv("NOTEBOOK_DIR", "/persistent-storage/notebooks")
# Set JUPYTER_TOKEN as a Cerebrium Secret for stable auth; if empty, Jupyter will generate one.
JUPYTER_TOKEN = os.getenv("JUPYTER_TOKEN", "")

PROJECT_ID = os.getenv("PROJECT_ID", "")
APP_NAME = os.getenv("APP_NAME", "")

# Cerebrium routes apps under /v4/{PROJECT_ID}/{APP_NAME}/...
# In some setups the platform strips this prefix before forwarding to your app; in others it might not.
CEREBRIUM_PREFIX = f"/v4/{PROJECT_ID}/{APP_NAME}" if PROJECT_ID and APP_NAME else ""

# Hop-by-hop headers should not be forwarded by proxies
HOP_BY_HOP_HEADERS = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
}


def _strip_cerebrium_prefix(path: str) -> str:
    if CEREBRIUM_PREFIX and path.startswith(CEREBRIUM_PREFIX):
        stripped = path[len(CEREBRIUM_PREFIX) :]
        return stripped if stripped else "/"
    return path


def _filter_request_headers(headers: Iterable[Tuple[str, str]]) -> Dict[str, str]:
    out: Dict[str, str] = {}
    for k, v in headers:
        lk = k.lower()
        if lk in HOP_BY_HOP_HEADERS:
            continue
        # Let httpx set content-length appropriately
        if lk == "content-length":
            continue
        out[k] = v
    # Ensure upstream Host points at Jupyter
    out["Host"] = f"{JUPYTER_HOST}:{JUPYTER_PORT}"
    return out


def _filter_response_headers(headers: Iterable[Tuple[str, str]]) -> Dict[str, str]:
    out: Dict[str, str] = {}
    for k, v in headers:
        lk = k.lower()
        if lk in HOP_BY_HOP_HEADERS:
            continue
        out[k] = v
    return out


# -----------------------------
# App + lifecycle
# -----------------------------
app = FastAPI()
_jupyter_proc: Optional[subprocess.Popen] = None


@app.on_event("startup")
async def _startup() -> None:
    global _jupyter_proc
    os.makedirs(NOTEBOOK_DIR, exist_ok=True)

    # Start JupyterLab on an internal port; FastAPI will proxy traffic to it.
    cmd = [
        "jupyter",
        "lab",
        "--ip=127.0.0.1",
        f"--port={JUPYTER_PORT}",
        "--no-browser",
        f"--ServerApp.root_dir={NOTEBOOK_DIR}",
        "--ServerApp.allow_remote_access=True",
        "--ServerApp.trust_xheaders=True",
        "--ServerApp.allow_root=True",
        # Reverse-proxy friendliness:
        "--ServerApp.disable_check_xsrf=True",
        "--ServerApp.allow_origin=*",
        "--ServerApp.base_url=/",
        "--ServerApp.default_url=/lab",
    ]
    if JUPYTER_TOKEN:
        cmd.append(f"--ServerApp.token={JUPYTER_TOKEN}")

    _jupyter_proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )

    # Wait briefly for Jupyter to come up (best-effort)
    async with httpx.AsyncClient() as client:
        for _ in range(60):
            try:
                r = await client.get(f"{JUPYTER_URL}/api", timeout=1.0)
                if r.status_code in (200, 302, 403):
                    return
            except Exception:
                pass
            await asyncio.sleep(0.5)


@app.on_event("shutdown")
async def _shutdown() -> None:
    global _jupyter_proc
    if _jupyter_proc and _jupyter_proc.poll() is None:
        _jupyter_proc.terminate()
        try:
            _jupyter_proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            _jupyter_proc.kill()


# -----------------------------
# Health + convenience routes
# -----------------------------
@app.get("/health")
async def health():
    return {"ok": True, "jupyter": JUPYTER_URL}


@app.get("/")
async def root():
    return RedirectResponse(url="/lab")


# -----------------------------
# HTTP reverse proxy (catch-all)
# -----------------------------
@app.api_route("/{full_path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"])
async def proxy_http(request: Request, full_path: str):
    upstream_path = _strip_cerebrium_prefix(request.url.path)
    target_url = f"{JUPYTER_URL}{upstream_path}"

    headers = _filter_request_headers(request.headers.items())
    body = await request.body()

    async with httpx.AsyncClient(follow_redirects=False) as client:
        upstream = await client.stream(
            request.method,
            target_url,
            headers=headers,
            params=request.query_params,
            content=body if body else None,
            timeout=None,
        )

        # Stream the response back to the client
        resp_headers = _filter_response_headers(upstream.headers.items())
        return StreamingResponse(
            upstream.aiter_raw(),
            status_code=upstream.status_code,
            headers=resp_headers,
            media_type=upstream.headers.get("content-type"),
        )


# -----------------------------
# WebSocket reverse proxy (catch-all)
# -----------------------------
@app.websocket("/{full_path:path}")
async def proxy_ws(ws: WebSocket, full_path: str):
    # Accept client websocket
    await ws.accept()

    # Build upstream websocket URL
    upstream_path = _strip_cerebrium_prefix(ws.url.path)
    qs = ws.url.query
    upstream_url = f"{JUPYTER_WS_URL}{upstream_path}"
    if qs:
        upstream_url = f"{upstream_url}?{qs}"

    # Connect upstream websocket and pump messages both ways
    import websockets  # installed via requirements

    # Forward a subset of headers (cookies matter for Jupyter sessions)
    upstream_headers = []
    for k, v in ws.headers.items():
        lk = k.lower()
        if lk in HOP_BY_HOP_HEADERS:
            continue
        if lk == "host":
            continue
        upstream_headers.append((k, v))

    async with websockets.connect(upstream_url, extra_headers=upstream_headers) as upstream:
        async def client_to_upstream():
            while True:
                msg = await ws.receive()
                if msg.get("type") == "websocket.disconnect":
                    await upstream.close()
                    return
                if "text" in msg and msg["text"] is not None:
                    await upstream.send(msg["text"])
                elif "bytes" in msg and msg["bytes"] is not None:
                    await upstream.send(msg["bytes"])

        async def upstream_to_client():
            while True:
                data = await upstream.recv()
                if isinstance(data, bytes):
                    await ws.send_bytes(data)
                else:
                    await ws.send_text(data)

        await asyncio.gather(client_to_upstream(), upstream_to_client())
