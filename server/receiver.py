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
import smtplib
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

if __package__:
    from .mail_delivery import MailDelivery
else:
    from mail_delivery import MailDelivery

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
    def __init__(self, root: Path, archive: Path | None = None, email_enabled: bool = False):
        self.root = root
        self.archive = archive
        self.email_enabled = email_enabled
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
            audio_path = folder / f"note.{extension}"
            if metadata_path.exists():
                saved = json.loads(metadata_path.read_text())
                if saved["sha256"] != digest or saved["extension"] != extension:
                    raise UploadError(409, "Finalized note differs")
                if not audio_path.is_file():
                    self.check_capacity(size)
                    self.atomic_write(audio_path, audio)
            else:
                # Preserve exactly what the watch sent.
                saved = {key: meta.get(key) for key in ("id", "created", "seconds", "state", "chunks", "bytes", "extension", "format")}
                if location is not None:
                    saved["location"] = location
                saved["sha256"] = digest
                metadata = json.dumps(saved, indent=2).encode()
                previous_size = audio_path.stat().st_size if audio_path.exists() else 0
                self.check_capacity(len(metadata) + max(0, size - previous_size))
                self.atomic_write(audio_path, audio)
                self.atomic_write(metadata_path, metadata)
                LOG.info("Note saved: %s, %d bytes", note_id, size)

            if self.archive is not None:
                destination = self.archive / f"{note_id}.{extension}"
                if not destination.is_file() or destination.stat().st_size != size or destination.read_bytes() != audio:
                    self.atomic_write(destination, audio)
            if self.email_enabled and "email" not in saved:
                saved["email"] = "pending"
                self.save_metadata(metadata_path, saved)

    def save_metadata(self, path: Path, metadata: dict):
        self.atomic_write(path, json.dumps(metadata, indent=2).encode())


class EmailQueue:
    def __init__(self, repository: Repository, delivery: MailDelivery):
        self.repository = repository
        self.delivery = delivery
        self.accepted = set()

    def deliver_pending(self, stop: threading.Event | None = None):
        for path in self.repository.root.glob("*/metadata.json"):
            if stop is not None and stop.is_set():
                return
            try:
                self.deliver_note(path)
            except (OSError, smtplib.SMTPException, ValueError) as error:
                # SMTP errors may contain addresses or server responses. Log only the error type.
                LOG.warning("Email delivery pending for %s (%s)", path.parent.name, type(error).__name__)

    def deliver_note(self, path: Path):
        metadata = json.loads(path.read_text())
        if metadata.get("email") != "pending":
            return
        note_id = path.parent.name
        extension = metadata.get("extension")
        if metadata.get("id") != note_id or extension not in ("ogg", "wav"):
            raise ValueError("Invalid recording metadata")
        digest = metadata.get("sha256")
        key = (note_id, digest)
        if key not in self.accepted:
            with (path.parent / f"note.{extension}").open("rb") as recording:
                audio = recording.read(MAX_NOTE_BYTES + 1)
            if len(audio) > MAX_NOTE_BYTES or hashlib.sha256(audio).hexdigest() != digest:
                raise ValueError("Recording checksum mismatch")
            self.delivery.send(note_id, extension, digest, audio)
            self.accepted.add(key)
        with self.repository.lock:
            metadata["email"] = "sent"
            self.repository.save_metadata(path, metadata)
        self.accepted.discard(key)
        LOG.info("Recording email accepted: %s", note_id)

    def run(self, stop: threading.Event):
        while not stop.is_set():
            try:
                self.deliver_pending(stop)
            except OSError as error:
                LOG.warning("Cannot check email queue (%s)", type(error).__name__)
            stop.wait(30)


class Receiver(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, root: Path, token: str, archive: Path | None = None,
                 delivery: MailDelivery | None = None):
        self.repository = Repository(root, archive, email_enabled=delivery is not None)
        self.token = token
        self.email_stop = threading.Event()
        self.email_thread = None
        super().__init__(address, Handler)
        if delivery is not None:
            queue = EmailQueue(self.repository, delivery)
            self.email_thread = threading.Thread(target=queue.run, args=(self.email_stop,), daemon=True)
            self.email_thread.start()

    def server_close(self):
        self.email_stop.set()
        super().server_close()
        if self.email_thread is not None:
            self.email_thread.join()


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
    parser.add_argument("--archive", type=Path, help="Existing mounted share or folder for exported recordings")
    args = parser.parse_args()
    token = os.environ.get("VOICENOTES_TOKEN", "")
    if len(token) < 32 or not token.isascii():
        parser.error("Set VOICENOTES_TOKEN to a random ASCII token of at least 32 characters")
    try:
        delivery = MailDelivery.from_environment(os.environ)
    except ValueError as error:
        parser.error(str(error))
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    server = Receiver((args.host, args.port), args.data, token, args.archive, delivery)
    LOG.info("Voicenotes receiver listening on %s:%d", args.host, args.port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
