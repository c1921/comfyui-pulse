"""Attachment extraction from captured HTTP requests.

Supports multipart form-data, raw binary bodies, JSON-embedded base64,
URL-encoded form base64, and plain-text data URLs.
"""

import json
import re
from datetime import datetime
from email import policy
from email.parser import BytesParser
from pathlib import Path
from urllib.parse import parse_qs

from .events import build_attachment_event, event_bus
from .utils import (
    DATA_URL_RE,
    FILENAME_FIELD_HINTS,
    CONTENT_TYPE_FIELD_HINTS,
    MIN_HINTED_BASE64_CHARS,
    content_type_base,
    decode_base64,
    extension_for_content_type,
    filename_from_request_path,
    has_base64_field_hint,
    is_raw_binary_content_type,
    parse_content_disposition_filename,
    safe_filename_part,
)


def save_attachment_bytes(
    saved,
    download_dir,
    capture_stem,
    payload,
    filename,
    content_type,
    mode,
    field_name="",
):
    """Write *payload* to *download_dir* and append a result dict to *saved*."""
    if not payload:
        return

    attachment_index = len(saved) + 1
    ts = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    ext = extension_for_content_type(content_type or "")
    saved_name = f"{ts}-{attachment_index:03d}{ext}"

    saved_path = download_dir / saved_name
    saved_path.parent.mkdir(parents=True, exist_ok=True)
    saved_path.write_bytes(payload)

    saved.append(
        {
            "mode": mode,
            "field_name": field_name,
            "original_filename": filename or "",
            "content_type": content_type or "application/octet-stream",
            "saved_bytes": len(payload),
            "saved_path": str(saved_path),
        }
    )

    # Publish real-time event for live frontend updates
    event = build_attachment_event(
        saved_path=str(saved_path),
        filename=saved_name,
        content_type=content_type or "",
        size=len(payload),
    )
    event_bus.publish(event)


def save_attachments(body, headers, download_dir, capture_stem, request_path):
    """Try every attachment strategy in order; return the first successful one's results."""
    saved = []
    save_multipart_attachments(body, headers, download_dir, capture_stem, saved)
    if saved:
        return saved

    save_raw_body_attachment(body, headers, download_dir, capture_stem, request_path, saved)
    if saved:
        return saved

    save_json_base64_attachments(body, headers, download_dir, capture_stem, saved)
    if saved:
        return saved

    save_form_base64_attachments(body, headers, download_dir, capture_stem, saved)
    if saved:
        return saved

    save_text_data_url_attachments(body, headers, download_dir, capture_stem, saved)
    return saved


# ---------------------------------------------------------------------------
# Individual strategies
# ---------------------------------------------------------------------------


def save_multipart_attachments(body, headers, download_dir, capture_stem, saved):
    """Extract file parts from ``multipart/form-data`` bodies."""
    content_type = headers.get("Content-Type", "")
    if "multipart/form-data" not in content_type.lower():
        return

    raw_message = (
        f"Content-Type: {content_type}\r\n"
        "MIME-Version: 1.0\r\n"
        "\r\n"
    ).encode("utf-8") + body

    try:
        message = BytesParser(policy=policy.default).parsebytes(raw_message)
    except Exception:
        return

    if not message.is_multipart():
        return

    for part in message.iter_parts():
        filename = part.get_filename()
        if not filename:
            continue

        payload = part.get_payload(decode=True)
        if payload is None:
            continue

        field_name = part.get_param("name", header="Content-Disposition") or ""
        save_attachment_bytes(
            saved=saved,
            download_dir=download_dir,
            capture_stem=capture_stem,
            payload=payload,
            filename=filename,
            content_type=part.get_content_type(),
            mode="multipart",
            field_name=field_name,
        )


def save_raw_body_attachment(body, headers, download_dir, capture_stem, request_path, saved):
    """Save the raw body when the Content-Type is a known binary type."""
    if not body:
        return
    content_type = headers.get("Content-Type", "")
    if not is_raw_binary_content_type(content_type):
        return

    filename = parse_content_disposition_filename(headers.get("Content-Disposition"))
    if not filename:
        filename = filename_from_request_path(request_path)
    if not filename:
        filename = "body" + extension_for_content_type(content_type)

    save_attachment_bytes(
        saved=saved,
        download_dir=download_dir,
        capture_stem=capture_stem,
        payload=body,
        filename=filename,
        content_type=content_type_base(content_type) or "application/octet-stream",
        mode="raw-body",
    )


def save_json_base64_attachments(body, headers, download_dir, capture_stem, saved):
    """Scan a JSON body for base64-encoded fields and save them."""
    if content_type_base(headers.get("Content-Type")) != "application/json":
        return
    try:
        payload = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return
    scan_json_value(payload, "", None, download_dir, capture_stem, saved)


def scan_json_value(value, path, parent, download_dir, capture_stem, saved):
    """Recursively walk a parsed JSON tree looking for base64 strings."""
    if isinstance(value, dict):
        for key, child in value.items():
            child_path = f"{path}.{key}" if path else str(key)
            scan_json_value(child, child_path, value, download_dir, capture_stem, saved)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            child_path = f"{path}[{index}]"
            scan_json_value(child, child_path, None, download_dir, capture_stem, saved)
    elif isinstance(value, str):
        filename, content_type = metadata_from_mapping(parent)
        save_base64_string_if_attachment(
            value=value,
            field_name=path,
            mode="json-base64",
            filename=filename,
            content_type=content_type,
            download_dir=download_dir,
            capture_stem=capture_stem,
            saved=saved,
        )


def metadata_from_mapping(mapping):
    """Extract filename & content-type hints from a sibling dict mapping."""
    if not isinstance(mapping, dict):
        return "", ""

    lowered = {str(key).lower(): value for key, value in mapping.items() if isinstance(value, str)}
    filename = ""
    content_type = ""

    for key in FILENAME_FIELD_HINTS:
        if key in lowered:
            filename = lowered[key]
            break
    for key in CONTENT_TYPE_FIELD_HINTS:
        if key in lowered and "/" in lowered[key]:
            content_type = lowered[key]
            break

    return filename, content_type


def save_form_base64_attachments(body, headers, download_dir, capture_stem, saved):
    """Scan a URL-encoded form body for base64-encoded fields."""
    if content_type_base(headers.get("Content-Type")) != "application/x-www-form-urlencoded":
        return
    try:
        form = parse_qs(body.decode("utf-8"), keep_blank_values=True)
    except UnicodeDecodeError:
        return

    flattened = {key: values[-1] for key, values in form.items() if values}
    filename, content_type = metadata_from_mapping(flattened)

    for key, values in form.items():
        for value in values:
            save_base64_string_if_attachment(
                value=value,
                field_name=key,
                mode="form-base64",
                filename=filename,
                content_type=content_type,
                download_dir=download_dir,
                capture_stem=capture_stem,
                saved=saved,
            )


def save_text_data_url_attachments(body, headers, download_dir, capture_stem, saved):
    """Extract ``data:`` URLs embedded in a text/* body."""
    base = content_type_base(headers.get("Content-Type"))
    if base and not base.startswith("text/"):
        return
    try:
        text = body.decode("utf-8")
    except UnicodeDecodeError:
        return
    for index, match in enumerate(DATA_URL_RE.finditer(text), start=1):
        content_type = match.group(1) or "application/octet-stream"
        decoded = decode_base64(match.group(2))
        if decoded is None:
            continue
        filename = f"data-url-{index}{extension_for_content_type(content_type)}"
        save_attachment_bytes(
            saved=saved,
            download_dir=download_dir,
            capture_stem=capture_stem,
            payload=decoded,
            filename=filename,
            content_type=content_type,
            mode="data-url",
            field_name=f"data-url[{index}]",
        )


def save_base64_string_if_attachment(
    value,
    field_name,
    mode,
    filename,
    content_type,
    download_dir,
    capture_stem,
    saved,
):
    """Check if *value* is a base64-encoded attachment; if so save it."""
    data_url = DATA_URL_RE.fullmatch(value.strip())
    if data_url:
        detected_content_type = data_url.group(1) or content_type or "application/octet-stream"
        decoded = decode_base64(data_url.group(2))
        if decoded is None:
            return
        target_name = filename or field_name_filename(field_name, detected_content_type)
        save_attachment_bytes(
            saved=saved,
            download_dir=download_dir,
            capture_stem=capture_stem,
            payload=decoded,
            filename=target_name,
            content_type=detected_content_type,
            mode=mode if mode != "form-base64" else "form-base64",
            field_name=field_name,
        )
        return

    if not has_base64_field_hint(field_name):
        return
    stripped = re.sub(r"\s+", "", value)
    if len(stripped) < MIN_HINTED_BASE64_CHARS:
        return

    decoded = decode_base64(stripped)
    if decoded is None:
        return

    target_content_type = content_type or "application/octet-stream"
    target_name = filename or field_name_filename(field_name, target_content_type)
    save_attachment_bytes(
        saved=saved,
        download_dir=download_dir,
        capture_stem=capture_stem,
        payload=decoded,
        filename=target_name,
        content_type=target_content_type,
        mode=mode,
        field_name=field_name,
    )
