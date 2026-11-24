import Toybox.Application;
import Toybox.Audio;
import Toybox.Lang;
import Toybox.Position;
import Toybox.System;
import Toybox.WatchUi;

class Recorder {
    const SAVE_LOCATION = "saveLocation";
    var store;
    var note as Lang.Dictionary or Null = null;
    var active = false;
    var finishing = false;
    private var locating = false;
    var started = 0;
    var lastData = 0;
    var message = "Ready to record";
    function initialize(notes) { store = notes; }
    function savesLocation() as Lang.Boolean {
        return Application.Storage.getValue(SAVE_LOCATION) == true;
    }
    function setSaveLocation(enabled as Lang.Boolean) as Void {
        Application.Storage.setValue(SAVE_LOCATION, enabled);
    }
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
        if (active) { startLocation(); }
        WatchUi.requestUpdate();
    }
    private function startLocation() as Void {
        try {
            if (savesLocation() && (Position has :enableLocationEvents)) {
                locating = true;
                Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
            }
        } catch (e) { stopLocation(); }
    }
    private function stopLocation() as Void {
        if (!locating) { return; }
        locating = false;
        try { Position.enableLocationEvents(Position.LOCATION_DISABLE, null); }
        catch (e) { /* Location failure should not interrupt audio capture. */ }
    }
    function onPosition(info as Position.Info) as Void {
        if (!locating || !active || finishing || note == null || info.accuracy < Position.QUALITY_USABLE) { return; }
        var fix = info.position;
        var when = info.when;
        if (fix == null || when == null || when.value() < note["created"]) { return; }
        note["location"] = fix.toDegrees();
        stopLocation();
    }
    function stop() {
        if (!active || finishing) { return; }
        finishing = true;
        stopLocation();
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
        stopLocation();
        if ("recording".equals(note["state"])) { note["state"] = "saved"; }
        note["seconds"] = (System.getTimer() - started) / 1000;
        if (note["bytes"] == 0) {
            note["state"] = "interrupted";
            message = "No audio received";
        } else if ("saved".equals(note["state"])) {
            message = "Saved on watch";
        }
        persistStatus();
        WatchUi.requestUpdate();
    }
    function onError(error as Audio.Capture.Error) as Void {
        active = false;
        finishing = false;
        stopLocation();
        markInterrupted();
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
