import hashlib
import http.client
import json
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch

from receiver import Receiver, Repository


class ReceiverTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.server = Receiver(("127.0.0.1", 0), self.root, "test-token")
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.audio = b"RIFF" + (44).to_bytes(4, "little") + b"WAVE" + bytes(range(40))

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.temp.cleanup()

    def request(self, method, path, body, token="test-token"):
        client = http.client.HTTPConnection(*self.server.server_address)
        client.request(method, path, body, {"Authorization": "Bearer " + token})
        response = client.getresponse()
        result = response.status, json.loads(response.read())
        client.close()
        return result

    def put(self, index, content):
        return self.request("PUT", f"/api/notes/watch-123/chunks/{index}", content)[0]

    def finish(self, **changes):
        meta = dict(id="watch-123", chunks=2, bytes=len(self.audio), extension="wav")
        meta.update(changes)
        return self.request("POST", "/api/notes/watch-123/complete", json.dumps(meta))[0]

    def test_retry_after_disconnect_preserves_exact_audio(self):
        self.assertEqual(self.put(0, self.audio[:20]), 200)
        self.assertEqual(self.finish(), 409)
        # A restarted watch sends the first chunk again.
        self.assertEqual(self.put(0, self.audio[:20]), 200)
        self.assertEqual(self.put(1, self.audio[20:]), 200)
        self.assertEqual(self.finish(), 200)
        self.assertEqual(self.finish(), 200)
        self.assertEqual((self.root / "watch-123/note.wav").read_bytes(), self.audio)
        meta = json.loads((self.root / "watch-123/metadata.json").read_text())
        self.assertEqual(meta["sha256"], hashlib.sha256(self.audio).hexdigest())
        self.assertNotIn("location", meta)

    def test_saves_optional_location_with_note(self):
        self.put(0, self.audio[:20])
        self.put(1, self.audio[20:])
        self.assertEqual(self.finish(location=[91, 8.55]), 400)
        location = [47.37, 8.55]
        self.assertEqual(self.finish(location=location), 200)
        self.assertEqual(self.finish(location=location), 200)
        meta = json.loads((self.root / "watch-123/metadata.json").read_text())
        self.assertEqual(meta["location"], location)

    def test_rejects_conflicting_retry(self):
        self.assertEqual(self.put(0, self.audio), 200)
        self.assertEqual(self.put(0, b"different"), 409)

    def test_receiver_restart_retains_acknowledged_chunks(self):
        self.put(0, self.audio[:20])
        self.server.repository = Repository(self.root)
        self.assertEqual(self.put(1, self.audio[20:]), 200)
        self.assertEqual(self.finish(), 200)
        self.server.repository = Repository(self.root)
        self.assertEqual(self.put(0, self.audio[:20]), 200)
        self.assertEqual(self.finish(), 200)

    def test_auth_and_path_validation(self):
        self.assertEqual(self.request("PUT", "/api/notes/x/chunks/0", b"x", token="wrong")[0], 401)
        self.assertEqual(self.request("PUT", "/api/notes/../chunks/0", b"x")[0], 404)

    def test_rejects_oversize_and_bad_metadata(self):
        self.assertEqual(self.put(0, b"x" * 4097), 400)
        self.assertEqual(self.finish(chunks=-1), 400)
        self.assertEqual(self.finish(extension="exe"), 400)

    def test_never_finalizes_wrong_size_or_container(self):
        self.put(0, b"invalid")
        self.put(1, b"audio")
        self.assertEqual(self.finish(bytes=12), 422)
        self.assertEqual(self.finish(bytes=999), 409)
        self.assertFalse((self.root / "watch-123/metadata.json").exists())

    def test_finalization_respects_disk_quota_and_can_retry(self):
        self.assertEqual(self.put(0, self.audio[:20]), 200)
        self.assertEqual(self.put(1, self.audio[20:]), 200)
        with patch("receiver.MAX_DISK_BYTES", 2 * len(self.audio)):
            self.assertEqual(self.finish(), 507)
        folder = self.root / "watch-123"
        self.assertFalse((folder / "note.wav").exists())
        self.assertFalse((folder / "metadata.json").exists())
        self.assertEqual(self.finish(), 200)


if __name__ == "__main__":
    unittest.main()
