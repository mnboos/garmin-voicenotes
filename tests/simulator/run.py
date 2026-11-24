#!/usr/bin/env python3
"""Exercise the Venu 4 simulator and Garmin's tethered SDK on an Android AVD."""
import argparse
import contextlib
import hashlib
import os
from pathlib import Path
import re
import select
import signal
import shutil
import socket
import subprocess
import sys
import threading
import time
import uuid
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = "ch.voicenotes.inbox.e2e"
ACTIVITY = PACKAGE + "/ch.voicenotes.inbox.InboxActivity"
BACKGROUND_WINDOW_SECONDS = 25
SIZE = 32044
SHA256 = "953ea453dce7245c7e2153012000d3bf686cee2b75cc6d30f60da90812b64022"


def run(*args, check=True, env=None):
    result = subprocess.run(args, cwd=ROOT, env=env, capture_output=True, timeout=90)
    if check and result.returncode:
        raise RuntimeError(f"{args[0]} failed: {result.stderr.decode(errors='replace') or result.stdout.decode(errors='replace')}")
    return result


def wait_for(label, probe, seconds=35):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = probe()
        if value:
            return value
        time.sleep(0.2)
    raise RuntimeError(f"Timed out waiting for {label}")


class Tether:
    """Relay the vendor's bytes unchanged. Drop only the Android socket on demand."""

    def __init__(self, port):
        self.port = port
        self.closed = threading.Event()
        self.pause_phone = threading.Event()
        self.disconnect_watch = threading.Event()
        self.dropped = threading.Event()
        self.connected = threading.Event()

    def __enter__(self):
        self.listener = socket.socket()
        try:
            self.listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.listener.bind(("127.0.0.1", 7381))
            self.listener.listen(1)
            self.listener.settimeout(0.25)
        except BaseException:
            self.listener.close()
            raise
        self.thread = threading.Thread(target=self.serve, daemon=True)
        self.thread.start()
        return self

    def __exit__(self, *_):
        self.closed.set()
        self.thread.join(3)
        self.listener.close()

    def serve(self):
        while not self.closed.is_set():
            try:
                watch, _ = self.listener.accept()
            except TimeoutError:
                continue
            with watch:
                watch.settimeout(0.3)
                self.connected.set()
                try:
                    self.relay(watch)
                except (ConnectionError, TimeoutError):
                    pass
                finally:
                    self.connected.clear()

    def relay(self, watch):
        phone = None
        try:
            while not self.closed.is_set() and not self.disconnect_watch.is_set():
                if self.pause_phone.is_set():
                    if phone is not None:
                        phone.close()
                        phone = None
                    self.dropped.set()
                elif phone is None:
                    try:
                        phone = socket.create_connection(("127.0.0.1", self.port), timeout=0.3)
                    except OSError:
                        time.sleep(0.2)
                        continue
                    self.dropped.clear()
                peers = [watch] if phone is None else [watch, phone]
                readable, _, _ = select.select(peers, [], [], 0.1)
                for source in readable:
                    payload = source.recv(16384)
                    if source is watch:
                        if not payload:
                            return
                        if phone is not None:
                            phone.sendall(payload)
                    elif payload:
                        watch.sendall(payload)
                    else:
                        phone.close()
                        phone = None
        finally:
            if phone is not None:
                phone.close()


class Suite:
    def __init__(self, adb, serial, sdk, output):
        self.adb = (adb, "-s", serial)
        self.sdk = sdk
        self.output = output
        self.watch_log = output / "watch.log"
        self.launches = []

    def phone(self, *args, check=True):
        return run(*self.adb, *args, check=check)

    def phone_log(self):
        result = self.phone("logcat", "-d", "--pid=" + self.pid, "-s", "Voicenotes", "ConnectIQ-AdbConnection", "AndroidRuntime")
        log = result.stdout.decode(errors="replace")
        (self.output / "android.log").write_text(log)
        if "FATAL EXCEPTION" in log:
            raise RuntimeError("Android inbox crashed")
        return log

    def start_phone(self):
        self.phone("install", "-r", ROOT / "bin/android/Voicenotes-test.apk")
        if self.phone("shell", "pm", "clear", PACKAGE).stdout.strip() != b"Success":
            raise RuntimeError("Android could not clear the isolated test inbox")
        self.open_phone()

    def open_phone(self):
        launch = self.phone("shell", "am", "start", "-W", "-n", ACTIVITY)
        if b"Status: ok" not in launch.stdout:
            raise RuntimeError(launch.stdout.decode(errors="replace"))
        self.pid = wait_for("the test inbox process", lambda: self.phone(
            "shell", "pidof", PACKAGE, check=False).stdout.decode().strip())

    def build_watch(self):
        ET.register_namespace("iq", "http://www.garmin.com/xml/connectiq")
        manifest = ET.parse(ROOT / "manifest.xml")
        app = manifest.find("{*}application")
        app.set("id", "289786c524644eb48eb8f0554da01d7e")
        products = app.find("{*}products")
        for product in list(products):
            if product.get("id") != "venu445mm":
                products.remove(product)
        manifest.write(self.output / "manifest.xml", encoding="utf-8")
        resources = self.output / "resources"
        shutil.copytree(ROOT / "resources", resources)
        strings = resources / "strings/strings.xml"
        tree = ET.parse(strings)
        tree.find("string[@id='Voicenotes']").text = "VNE2E"
        tree.write(strings, encoding="utf-8")
        (self.output / "RunId.mc").write_text('const TEST_RUN = "' + uuid.uuid4().hex + '";\n')
        jungle = self.output / "test.jungle"
        jungle.write_text(
            "project.manifest = manifest.xml\n"
            f"base.sourcePath = {ROOT / 'src'};{ROOT / 'simulator'};{Path(__file__).resolve().parent};RunId.mc\n"
            "base.resourcePath = resources\n"
            f"venu445mm.resourcePath = $(base.resourcePath);{ROOT / 'launcher-icons/65'};{ROOT / 'resources-venu445mm'}\n"
        )
        key = self.output.parent / "test-key.der"
        if not key.exists():
            run("openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:4096",
                "-out", self.output / "test-key.pem")
            run("openssl", "pkcs8", "-topk8", "-nocrypt", "-outform", "DER",
                "-in", self.output / "test-key.pem", "-out", key)
            (self.output / "test-key.pem").unlink()
        self.artifact = self.output / "VNE2E.prg"
        result = run(self.sdk / "bin/monkeyc",
                     "-f", jungle,
                     "-o", self.artifact, "-y", key, "-w", "-r", "-d", "venu445mm")
        (self.output / "build.log").write_bytes(result.stdout + result.stderr)

    def launch_watch(self):
        with self.watch_log.open("ab") as log:
            launch = subprocess.Popen([self.sdk / "bin/monkeydo", self.artifact, "venu445mm"],
                                      cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                                      start_new_session=True)
        self.launches.append(launch)
        return launch

    def stop_launchers(self):
        for launch in self.launches:
            if launch.poll() is None:
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(launch.pid, signal.SIGTERM)
                launch.wait(timeout=5)
        self.launches.clear()

    def open_watch(self, phase):
        offset = len(self.watch_log.read_text(errors="replace")) if self.watch_log.exists() else 0
        attempts = 5 if phase == 3 else 3
        for attempt in range(attempts):
            self.launch_watch()
            try:
                return self.watch_ready(phase, offset, seconds=9)
            except RuntimeError:
                self.stop_launchers()
                if attempt == attempts - 1:
                    raise
                if phase == 3 and attempt == 0:
                    print("If the watch stays on the Garmin logo, quit and reopen the simulator. "
                          "The queued test note is preserved.", flush=True)
                print("Retrying after Garmin's app launcher stalled.", flush=True)
                time.sleep(2)

    def watch_event(self, pattern, start=0):
        return re.search("VN-E2E " + pattern, self.watch_log.read_text(errors="replace")[start:])

    def watch_ready(self, phase, start=0, seconds=25):
        return wait_for(f"watch phase {phase}", lambda: self.watch_event(
            rf"ready {phase} ([a-f0-9-]+)", start), seconds).group(1)

    def files(self):
        result = self.phone("shell", "run-as", PACKAGE, "ls", "files/inbox", check=False)
        return set(result.stdout.decode().split()) if result.returncode == 0 else set()

    def audio(self, note, partial=False):
        suffix = ".wav.part" if partial else ".wav"
        result = self.phone("shell", "-T", "run-as", PACKAGE, "cat", "files/inbox/" + note + suffix, check=False)
        return result.stdout if result.returncode == 0 else b""

    def verify_note(self, phase, note):
        def saved_and_played():
            log = self.phone_log()
            return ("Watch confirmed saved note " + note in log
                    and "Playback completed " + note + ".wav" in log)

        wait_for(f"Android save and playback for note {phase}", saved_and_played, 55)
        wait_for(f"watch receipt {phase}", lambda: self.watch_event(rf"receipt {phase} {note}"))
        audio = self.audio(note)
        if len(audio) != SIZE or hashlib.sha256(audio).hexdigest() != SHA256:
            raise RuntimeError(f"Note {note} differs from the fixture")
        if note + ".wav.part" in self.files():
            raise RuntimeError(f"Partial file still exists for {note}")
        (self.output / f"note-{phase}.wav").write_bytes(audio)

    def exercise(self, tether, require_background):
        first = self.open_watch(1)
        print("In Garmin Simulator, choose adb Connection → Start.", flush=True)
        wait_for("Garmin tether (adb Connection → Start)", tether.connected.is_set, 90)
        wait_for("Garmin ping/pong", lambda: "Garmin ping/pong verified" in self.phone_log())
        self.verify_note(1, first)
        print("PASS 1/3 · WAV saved, played automatically, and acknowledged", flush=True)

        second = wait_for("second watch fixture", lambda: self.watch_event(r"queued 2 ([a-f0-9-]+)")).group(1)
        wait_for("mid-transfer checkpoint", lambda: len(self.audio(second, partial=True)) >= SIZE // 2, 30)
        disconnects = self.phone_log().count("End of input reached")
        tether.pause_phone.set()
        wait_for("relay to drop Android's socket", tether.dropped.is_set, 5)
        wait_for("Android to detect the closed socket", lambda:
                 self.phone_log().count("End of input reached") > disconnects)
        saved = self.audio(second, partial=True)
        if not 0 < len(saved) < SIZE or self.audio(second):
            raise RuntimeError("Fault injection did not stop an incomplete transfer")
        if self.watch_event(rf"receipt 2 {second}"):
            raise RuntimeError("Watch acknowledged the incomplete transfer")
        if self.audio(first) != (self.output / "note-1.wav").read_bytes():
            raise RuntimeError("First inbox note changed during the interruption")
        (self.output / "android-before-restart.log").write_text(self.phone_log())
        self.phone("shell", "am", "force-stop", PACKAGE)
        self.open_phone()
        if self.audio(second, partial=True) != saved:
            raise RuntimeError("The committed partial bytes changed across Android restart")
        tether.pause_phone.clear()
        wait_for("Android to offer the interrupted note at the saved offset", lambda:
                 f"Offered {second} at {len(saved)}/{SIZE}" in self.phone_log(), 35)
        self.verify_note(2, second)
        if self.files() != {first + ".wav", second + ".wav"}:
            raise RuntimeError("Unexpected inbox files after reconnect")
        print(f"PASS 2/3 · resumed after Android restart at {len(saved)}/{SIZE} bytes with exactly one copy", flush=True)

        third = wait_for("watch to exit with a queued note", lambda:
                         self.watch_event(r"exiting ([a-f0-9-]+)")).group(1)
        wait_for("watch app shutdown", lambda: self.watch_event(rf"stopped 3 {third}"))
        if not tether.connected.is_set():
            print("Choose adb Connection → Start with the watch app exited.", flush=True)
            wait_for("Garmin tether with the watch app exited", tether.connected.is_set, 90)
        attempts = self.phone_log().count("Wrote ")
        wait_for("Android to request sync while the watch app is exited", lambda:
                 self.phone_log().count("Wrote ") > attempts or self.audio(third))
        deadline = time.monotonic() + BACKGROUND_WINDOW_SECONDS
        while time.monotonic() < deadline and not self.audio(third):
            time.sleep(0.5)
        if not tether.connected.is_set() and not self.audio(third):
            raise RuntimeError("Tether closed during the background observation")
        background = bool(self.audio(third))
        (self.output / "background.txt").write_text(("delivered" if background else "no delivery") + "\n")
        # Garmin may keep the idle app's tether route after System.exit.
        # Close it before monkeydo loads the app again.
        tether.disconnect_watch.set()
        wait_for("the Garmin tether to close", lambda: not tether.connected.is_set())
        self.stop_launchers()
        if third != self.open_watch(3):
            raise RuntimeError("Queued note ID changed after reopening the watch app")
        tether.disconnect_watch.clear()
        print("Choose adb Connection → Start for the reopened watch app.", flush=True)
        wait_for("Garmin tether after reopening", tether.connected.is_set, 90)
        self.verify_note(3, third)
        if self.files() != {note + ".wav" for note in (first, second, third)}:
            raise RuntimeError("Unexpected inbox files after the app-exit test")
        if require_background and not background:
            raise RuntimeError("Garmin did not deliver the queued note while the watch app was exited")
        status = "background delivery" if background else "no background delivery, then verified foreground recovery"
        print(f"PASS 3/3 · {status}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", default=os.environ.get("ANDROID_SERIAL"))
    parser.add_argument("--require-background", action="store_true")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("this simulator suite is configured for macOS")
    companion = Path(os.environ.get("VOICENOTES_COMPANION_DIR")
                     or Path.home() / "src/garmin-voicenotes-companion").expanduser().resolve()
    companion_build = companion / "build-debug.sh"
    if not companion_build.is_file():
        parser.error(f"Android companion build script missing at {companion_build}. Set VOICENOTES_COMPANION_DIR.")
    android = Path(os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
                   or Path.home() / "Library/Android/sdk")
    adb = android / "platform-tools/adb"
    devices = run(adb, "devices").stdout.decode().splitlines()
    online = [line.split()[0] for line in devices if re.fullmatch(r"emulator-\d+\s+device", line)]
    if not args.serial and len(online) == 1:
        args.serial = online[0]
    if args.serial not in online:
        parser.error("boot an Android AVD and select it with --serial if more than one is running")

    if not run("lsof", "-nP", "-iTCP:1234", "-sTCP:LISTEN", check=False).stdout:
        parser.error("start the Garmin simulator with just garmin-simulator")
    with socket.socket() as probe:
        probe.settimeout(0.3)
        if probe.connect_ex(("127.0.0.1", 8787)) == 0:
            parser.error("stop the local Voicenotes receiver on port 8787 before running the test")

    output = ROOT / ".tools/simulator-tests" / (time.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:6])
    output.mkdir(parents=True)
    print(f"Test artifacts: {output}", flush=True)
    sdk = Path(run("bash", "build.sh", "--sdk").stdout.decode().strip())
    suite = Suite(adb, args.serial, sdk, output)
    existing_forward = f"{args.serial} tcp:7381 tcp:7381"
    forwards = suite.phone("forward", "--list").stdout.decode().splitlines()
    replace_forward = existing_forward in forwards
    with contextlib.ExitStack() as stack:
        if replace_forward:
            suite.phone("forward", "--remove", "tcp:7381")
            stack.callback(suite.phone, "forward", "--no-rebind", "tcp:7381", "tcp:7381", check=False)
        port = int(suite.phone("forward", "tcp:0", "tcp:17381").stdout)
        stack.callback(suite.phone, "forward", "--remove", f"tcp:{port}", check=False)
        tether = stack.enter_context(Tether(port))
        try:
            suite.build_watch()
            build_env = dict(os.environ, VOICENOTES_ANDROID_OUTPUT_DIR=str(ROOT / "bin/android"))
            built = run("bash", companion_build, "--simulator-test", env=build_env)
            (output / "android-build.log").write_bytes(built.stdout + built.stderr)
            suite.start_phone()
            stack.callback(suite.phone, "shell", "am", "force-stop", PACKAGE, check=False)
            suite.exercise(tether, args.require_background)
        finally:
            if hasattr(suite, "pid"):
                with contextlib.suppress(RuntimeError, subprocess.SubprocessError):
                    suite.phone_log()
            suite.stop_launchers()


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        sys.exit(f"Simulator test failed: {error}")
