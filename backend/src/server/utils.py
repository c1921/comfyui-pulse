"""Utility functions for request capture and attachment handling."""

import base64
import binascii
import json
import mimetypes
import re
from pathlib import Path
from urllib.parse import unquote, urlsplit

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

BASE64_FIELD_HINTS = (
    "file",
    "image",
    "attachment",
    "base64",
    "b64",
    "content",
    "bytes",
    "data",
)

FILENAME_FIELD_HINTS = ("filename", "file_name", "name")
CONTENT_TYPE_FIELD_HINTS = ("content_type", "content-type", "mime", "mime_type", "type")

DATA_URL_RE = re.compile(
    r"data:([^;,\s]+)?(?:;[^,]*)?;base64,([A-Za-z0-9+/=_-]+)",
    re.IGNORECASE,
)

MIN_HINTED_BASE64_CHARS = 80

# ---------------------------------------------------------------------------
# Filename / content-type helpers
# ---------------------------------------------------------------------------


def safe_filename_part(value: str) -> str:
    """Replace unsafe filename characters with underscores."""
    value = re.sub(r"[^A-Za-z0-9._-]+", "_", value)
    return value.strip("._-")


def safe_original_filename(filename: str) -> str:
    """Sanitise a user-supplied filename to a safe filesystem name."""
    filename = Path(filename).name
    filename = re.sub(r'[<>:"/\\|?*\x00-\x1f]+', "_", filename)
    filename = filename.strip(" ._")
    return filename or "attachment.bin"


def content_type_base(content_type: str | None) -> str:
    """Return the MIME type without parameters (e.g. ``image/png``)."""
    return (content_type or "").split(";", 1)[0].strip().lower()


def extension_for_content_type(content_type: str) -> str:
    """Guess a file extension from a MIME type."""
    base = content_type_base(content_type)
    if not base:
        return ".bin"
    if base == "image/jpeg":
        return ".jpg"
    extension = mimetypes.guess_extension(base)
    return extension or ".bin"


def ensure_extension(filename: str, content_type: str) -> str:
    """Append a guessed extension if *filename* has none."""
    path = Path(filename)
    if path.suffix:
        return filename
    return filename + extension_for_content_type(content_type)


def parse_content_disposition_filename(value: str | None) -> str:
    """Extract the filename from a ``Content-Disposition`` header value."""
    if not value:
        return ""
    match = re.search(r'filename\*=(?:UTF-8\'\')?([^;\r\n]+)', value, re.IGNORECASE)
    if match:
        return unquote(match.group(1).strip().strip('"'))
    match = re.search(r'filename=("[^"]+"|[^;\r\n]+)', value, re.IGNORECASE)
    if match:
        return match.group(1).strip().strip('"')
    return ""


def filename_from_request_path(request_path: str) -> str:
    """Derive a filename from the URL path tail, if it looks like one."""
    parsed = urlsplit(request_path)
    candidate = unquote(Path(parsed.path).name)
    if "." in candidate:
        return candidate
    return ""


def is_raw_binary_content_type(content_type: str) -> bool:
    """Check whether a MIME type should be treated as raw binary data."""
    base = content_type_base(content_type)
    if base.startswith(("image/", "audio/", "video/")):
        return True
    return base in {
        "application/octet-stream",
        "application/pdf",
        "application/zip",
        "application/x-zip-compressed",
        "application/gzip",
        "application/x-gzip",
        "application/x-tar",
        "application/x-7z-compressed",
        "application/msword",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "application/vnd.ms-excel",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "application/vnd.ms-powerpoint",
        "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    }


# ---------------------------------------------------------------------------
# Base64 helpers
# ---------------------------------------------------------------------------


def has_base64_field_hint(field_name: str) -> bool:
    """Check if a form/JSON field name suggests it contains base64 data."""
    lowered = field_name.lower()
    return any(hint in lowered for hint in BASE64_FIELD_HINTS)


def field_name_filename(field_name: str, content_type: str) -> str:
    """Derive a filename from a field name and content type."""
    base = safe_filename_part(field_name.replace("[", "_").replace("]", "")) or "attachment"
    return base + extension_for_content_type(content_type)


def decode_base64(value: str) -> bytes | None:
    """Decode a base64 (or base64url) string; return ``None`` on failure."""
    compact = re.sub(r"\s+", "", value)
    compact += "=" * ((4 - len(compact) % 4) % 4)
    try:
        return base64.b64decode(compact, validate=True)
    except (binascii.Error, ValueError):
        try:
            return base64.urlsafe_b64decode(compact)
        except (binascii.Error, ValueError):
            return None


# ---------------------------------------------------------------------------
# JSON formatting helper
# ---------------------------------------------------------------------------


def format_json_if_possible(body: bytes) -> str | None:
    """Pretty-print *body* as JSON if it looks like valid JSON."""
    stripped = body.strip()
    if not stripped or stripped[:1] not in (b"{", b"["):
        return None
    try:
        parsed = json.loads(stripped.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return None
    return json.dumps(parsed, ensure_ascii=False, indent=2, sort_keys=True)
