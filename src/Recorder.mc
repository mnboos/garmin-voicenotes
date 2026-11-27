import Toybox.Application;
import Toybox.Attention;
import Toybox.Audio;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class Recorder {
    var store;
    var note as Lang.Dictionary? = null;
    var active = false;
    var finishing = false;
    var started = 0;
    var lastData = 0;
    var message = "Ready to record";
    var limit = 0; // 0 = no limit
    var warnAt = -1; // -1 = none
    var warned = false;
    function initialize(notes) {
        store = notes;
    }
    function start() {
        if (active || finishing) {
            return;
        }
        note = null;
        try {
            var format = {
                :containerFormat => Audio.CONTAINER_OGG,
                :codec => Audio.CODEC_OPUS,
                :frequency => Audio.FREQ_16_KHZ,
                :channels => Audio.CHANNEL_MONO
            };
            var ext = "ogg";
            if (!Audio.Capture.isFormatSupported(format)) {
                format = {
                    :containerFormat => Audio.CONTAINER_WAV,
                    :codec => Audio.CODEC_LPCM,
                    :frequency => Audio.FREQ_8_KHZ,
                    :channels => Audio.CHANNEL_MONO
                };
                ext = "wav";
            }
            if (!Audio.Capture.isFormatSupported(format)) {
                message = "Microphone unavailable";
                return;
            }
            Audio.Capture.initializeAudioCapture(self, {
                :format => format,
                :windowSize => 4096,
                :windowFilledBehavior => Audio.Capture.WINDOW_FILLED_CONTINUE
            });
            note = store.create(format, ext);
            readLimit();
            started = System.getTimer();
            lastData = started;
            active = true;
            message = "Recording";
            Audio.Capture.start();
            vibrate();
        } catch (e) {
            active = false;
            finishing = false;
            message = "Cannot record / storage full";
            markInterrupted();
        }
        WatchUi.requestUpdate();
    }
    function stop() {
        if (!active || finishing) {
            return;
        }
        finishing = true;
        message = "Saving...";
        try {
            Audio.Capture.stop();
        } catch (e) {
            onError(Audio.Capture.CAPTURE_ERR_INTERNAL);
        }
    }
    function tick() {
        if (!active) {
            return;
        }
        note["seconds"] = (System.getTimer() - started) / 1000;
        if (!warned && warnAt >= 0 && note["seconds"] >= warnAt) {
            warned = true;
            pulse([
                new Attention.VibeProfile(100, 150),
                new Attention.VibeProfile(0, 150),
                new Attention.VibeProfile(100, 150)
            ]);
        }
        if (limit > 0 && warned && !finishing) {
            message = "Ends in " + (limit - note["seconds"]) + " s";
        }
        if (limit > 0 && note["seconds"] >= limit) {
            stop();
            message = "Time limit; saving...";
            return;
        }
        if (System.getTimer() - lastData > 15000) {
            stop();
            if (active) {
                onError(Audio.Capture.CAPTURE_ERR_INTERNAL);
            }
            message = "Capture stalled; check note";
        }
    }
    function onData(data as Lang.ByteArray) as Void {
        if (!active || note == null || data.size() == 0) {
            return;
        }
        lastData = System.getTimer();
        try {
            store.append(note, data);
        } catch (e) {
            note["state"] = "interrupted";
            stop();
            message = "Storage full; partial note";
        }
        WatchUi.requestUpdate();
    }
    function onComplete() as Void {
        if (!active) {
            return;
        }
        active = false;
        finishing = false;
        if ("recording".equals(note["state"])) {
            note["state"] = "saved";
        }
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
        markInterrupted();
        message = "Capture error " + error;
        WatchUi.requestUpdate();
    }
    function readLimit() {
        var value = Application.Properties.getValue("maxSeconds");
        limit = value instanceof Lang.Number && value > 0 ? value : 0;
        warned = false;
        warnAt = -1;
        if (limit > 0 && Application.Properties.getValue("warnBeforeEnd") != false) {
            var lead = limit / 3 < 10 ? limit / 3 : 10;
            if (lead > 0) {
                warnAt = limit - lead;
            }
        }
    }
    function vibrate() {
        if (Application.Properties.getValue("vibrateOnRecord") != true) {
            return;
        }
        pulse([new Attention.VibeProfile(60, 200)]);
    }
    function pulse(profile as Lang.Array<Attention.VibeProfile>) {
        if (Attention has :vibrate) {
            try {
                Attention.vibrate(profile);
            } catch (e) {}
        }
    }
    function persistStatus() {
        try {
            store.save();
        } catch (e) {
            message = "Audio kept; status save failed";
        }
    }
    function markInterrupted() {
        if (note != null) {
            note["state"] = "interrupted";
            persistStatus();
        }
    }
}
