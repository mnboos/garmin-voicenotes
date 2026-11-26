"""Single-user Voicenotes receiver. Put behind an HTTPS reverse proxy for watches."""
from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import logging
import os
from pathlib import Path
import re
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOG = logging.getLogger("voicenotes")
# Sanity guards only; the watch limits notes by duration, not size.
MAX_NOTE_BYTES = 40_000_000
MAX_CHUNKS = 10_000  # chunk files use four-digit names
MAX_DISK_BYTES = 1_000_000_000
NOTE_PATH = re.compile(r"/api/notes/([a-zA-Z0-9-]{1,100})/(?:chunks/(\d+)|complete)")


class UploadError(Exception):
    def __init__(self, status: int, message: str):
        self.status = status
        super().__init__(message)


class Repository:
    def __init__(self, root: Path):
        self.root = root
        root.mkdir(parents=True, exist_ok=True)
        self.lock = threading.Lock()

    def atomic_write(self, path: Path, content: bytes):
        temp = path.with_suffix(path.suffix + ".tmp")
        with temp.open("wb") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        temp.replace(path)

    def check_capacity(self, additional_bytes: int):
        used = sum(path.stat().st_size for path in self.root.rglob("*") if path.is_file())
        if used + additional_bytes > MAX_DISK_BYTES:
            raise UploadError(507, "Receiver storage full")

    def put_chunk(self, note_id: str, index: int, content: bytes):
        if not 0 <= index < MAX_CHUNKS or not 0 < len(content) <= 4096:
            raise UploadError(400, "Invalid chunk")
        with self.lock:
            folder = self.root / note_id
            folder.mkdir(exist_ok=True)
            target = folder / f"{index:04d}.chunk"
            if target.exists():
                if target.read_bytes() != content:
                    raise UploadError(409, "Chunk conflicts with an existing upload")
                return
            if (folder / "metadata.json").exists():
                raise UploadError(409, "Note already complete")
            if sum(p.stat().st_size for p in folder.glob("*.chunk")) + len(content) > MAX_NOTE_BYTES:
                raise UploadError(413, "Note too large")
            self.check_capacity(len(content))
            self.atomic_write(target, content)

    def complete(self, note_id: str, meta: dict):
        count = meta.get("chunks")
        size = meta.get("bytes")
        extension = meta.get("extension")
        if (
            meta.get("id") != note_id
            or type(count) is not int or not 1 <= count <= MAX_CHUNKS
            or type(size) is not int or not 0 < size <= MAX_NOTE_BYTES
            or extension not in ("ogg", "wav")
        ):
            raise UploadError(400, "Invalid note metadata")
        location = meta.get("location")
        if location is not None and (
            not isinstance(location, list) or len(location) != 2
            or any(type(value) not in (int, float) or not -limit <= value <= limit
                   for value, limit in zip(location, (90, 180)))
        ):
            raise UploadError(400, "Invalid note location")
        with self.lock:
            folder = self.root / note_id
            chunks = [folder / f"{index:04d}.chunk" for index in range(count)]
            if any(not chunk.is_file() for chunk in chunks):
                raise UploadError(409, "Missing chunks; retry upload")
            audio = b"".join(chunk.read_bytes() for chunk in chunks)
            if len(audio) != size or len(list(folder.glob("*.chunk"))) != count:
                raise UploadError(409, "Size or chunk count mismatch")
            if extension == "ogg":
                valid_header = audio.startswith(b"OggS")
            else:
                valid_header = audio.startswith(b"RIFF") and audio[8:12] == b"WAVE"
            if not valid_header:
                raise UploadError(422, "Audio container header missing")
            digest = hashlib.sha256(audio).hexdigest()
            metadata_path = folder / "metadata.json"
            if metadata_path.exists():
                existing = json.loads(metadata_path.read_text())
                if existing["sha256"] != digest or existing["extension"] != extension:
                    raise UploadError(409, "Finalized note differs")
                return
            saved = {key: meta.get(key) for key in ("id", "created", "seconds", "state", "chunks", "bytes", "extension", "format")}
            if location is not None:
                saved["location"] = location
            saved["sha256"] = digest
            metadata = json.dumps(saved, indent=2).encode()
            audio_path = folder / f"note.{extension}"
            # An interrupted finalization may already have written the audio.
            previous_size = audio_path.stat().st_size if audio_path.exists() else 0
            self.check_capacity(len(metadata) + max(0, len(audio) - previous_size))
            self.atomic_write(audio_path, audio)
            self.atomic_write(metadata_path, metadata)
            LOG.info("Note saved: %s, %d bytes", note_id, size)


class Receiver(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, root: Path, token: str):
        self.repository = Repository(root)
        self.token = token
        super().__init__(address, Handler)


class Handler(BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        self.connection.settimeout(20)

    def log_message(self, fmt, *args):
        # Never log access tokens, headers, or audio bodies.
        LOG.debug(fmt, *args)

    def respond(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def handle_upload(self):
        try:
            supplied = self.headers.get("Authorization", "")
            if not hmac.compare_digest(supplied.encode(), ("Bearer " + self.server.token).encode()):
                raise UploadError(401, "Unauthorized")
            match = NOTE_PATH.fullmatch(self.path)
            if not match:
                raise UploadError(404, "Unknown endpoint")
            note_id, chunk_index = match.groups()
            if (self.command == "PUT") != (chunk_index is not None):
                raise UploadError(405, "Wrong method")
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 8192 or self.headers.get("Transfer-Encoding"):
                raise UploadError(413, "Invalid request size")
            body = self.rfile.read(length)
            if len(body) != length:
                raise UploadError(400, "Incomplete request")
            if chunk_index is not None:
                self.server.repository.put_chunk(note_id, int(chunk_index), body)
            else:
                metadata = json.loads(body)
                if not isinstance(metadata, dict):
                    raise UploadError(400, "Expected metadata object")
                self.server.repository.complete(note_id, metadata)
            self.respond(200, {"ok": True})
        except UploadError as error:
            self.respond(error.status, {"ok": False, "error": str(error)})
        except ValueError:
            self.respond(400, {"ok": False, "error": "Invalid request"})
        except OSError:
            LOG.exception("Receiver I/O failure")
            self.respond(503, {"ok": False, "error": "Storage unavailable; retry later"})

    do_PUT = handle_upload
    do_POST = handle_upload


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--data", type=Path, default=Path("data"))
    args = parser.parse_args()
    token = os.environ.get("VOICENOTES_TOKEN", "")
    if len(token) < 32 or not token.isascii():
        parser.error("Set VOICENOTES_TOKEN to a random ASCII token of at least 32 characters")
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    with Receiver((args.host, args.port), args.data, token) as server:
        LOG.info("Voicenotes receiver listening on %s:%d", args.host, args.port)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
