import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

(:background)
class BackgroundUpload extends System.ServiceDelegate {
    var note as Lang.Dictionary or Null = null;
    var index = 0;
    var started = 0;
    var baseUrl;
    var token;
    function initialize() { ServiceDelegate.initialize(); }
    function onTemporalEvent() as Void {
        if (!Application.Properties.getValue("autoUpload")) { Background.exit(null); return; }
        baseUrl = Application.Properties.getValue("serverUrl");
        token = Application.Properties.getValue("serverToken");
        if (!(baseUrl instanceof Lang.String) || baseUrl.length() < 9 ||
            !baseUrl.substring(0,8).equals("https://") || !(token instanceof Lang.String) || token.length() == 0) {
            Background.exit(null); return;
        }
        if (baseUrl.substring(baseUrl.length()-1, baseUrl.length()).equals("/")) {
            baseUrl = baseUrl.substring(0, baseUrl.length()-1);
        }
        var items = Application.Storage.getValue("notes") as Lang.Array<Lang.Dictionary> or Null;
        if (items == null) { Background.exit(null); return; }
        for (var i = 0; i < items.size(); i++) {
            var candidate = items[i] as Lang.Dictionary;
            if (candidate["bytes"] > 0 && !candidate["uploaded"] &&
                Application.Storage.getValue("sent:" + candidate["id"]) != true) {
                note = candidate;
                if (note["state"] == "recording") { note["state"] = "interrupted"; }
                var cursor = Application.Storage.getValue("upload:" + note["id"]);
                index = cursor == null ? 0 : cursor as Lang.Number;
                started = System.getTimer();
                send(); return;
            }
        }
        Background.exit(null);
    }
    function send() as Void {
        if (System.getTimer() - started > 20000) { Background.exit(null); return; }
        var path = "/api/notes/" + note["id"];
        var options = {:method=>Communications.HTTP_REQUEST_METHOD_PUT,
            :headers=>{"Authorization"=>"Bearer " + token,"Content-Type"=>"application/octet-stream"},
            :responseType=>Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON};
        if (index < note["chunks"]) {
            var data = Application.Storage.getValue(note["id"] + ":" + index);
            if (!(data instanceof Lang.ByteArray)) { Background.exit(null); return; }
            options[:body] = data;
            path += "/chunks/" + index;
        } else {
            options[:method] = Communications.HTTP_REQUEST_METHOD_POST;
            options[:headers]["Content-Type"] = "application/json";
            path += "/complete";
        }
        try {
            Communications.makeWebRequest(baseUrl + path,
                index == note["chunks"] ? note : null, options, method(:response));
        } catch (e) { Background.exit(null); }
    }
    function response(code as Lang.Number, data as Communications.ContentType or Null) as Void {
        if (code != 200 || !(data instanceof Lang.Dictionary) || data["ok"] != true) {
            if (code == 409) { Application.Storage.deleteValue("upload:" + note["id"]); }
            Background.exit(null); return;
        }
        try {
            if (index == note["chunks"]) {
                Application.Storage.setValue("sent:" + note["id"], true);
                Application.Storage.deleteValue("upload:" + note["id"]);
                Background.exit(note["id"]); return;
            }
            index++;
            Application.Storage.setValue("upload:" + note["id"], index);
            send();
        } catch (e) { Background.exit(null); }
    }
}
