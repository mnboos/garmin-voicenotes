import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Time;

(:background)
module UploadRequest {
    function nextNote(items as Lang.Array<Lang.Dictionary>, allowInterruptedCapture as Lang.Boolean) as Lang.Dictionary or Null {
        var next = null;
        var earliest = 0;
        for (var i = 0; i < items.size(); i++) {
            var note = items[i] as Lang.Dictionary;
            if (note["uploaded"] || note["bytes"] <= 0 || "deleting".equals(note["state"]) ||
                (!allowInterruptedCapture && "recording".equals(note["state"])) ||
                Application.Storage.getValue("sent:" + note["id"]) == true) { continue; }
            var retry = Application.Storage.getValue("retry:" + note["id"]);
            if (retry == null) { return note; }
            if (retry > 0 && retry <= Time.now().value() && (next == null || retry < earliest)) {
                next = note;
                earliest = retry;
            }
        }
        return next;
    }

    function defer(note as Lang.Dictionary, permanent as Lang.Boolean) {
        Application.Storage.setValue("retry:" + note["id"], permanent ? -1 : Time.now().value() + 300);
    }

    function rejected(code) { return code == 400 || code == 413 || code == 422; }

    function endpoint(url, token) {
        if (!(url instanceof Lang.String) || url.length() < 9 ||
            !url.substring(0, 8).equals("https://") ||
            !(token instanceof Lang.String) || token.length() == 0) {
            return null;
        }
        var end = url.length();
        return url.substring(end - 1, end).equals("/") ? url.substring(0, end - 1) : url;
    }

    function send(url, token, note as Lang.Dictionary, index as Lang.Number, callback) {
        var path = url + "/api/notes/" + note["id"];
        var options = {
            :headers=>{"Authorization"=>"Bearer " + token},
            :responseType=>Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        var metadata = null;
        if (index < note["chunks"]) {
            var chunk = Application.Storage.getValue(note["id"] + ":" + index);
            if (!(chunk instanceof Lang.ByteArray)) { return false; }
            path += "/chunks/" + index;
            options[:method] = Communications.HTTP_REQUEST_METHOD_PUT;
            options[:headers]["Content-Type"] = "application/octet-stream";
            options[:body] = chunk;
        } else {
            path += "/complete";
            options[:method] = Communications.HTTP_REQUEST_METHOD_POST;
            options[:headers]["Content-Type"] = "application/json";
            if (index == note["chunks"]) { metadata = note; }
        }
        Communications.makeWebRequest(path, metadata, options, callback);
        return true;
    }

    function acknowledged(code as Lang.Number, data as Communications.ContentType or Null) {
        return code == 200 && data instanceof Lang.Dictionary && data["ok"] == true;
    }
}
