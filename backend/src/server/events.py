"""Simple thread-safe event bus for real-time file notifications."""

import json
import queue
import threading
from datetime import datetime


class EventBus:
    """A pub/sub event bus for broadcasting file-save events to SSE clients."""

    def __init__(self):
        self._subscribers: list[queue.Queue] = []
        self._lock = threading.Lock()

    def subscribe(self) -> queue.Queue:
        """Register a new subscriber and return its queue."""
        q: queue.Queue = queue.Queue()
        with self._lock:
            self._subscribers.append(q)
        return q

    def unsubscribe(self, q: queue.Queue) -> None:
        """Remove a subscriber queue."""
        with self._lock:
            try:
                self._subscribers.remove(q)
            except ValueError:
                pass

    def publish(self, event: dict) -> None:
        """Publish an event to all subscribers."""
        with self._lock:
            dead: list[queue.Queue] = []
            for q in self._subscribers:
                try:
                    q.put_nowait(event)
                except queue.Full:
                    dead.append(q)
            for q in dead:
                try:
                    self._subscribers.remove(q)
                except ValueError:
                    pass


event_bus = EventBus()


def build_attachment_event(
    saved_path: str,
    filename: str,
    content_type: str,
    size: int,
) -> dict:
    """Build a standardized event dict for a newly saved attachment."""
    ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
    image_exts = {"jpg", "jpeg", "png", "gif", "webp", "bmp", "svg", "tiff", "tif", "ico"}
    is_image = ext in image_exts or (content_type or "").startswith("image/")

    return {
        "type": "new_attachment",
        "name": filename,
        "path": f"/downloads/{filename}",
        "size": size,
        "content_type": content_type or "application/octet-stream",
        "is_image": is_image,
        "mtime": datetime.now().isoformat(),
    }
