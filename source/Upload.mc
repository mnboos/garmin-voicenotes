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
    var failures = 0;
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
        for (var i = 0; i < store.items.size(); i++) {
            var item = store.items[i] as Lang.Dictionary;
            if (!item["uploaded"] && item["bytes"] > 0 && item["state"] != "recording") {
                start(item);
                return;
            }
        }
    }
    function start(note as Lang.Dictionary) {
        if (busy) {
            return;
        }
        baseUrl = Application.Properties.getValue("serverUrl");
        token = Application.Properties.getValue("serverToken");
        if (
            baseUrl == null ||
            baseUrl.length() < 9 ||
            !baseUrl.substring(0, 8).equals("https://") ||
            token == null ||
            token.length() == 0
        ) {
            message = "Set HTTPS server and token";
            nextAttempt = System.getTimer() + 60000;
            return;
        }
        if (baseUrl.substring(baseUrl.length() - 1, baseUrl.length()).equals("/")) {
            baseUrl = baseUrl.substring(0, baseUrl.length() - 1);
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
        var path = "/api/notes/" + current["id"];
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_PUT,
            :headers => {
                "Authorization" => "Bearer " + token,
                "Content-Type" => "application/octet-stream"
            },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        if (index < current["chunks"]) {
            var chunk = store.read(current, index);
            if (chunk == null) {
                failed("Missing audio chunk");
                return;
            }
            options[:body] = chunk;
            path += "/chunks/" + index;
        } else {
            options[:method] = Communications.HTTP_REQUEST_METHOD_POST;
            options[:headers]["Content-Type"] = "application/json";
            path += "/complete";
        }
        try {
            Communications.makeWebRequest(
                baseUrl + path,
                index == current["chunks"] ? current : null,
                options,
                method(:response)
            );
        } catch (e) {
            failed("Upload unavailable; queued");
        }
        WatchUi.requestUpdate();
    }
    function response(code as Lang.Number, data as Communications.ContentType?) as Void {
        if (!busy) {
            return;
        }
        if (code != 200 || !(data instanceof Lang.Dictionary) || data["ok"] != true) {
            failed("Queued; upload error " + code);
            return;
        }
        if (index == current["chunks"]) {
            current["uploaded"] = true;
            try {
                store.save();
            } catch (e) {
                current["uploaded"] = false;
                failed("Uploaded; local save failed");
                return;
            }
            busy = false;
            current = null;
            failures = 0;
            message = "Uploaded; kept on watch";
        } else {
            index++;
            send();
        }
        WatchUi.requestUpdate();
    }
    function failed(reason) {
        busy = false;
        current = null;
        failures++;
        var delay = failures * 30000;
        if (delay > 300000) {
            delay = 300000;
        }
        nextAttempt = System.getTimer() + delay;
        message = reason;
        WatchUi.requestUpdate();
    }
}
