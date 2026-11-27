import Toybox.Application;
import Toybox.Attention;
import Toybox.Audio;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

class Recorder {
    const FEEDBACK_SETTLE_MS = 350;
    var store as Notes;
    var note as Lang.Dictionary? = null;
    var active = false;
    var startTimer as Timer.Timer? = null;
    var awaitingDecision = false;
    var closing = false;
    var lastEndFeedback = null;
    var partial = false;
    var finishing = false;
    var started = 0;
    var lastData = 0;
    var message = "Ready to record";
    var limit = 0; // 0 = no limit
    var warnAt = -1; // -1 = none
    var warned = false;
    function initialize(notes as Notes) {
        store = notes;
        for (var i = 0; i < store.items.size(); i++) {
            var draft = store.items[i];
            if ("draft".equals(draft.get("state"))) {
                note = draft;
                awaitingDecision = true;
                message = "Keep this recording?";
                break;
            }
        }
    }
    function start() {
        if (active || startTimer != null || awaitingDecision) {
            return;
        }
        var delay = 0;
        if (feedback("vibrateOnRecord", "soundOnStart", 1800)) {
            delay = FEEDBACK_SETTLE_MS;
        } else if (lastEndFeedback != null) {
            delay = FEEDBACK_SETTLE_MS - (System.getTimer() - lastEndFeedback);
        }
        if (delay > 0) {
            message = "Starting...";
            startTimer = new Timer.Timer();
            startTimer.start(method(:beginCapture), delay, false);
            WatchUi.requestUpdate();
            return;
        }
        beginCapture();
    }
    function beginCapture() as Void {
        startTimer = null;
        lastEndFeedback = null;
        note = null;
        partial = false;
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
                WatchUi.requestUpdate();
                return;
            }
            Audio.Capture.initializeAudioCapture(self, {
                :format => format,
                :windowSize => 4096,
                :windowFilledBehavior => Audio.Capture.WINDOW_FILLED_CONTINUE
            });
            var state =
                Application.Properties.getValue("autoSave") == false ? "draft" : "recording";
            note = store.create(format, ext, state);
            readLimit();
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
    function shutdown() {
        closing = true;
        stop();
    }
    function stop() {
        if (startTimer != null) {
            startTimer.stop();
            startTimer = null;
            message = "Ready to record";
            WatchUi.requestUpdate();
            return;
        }
        if (!active || finishing) {
            return;
        }
        finishing = true;
        note["seconds"] = (System.getTimer() - started) / 1000;
        message = "Stopping...";
        WatchUi.requestUpdate();
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
        if (finishing) {
            if (System.getTimer() - lastData > 15000) {
                onError(Audio.Capture.CAPTURE_ERR_INTERNAL);
            }
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
        if (limit > 0 && warned) {
            message = "Ends in " + (limit - note["seconds"]) + " s";
        }
        if (limit > 0 && note["seconds"] >= limit) {
            stop();
            return;
        }
        if (System.getTimer() - lastData > 15000) {
            partial = true;
            stop();
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
            partial = true;
            stop();
        }
        WatchUi.requestUpdate();
    }
    function onComplete() as Void {
        if (!active) {
            return;
        }
        finishCapture();
    }
    function onError(error as Audio.Capture.Error) as Void {
        if (active) {
            partial = true;
            finishCapture();
            message = "Capture error " + error;
            WatchUi.requestUpdate();
        }
    }
    function finishCapture() {
        if (!finishing) {
            note["seconds"] = (System.getTimer() - started) / 1000;
        }
        active = false;
        finishing = false;
        message =
            note["bytes"] == 0
                ? "No audio received"
                : partial
                  ? "Partial note saved"
                  : "Saved on watch";
        if ("draft".equals(note["state"])) {
            awaitingDecision = true;
            message = "Keep this recording?";
            if (note["bytes"] == 0) {
                resolveDraft(false);
            }
        } else {
            note["state"] = partial || note["bytes"] == 0 ? "interrupted" : "saved";
        }
        persistStatus();
        if (!closing && feedback("vibrateOnStop", "soundOnStop", 1000)) {
            lastEndFeedback = System.getTimer();
        }
        WatchUi.requestUpdate();
    }
    function resolveDraft(keep) {
        if (!awaitingDecision) {
            return;
        }
        try {
            if (keep && note["bytes"] > 0) {
                note["state"] = partial ? "interrupted" : "saved";
                store.save();
                message = partial ? "Partial note saved" : "Saved on watch";
            } else {
                store.remove(note);
                message = note["bytes"] == 0 ? "No audio received" : "Deleted";
            }
            awaitingDecision = false;
            note = null;
        } catch (e) {
            note["state"] = "draft";
            message = keep ? "Save failed. Try again." : "Delete failed. Try again.";
        }
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
    function feedback(vibrationKey, soundKey, pitch) as Lang.Boolean {
        var played = false;
        if (Attention has :vibrate && Application.Properties.getValue(vibrationKey) == true) {
            pulse([new Attention.VibeProfile(60, 200)]);
            played = true;
        }
        if (
            Attention has :playTone &&
            Attention has :ToneProfile &&
            Application.Properties.getValue(soundKey) == true
        ) {
            try {
                Attention.playTone({ :toneProfile => [new Attention.ToneProfile(pitch, 150)] });
                played = true;
            } catch (e) {}
        }
        return played;
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
        if (note != null && "draft".equals(note["state"])) {
            awaitingDecision = true;
            resolveDraft(false);
        } else if (note != null) {
            note["state"] = "interrupted";
            persistStatus();
        }
    }
}
