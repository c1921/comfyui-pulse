"""Command-line entry point for the request capture server."""

import argparse
import sys
from pathlib import Path

from .server import CaptureServer, RequestCaptureHandler


def parse_args(argv):
    """Parse and validate command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Capture any local HTTP request and save each request as a text file."
    )
    parser.add_argument("--host", default="127.0.0.1", help="Host to bind. Use 0.0.0.0 for LAN access.")
    parser.add_argument("--port", type=int, default=8088, help="Port to bind.")
    parser.add_argument(
        "--save-request-info",
        action="store_true",
        help="Save full request details as text files. Default: disabled.",
    )
    parser.add_argument(
        "--out",
        default="requests",
        help="Directory for captured request text files when --save-request-info is enabled.",
    )
    parser.add_argument(
        "--max-body-bytes",
        type=int,
        default=None,
        help="Maximum request body bytes to save per request. Default: unlimited.",
    )
    parser.add_argument(
        "--frontend-dir",
        default=None,
        help="Path to the built frontend dist directory. When set, the server will serve "
        "frontend static files and the SPA for GET requests.",
    )
    args = parser.parse_args(argv)

    if args.port < 1 or args.port > 65535:
        parser.error("--port must be between 1 and 65535")
    if args.max_body_bytes is not None and args.max_body_bytes < 0:
        parser.error("--max-body-bytes must be zero or greater")

    return args


def main(argv=None):
    """Start the capture server."""
    args = parse_args(argv if argv is not None else sys.argv[1:])
    output_dir = Path(args.out)
    download_dir = Path(__file__).resolve().parent.parent.parent / "downloads"
    try:
        if args.save_request_info:
            output_dir.mkdir(parents=True, exist_ok=True)
        download_dir.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        print(f"Cannot create output directory: {exc}", file=sys.stderr)
        return 1

    server = CaptureServer(
        (args.host, args.port),
        RequestCaptureHandler,
        output_dir=output_dir,
        download_dir=download_dir,
        max_body_bytes=args.max_body_bytes,
        save_request_info=args.save_request_info,
        frontend_dir=args.frontend_dir,
    )

    print(f"Listening on http://{args.host}:{args.port}", flush=True)
    if args.save_request_info:
        print(f"Saving request info to {output_dir.resolve()}", flush=True)
    else:
        print("Request info saving is disabled. Use --save-request-info to enable it.", flush=True)
    print(f"Saving attachments to {download_dir.resolve()}", flush=True)
    if args.frontend_dir:
        print(f"Serving frontend static files from {Path(args.frontend_dir).resolve()}", flush=True)
    print("Press Ctrl+C to stop.", flush=True)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping.", flush=True)
    finally:
        server.server_close()
    return 0
