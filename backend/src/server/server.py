"""HTTP server classes for capturing local requests."""

import json
import mimetypes
import queue
import threading
from datetime import datetime
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

from .attachment import save_attachments
from .events import event_bus
from .utils import format_json_if_possible, safe_filename_part


class CaptureServer(ThreadingHTTPServer):
    """Multi-threaded HTTP server that captures incoming requests."""

    daemon_threads = True

    def __init__(
        self,
        server_address,
        handler_class,
        output_dir,
        download_dir,
        max_body_bytes,
        save_request_info,
        frontend_dir=None,
    ):
        super().__init__(server_address, handler_class)
        self.output_dir = Path(output_dir)
        self.download_dir = Path(download_dir)
        self.max_body_bytes = max_body_bytes
        self.save_request_info = save_request_info
        self.frontend_dir = Path(frontend_dir) if frontend_dir else None
        self._counter = 0
        self._counter_lock = threading.Lock()

    def next_counter(self):
        with self._counter_lock:
            self._counter += 1
            return self._counter


class RequestCaptureHandler(BaseHTTPRequestHandler):
    """Request handler that saves every request as a text file."""

    server_version = "LocalRequestCapture/1.0"
    protocol_version = "HTTP/1.1"

    # ------------------------------------------------------------------
    # Request lifecycle
    # ------------------------------------------------------------------

    def handle_one_request(self):
        """Read and parse one HTTP request, then capture it."""
        try:
            self.raw_requestline = self.rfile.readline(65537)
            if len(self.raw_requestline) > 65536:
                self.requestline = ""
                self.request_version = ""
                self.command = ""
                self.send_error(HTTPStatus.REQUEST_URI_TOO_LONG)
                return
            if not self.raw_requestline:
                self.close_connection = True
                return
            if not self.parse_request():
                return

            # Route requests: API, downloads, frontend static, then capture
            parsed_path = urlsplit(self.path).path
            if parsed_path.startswith("/api/") or parsed_path.startswith("/downloads/"):
                self.handle_management_request()
                self.wfile.flush()
                return

            # Serve frontend static files for GET requests when frontend_dir is configured
            if self.command == "GET" and self.server.frontend_dir:
                if self.try_serve_frontend(parsed_path):
                    self.wfile.flush()
                    return

            self.capture_request()
            self.wfile.flush()
        except TimeoutError:
            self.log_error("Request timed out: %r", self.client_address)
            self.close_connection = True

    # ------------------------------------------------------------------
    # Capture logic
    # ------------------------------------------------------------------

    def capture_request(self):
        """Process the request: read body, save attachments, write info."""
        received_at = datetime.now().astimezone()
        body, body_meta = self.read_body()
        capture_stem = self.build_capture_stem(received_at)

        attachment_results = []
        attachment_note = ""
        if body_meta.get("truncated"):
            attachment_note = "Skipped because request body was truncated by --max-body-bytes."
        else:
            attachment_results = save_attachments(
                body=body,
                headers=self.headers,
                download_dir=self.server.download_dir,
                capture_stem=capture_stem,
                request_path=self.path,
            )

        saved_path = None
        if self.server.save_request_info:
            saved_path = self.write_request_info(
                received_at=received_at,
                body=body,
                body_meta=body_meta,
                capture_stem=capture_stem,
                attachment_results=attachment_results,
                attachment_note=attachment_note,
            )

        response = {
            "ok": True,
            "saved": str(saved_path) if saved_path is not None else None,
            "attachments": [item["saved_path"] for item in attachment_results],
            "request_info_saved": saved_path is not None,
        }
        response_bytes = json.dumps(response, ensure_ascii=False).encode("utf-8")

        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(0 if self.command == "HEAD" else len(response_bytes)))
        self.send_header("Connection", "close" if self.close_connection else "keep-alive")
        if self.command == "OPTIONS":
            self.send_header("Allow", "GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(response_bytes)

        print(
            f"[{received_at.strftime('%Y-%m-%d %H:%M:%S')}] "
            f"{self.client_address[0]}:{self.client_address[1]} "
            f"{self.command} {self.path} -> "
            f"request_info={saved_path if saved_path is not None else 'disabled'} "
            f"attachments={len(attachment_results)}",
            flush=True,
        )

    def build_capture_stem(self, received_at):
        """Build a unique filename stem for the captured request."""
        counter = self.server.next_counter()
        parsed = urlsplit(self.path)
        path_part = parsed.path.strip("/") or "root"
        safe_path = safe_filename_part(path_part)[:80] or "root"
        method = safe_filename_part(self.command or "UNKNOWN")[:24] or "UNKNOWN"
        return f"{received_at.strftime('%Y%m%d-%H%M%S-%f')}-{counter:06d}-{method}-{safe_path}"

    # ------------------------------------------------------------------
    # Body reading
    # ------------------------------------------------------------------

    def read_body(self):
        """Read the request body, respecting Content-Length / chunked encoding."""
        max_body_bytes = self.server.max_body_bytes
        content_length = self.headers.get("Content-Length")
        transfer_encoding = self.headers.get("Transfer-Encoding", "")

        if content_length is not None:
            try:
                expected = int(content_length)
            except ValueError:
                return b"", {
                    "source": "invalid-content-length",
                    "expected_bytes": content_length,
                    "saved_bytes": 0,
                    "truncated": False,
                }

            if expected <= 0:
                return b"", {
                    "source": "content-length",
                    "expected_bytes": expected,
                    "saved_bytes": 0,
                    "truncated": False,
                }

            read_size = expected
            truncated = False
            skipped_bytes = 0
            if max_body_bytes is not None and expected > max_body_bytes:
                read_size = max_body_bytes
                truncated = True
                skipped_bytes = expected - max_body_bytes
                self.close_connection = True

            body = self.rfile.read(read_size)
            return body, {
                "source": "content-length",
                "expected_bytes": expected,
                "saved_bytes": len(body),
                "truncated": truncated,
                "skipped_bytes": skipped_bytes,
            }

        if "chunked" in transfer_encoding.lower():
            body, meta = self.read_chunked_body(max_body_bytes)
            return body, meta

        return b"", {
            "source": "none",
            "expected_bytes": 0,
            "saved_bytes": 0,
            "truncated": False,
        }

    def read_chunked_body(self, max_body_bytes):
        """Read a ``Transfer-Encoding: chunked`` body."""
        chunks = []
        saved_bytes = 0
        truncated = False

        while True:
            size_line = self.rfile.readline(65537)
            if not size_line:
                self.close_connection = True
                break
            if len(size_line) > 65536:
                self.close_connection = True
                break

            size_token = size_line.split(b";", 1)[0].strip()
            try:
                chunk_size = int(size_token, 16)
            except ValueError:
                self.close_connection = True
                break

            if chunk_size == 0:
                while True:
                    trailer_line = self.rfile.readline(65537)
                    if trailer_line in (b"\r\n", b"\n", b""):
                        break
                break

            allowed = chunk_size
            if max_body_bytes is not None:
                remaining = max_body_bytes - saved_bytes
                if remaining <= 0:
                    truncated = True
                    self.close_connection = True
                    break
                allowed = min(chunk_size, remaining)

            data = self.rfile.read(allowed)
            chunks.append(data)
            saved_bytes += len(data)

            unread = chunk_size - allowed
            if unread:
                truncated = True
                self.close_connection = True
                break

            self.rfile.read(2)

        body = b"".join(chunks)
        return body, {
            "source": "chunked",
            "expected_bytes": "chunked",
            "saved_bytes": len(body),
            "truncated": truncated,
        }

    # ------------------------------------------------------------------
    # Request info writer
    # ------------------------------------------------------------------

    def write_request_info(
        self,
        received_at,
        body,
        body_meta,
        capture_stem,
        attachment_results,
        attachment_note,
    ):
        """Write a human-readable .txt file with full request details."""
        output_dir = self.server.output_dir
        output_dir.mkdir(parents=True, exist_ok=True)

        parsed = urlsplit(self.path)
        file_path = output_dir / f"{capture_stem}.txt"

        body_text = body.decode("utf-8", errors="replace")
        sections = [
            "REQUEST CAPTURE",
            "",
            f"Received-At: {received_at.isoformat()}",
            f"Client: {self.client_address[0]}:{self.client_address[1]}",
            f"Method: {self.command}",
            f"Full-Path: {self.path}",
            f"Path: {parsed.path}",
            f"Query: {parsed.query}",
            f"HTTP-Version: {self.request_version}",
            "",
            "HEADERS",
        ]

        for key, value in self.headers.items():
            sections.append(f"{key}: {value}")

        sections.extend(
            [
                "",
                "BODY META",
                f"Read-Source: {body_meta.get('source')}",
                f"Expected-Bytes: {body_meta.get('expected_bytes')}",
                f"Saved-Bytes: {body_meta.get('saved_bytes')}",
                f"Truncated: {body_meta.get('truncated')}",
            ]
        )
        if "skipped_bytes" in body_meta:
            sections.append(f"Skipped-Bytes: {body_meta['skipped_bytes']}")

        if attachment_note:
            sections.extend(["", "ATTACHMENT EXTRACTION", attachment_note])

        if attachment_results:
            sections.extend(["", "ATTACHMENTS"])
            for item in attachment_results:
                sections.append(f"Mode: {item['mode']}")
                sections.append(f"Field-Name: {item['field_name']}")
                sections.append(f"Original-Filename: {item['original_filename']}")
                sections.append(f"Content-Type: {item['content_type']}")
                sections.append(f"Saved-Bytes: {item['saved_bytes']}")
                sections.append(f"Saved-Path: {item['saved_path']}")
                sections.append("")

        sections.extend(["", "BODY TEXT", body_text])

        formatted_json = format_json_if_possible(body)
        if formatted_json is not None:
            sections.extend(["", "FORMATTED JSON", formatted_json])

        file_path.write_text("\n".join(sections) + "\n", encoding="utf-8")
        return file_path

    # ------------------------------------------------------------------
    # Silence default logging
    # ------------------------------------------------------------------


    def log_message(self, format, *args):
        return

    # ------------------------------------------------------------------
    # Management API (frontend SSE, file listing, static files)
    # ------------------------------------------------------------------

    def handle_management_request(self):
        """Route API and static file requests."""
        parsed_path = urlsplit(self.path).path

        if self.command == "GET" and parsed_path == "/api/events":
            self.handle_sse()
        elif self.command == "GET" and parsed_path == "/api/captures":
            self.handle_list_captures()
        elif parsed_path.startswith("/downloads/"):
            self.serve_download_file(parsed_path)
        else:
            self.send_json_response({"error": "Not found"}, HTTPStatus.NOT_FOUND)

    def send_cors_headers(self):
        """Add CORS headers so the frontend can access the API."""
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def send_json_response(self, data, status=HTTPStatus.OK):
        """Send a JSON response with standard headers."""
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_cors_headers()
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def handle_sse(self):
        """Server-Sent Events endpoint for real-time file notifications."""
        self.send_response(HTTPStatus.OK)
        self.send_cors_headers()
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.end_headers()

        q = event_bus.subscribe()
        try:
            while not self.close_connection:
                try:
                    event = q.get(timeout=15.0)
                    data = json.dumps(event, ensure_ascii=False)
                    line = "data: " + data + "\n\n"
                    self.wfile.write(line.encode("utf-8"))
                    self.wfile.flush()
                except queue.Empty:
                    self.wfile.write(b": keepalive\n\n")
                    self.wfile.flush()
        except (ConnectionError, BrokenPipeError, OSError):
            pass
        finally:
            event_bus.unsubscribe(q)

    def handle_list_captures(self):
        """Return a JSON list of all files in the download directory."""
        download_dir = self.server.download_dir
        entries = []
        if download_dir.is_dir():
            for child in sorted(download_dir.iterdir(), key=lambda p: p.stat().st_mtime, reverse=True):
                if not child.is_file():
                    continue
                stat = child.stat()
                ct = mimetypes.guess_type(child.name)[0] or "application/octet-stream"
                ext = child.suffix.lower().lstrip(".")
                image_exts = {"jpg", "jpeg", "png", "gif", "webp", "bmp", "svg", "tiff", "tif", "ico"}
                entries.append({
                    "name": child.name,
                    "path": "/downloads/" + child.name,
                    "size": stat.st_size,
                    "mtime": datetime.fromtimestamp(stat.st_mtime).isoformat(),
                    "content_type": ct,
                    "is_image": ext in image_exts or ct.startswith("image/"),
                })
        self.send_json_response({"captures": entries})

    def serve_download_file(self, request_path):
        """Serve a static file from the downloads directory."""
        filename = Path(request_path).name
        if ".." in filename or "/" in filename:
            self.send_json_response({"error": "Forbidden"}, HTTPStatus.FORBIDDEN)
            return

        file_path = self.server.download_dir / filename
        if not file_path.is_file():
            self.send_json_response({"error": "Not found"}, HTTPStatus.NOT_FOUND)
            return

        ct = mimetypes.guess_type(filename)[0] or "application/octet-stream"
        stat = file_path.stat()
        try:
            with open(file_path, "rb") as f:
                data = f.read()
        except OSError:
            self.send_json_response({"error": "Internal error"}, HTTPStatus.INTERNAL_SERVER_ERROR)
            return

        self.send_response(HTTPStatus.OK)
        self.send_cors_headers()
        self.send_header("Content-Type", ct)
        self.send_header("Content-Length", str(stat.st_size))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    # ------------------------------------------------------------------
    # Frontend static file serving
    # ------------------------------------------------------------------

    def try_serve_frontend(self, parsed_path):
        """Try to serve a file from the frontend dist directory.

        Returns True if the file was served, False if caller should fall
        through to normal capture logic.
        """
        frontend_dir = self.server.frontend_dir
        if not frontend_dir or not frontend_dir.is_dir():
            return False

        # Map the request path to a file inside frontend_dir
        if parsed_path == "/":
            relative = "index.html"
        else:
            relative = parsed_path.lstrip("/")

        # Prevent path traversal
        if ".." in relative:
            return False

        file_path = frontend_dir / relative
        if not file_path.is_file():
            return False

        ct = mimetypes.guess_type(file_path.name)[0] or "application/octet-stream"
        try:
            with open(file_path, "rb") as f:
                data = f.read()
        except OSError:
            return False

        self.send_response(HTTPStatus.OK)
        self.send_cors_headers()
        self.send_header("Content-Type", ct)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)
        return True

