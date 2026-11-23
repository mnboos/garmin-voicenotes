import Toybox.Audio;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class Recorder {
    var store;
    var note as Lang.Dictionary or Null = null;
    var active = false;
    var finishing = false;
    var started = 0;
    var lastData = 0;
    var message = "Ready to record";
    function initialize(notes) { store = notes; }
    function start() {
        if (active || finishing) { return; }
        note = null;
        try {
            var format = {:containerFormat=>Audio.CONTAINER_OGG, :codec=>Audio.CODEC_OPUS,
                :frequency=>Audio.FREQ_16_KHZ, :channels=>Audio.CHANNEL_MONO};
            var ext = "ogg";
            if (!Audio.Capture.isFormatSupported(format)) {
                format = {:containerFormat=>Audio.CONTAINER_WAV, :codec=>Audio.CODEC_LPCM,
                    :frequency=>Audio.FREQ_8_KHZ, :channels=>Audio.CHANNEL_MONO};
                ext = "wav";
            }
            if (!Audio.Capture.isFormatSupported(format)) {
                message = "Microphone unavailable";
                return;
            }
            Audio.Capture.initializeAudioCapture(self, {:format=>format, :windowSize=>4096,
                :windowFilledBehavior=>Audio.Capture.WINDOW_FILLED_CONTINUE});
            note = store.create(format, ext);
            started = System.getTimer();
            lastData = started;
            active = true;
            message = "Recording";
            Audio.Capture.start();
        } catch (e) {
            active = false;
            finishing = false;
            message = "Cannot record / storage full";
            markInterrupted();
        }
        WatchUi.requestUpdate();
    }
    function stop() {
        if (!active || finishing) { return; }
        finishing = true;
        message = "Saving...";
        try { Audio.Capture.stop(); } catch (e) { onError(Audio.Capture.CAPTURE_ERR_INTERNAL); }
    }
    function tick() {
        if (!active) { return; }
        note["seconds"] = (System.getTimer() - started) / 1000;
        if (note["seconds"] >= 60) { stop(); }
        // Do not leave a stalled firmware capture looking like a working recorder.
        if (System.getTimer() - lastData > 15000) {
            stop();
            if (active) { onError(Audio.Capture.CAPTURE_ERR_INTERNAL); }
            message = "Capture stalled; check note";
        }
    }
    function onData(data as Lang.ByteArray) as Void {
        if (!active || note == null || data.size() == 0) { return; }
        lastData = System.getTimer();
        try {
            if (!store.append(note, data)) {
                note["state"] = "interrupted";
                stop();
                message = "Storage full; partial note";
            }
        } catch (e) {
            note["state"] = "interrupted";
            stop();
            message = "Save failed; partial note";
        }
        WatchUi.requestUpdate();
    }
    function onComplete() as Void {
        if (!active) { return; }
        active = false;
        finishing = false;
        if (note["state"] == "recording") { note["state"] = "saved"; }
        note["seconds"] = (System.getTimer() - started) / 1000;
        message = note["bytes"] > 0 ? "Saved on watch" : "No audio received";
        if (note["bytes"] == 0) { note["state"] = "interrupted"; }
        persistStatus();
        WatchUi.requestUpdate();
    }
    function onError(error as Audio.Capture.Error) as Void {
        active = false;
        finishing = false;
        if (note != null) { note["state"] = "interrupted"; persistStatus(); }
        message = "Capture error " + error;
        WatchUi.requestUpdate();
    }
    function persistStatus() {
        try { store.save(); }
        catch (e) { message = "Audio kept; status save failed"; }
    }
    function markInterrupted() {
        if (note != null) { note["state"] = "interrupted"; persistStatus(); }
    }
}
