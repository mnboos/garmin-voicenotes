import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;

(:background)
module SyncTargets {
    const COUNT = 3;
    const LEGACY_URL = "sync:legacyUrl";

    function get(slot as Lang.Number) as Lang.Array<Lang.String>? {
        var suffix = slot == 0 ? "" : (slot + 1).toString();
        var url = Application.Properties.getValue("serverUrl" + suffix);
        var token = Application.Properties.getValue("serverToken" + suffix);
        if (
            !(url instanceof Lang.String) ||
            url.length() < 9 ||
            !url.substring(0, 8).equals("https://") ||
            url.find("?") != null ||
            url.find("#") != null ||
            url.find("@") != null ||
            url.find(" ") != null ||
            url.substring(8, 9).equals("/") ||
            !(token instanceof Lang.String) ||
            token.length() == 0
        ) {
            return null;
        }
        while (url.length() > 8 && url.substring(url.length() - 1, url.length()).equals("/")) {
            url = url.substring(0, url.length() - 1);
        }
        return url.length() > 8 ? [url, token] : null;
    }

    function bindLegacy() {
        if (Application.Storage.getValue(LEGACY_URL) == null) {
            var primary = get(0) as Lang.Array<Lang.String>?;
            Application.Storage.setValue(LEGACY_URL, primary == null ? "" : primary[0]);
        }
    }

    function key(note as Lang.Dictionary) as Lang.String {
        return "sync:" + note["id"];
    }

    function read(note as Lang.Dictionary) as Lang.Dictionary {
        var state = Application.Storage.getValue(key(note));
        return state == null ? {} : state as Lang.Dictionary;
    }

    // Store the URL, next chunk (-1 means complete), manual queue flag, and resync revision.
    function progress(
        note as Lang.Dictionary,
        state as Lang.Dictionary,
        slot as Lang.Number,
        url as Lang.String
    ) as Lang.Array {
        var entry = state[slot] as Lang.Array?;
        if (entry != null && entry[0].equals(url)) {
            return entry;
        }
        if (entry == null && slot == 0 && url.equals(Application.Storage.getValue(LEGACY_URL))) {
            if (
                note["uploaded"] == true ||
                Application.Storage.getValue("sent:" + note["id"]) == true
            ) {
                return [url, -1, false, 0];
            }
            var cursor = Application.Storage.getValue("upload:" + note["id"]);
            if (cursor != null && cursor >= 0 && cursor <= note["chunks"]) {
                return [url, cursor, false, 0];
            }
        }
        return [url, 0, false, 0];
    }
}

(:background)
class SyncTransfer {
    var note as Lang.Dictionary;
    var slot as Lang.Number;
    var target as Lang.Array<Lang.String>;
    var cursor;
    var manual;
    var revision;
    var deadline;
    var finished;

    function initialize(
        selected as Lang.Dictionary,
        destination as Lang.Number,
        settings as Lang.Array<Lang.String>,
        progress as Lang.Array,
        stopAt,
        callback
    ) {
        note = selected;
        slot = destination;
        target = settings;
        cursor = progress[1];
        manual = progress[2];
        revision = progress[3];
        deadline = stopAt;
        finished = callback;
    }

    function targetStillConfigured() {
        var settings = SyncTargets.get(slot);
        return settings != null && target[0].equals(settings[0]) && target[1].equals(settings[1]);
    }

    function send() as Void {
        if (deadline != null && System.getTimer() >= deadline) {
            finished.invoke(null);
            return;
        }
        if (!manual && !Application.Properties.getValue("autoUpload")) {
            finished.invoke("Automatic sync is off");
            return;
        }
        if (!targetStillConfigured()) {
            finished.invoke("Settings changed");
            return;
        }
        var path = "/api/notes/" + note["id"];
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_PUT,
            :headers => {
                "Authorization" => "Bearer " + target[1],
                "Content-Type" => "application/octet-stream"
            },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        if (cursor < note["chunks"]) {
            var chunk = Application.Storage.getValue(note["id"] + ":" + cursor);
            if (!(chunk instanceof Lang.ByteArray)) {
                finished.invoke("Missing audio");
                return;
            }
            options[:body] = chunk;
            path += "/chunks/" + cursor;
        } else {
            options[:method] = Communications.HTTP_REQUEST_METHOD_POST;
            options[:headers] = {
                "Authorization" => "Bearer " + target[1],
                "Content-Type" => "application/json"
            };
            path += "/complete";
        }
        try {
            Communications.makeWebRequest(
                target[0] + path,
                cursor == note["chunks"] ? note : null,
                options,
                method(:response)
            );
        } catch (e) {
            finished.invoke("Connection unavailable");
        }
    }

    function response(code as Lang.Number, data as Communications.ContentType?) as Void {
        if (!targetStillConfigured()) {
            finished.invoke("Settings changed");
            return;
        }
        var error = acknowledge(code, data);
        if (error != null || cursor == -1) {
            finished.invoke(error);
        } else {
            send();
        }
    }

    function acknowledge(code as Lang.Number, data as Communications.ContentType?) {
        var error = null;
        try {
            // Re-read state to preserve other targets' progress. A deleted recording has no first chunk.
            if (Application.Storage.getValue(note["id"] + ":0") == null) {
                return "Recording deleted";
            }
            var state = SyncTargets.read(note);
            var progress = SyncTargets.progress(note, state, slot, target[0]);
            if (progress[1] != cursor || progress[2] != manual || progress[3] != revision) {
                return "Sync queue changed";
            }
            if (code == 200 && data instanceof Lang.Dictionary && data["ok"] == true) {
                var complete = cursor == note["chunks"];
                cursor = complete ? -1 : cursor + 1;
                state[slot] = [target[0], cursor, !complete && manual, revision];
                Application.Storage.setValue(SyncTargets.key(note), state);
            } else {
                if (code == 409) {
                    state[slot] = [target[0], 0, manual, revision];
                    Application.Storage.setValue(SyncTargets.key(note), state);
                }
                error = "Sync error " + code;
            }
        } catch (e) {
            error = "Could not save sync progress";
        }
        return error;
    }
}
