import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class Upload {
    var store as Notes;
    var current as Lang.Dictionary? = null;
    var index = 0;
    var busy = false;
    var nextAttempt = 0;
    var message = "";
    var baseUrl;
    var token;
    function initialize(notes) {
        store = notes;
    }
    function tick() {
        if (
            busy ||
            System.getTimer() < nextAttempt ||
            !Application.Properties.getValue("autoUpload")
        ) {
            return;
        }
        var note = UploadRequest.nextNote(store.items, false);
        if (note != null) {
            start(note);
        }
    }
    function start(note as Lang.Dictionary) {
        if (busy) {
            return;
        }
        token = Application.Properties.getValue("serverToken");
        baseUrl = UploadRequest.endpoint(Application.Properties.getValue("serverUrl"), token);
        if (baseUrl == null) {
            message = "Set HTTPS server and token";
            nextAttempt = System.getTimer() + 60000;
            return;
        }
        if (note["bytes"] == 0) {
            message = "No audio to upload";
            return;
        }
        current = note;
        index = 0;
        busy = true;
        send();
    }
    function send() {
        message = "Uploading " + index + "/" + current["chunks"];
        try {
            if (!UploadRequest.send(baseUrl, token, current, index, method(:response))) {
                failed("Missing audio chunk", true);
                return;
            }
        } catch (e) {
            failed("Upload unavailable; queued", false);
            return;
        }
        WatchUi.requestUpdate();
    }
    function response(code as Lang.Number, data as Communications.ContentType?) as Void {
        if (!busy) {
            return;
        }
        if (!UploadRequest.acknowledged(code, data)) {
            failed("Upload error " + code, UploadRequest.rejected(code));
            return;
        }
        if (index == current["chunks"]) {
            current["uploaded"] = true;
            try {
                store.save();
            } catch (e) {
                current["uploaded"] = false;
                failed("Uploaded; local save failed", false);
                return;
            }
            busy = false;
            current = null;
            message = "Uploaded; kept on watch";
        } else {
            index++;
            send();
        }
        WatchUi.requestUpdate();
    }
    function failed(reason, permanent) {
        try {
            UploadRequest.defer(current, permanent);
        } catch (e) {
            nextAttempt = System.getTimer() + 30000;
        }
        busy = false;
        current = null;
        message = reason;
        WatchUi.requestUpdate();
    }
}
