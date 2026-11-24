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
    (:companion)
    function onPhoneAppMessage(message as Communications.PhoneAppMessage) as Void {
        var request = message.data;
        if (request instanceof Lang.Dictionary) {
            try {
                var response = PhoneSync.reply(request);
                if (response != null) {
                    System.println("Phone sync background " + response["op"]);
                    Communications.transmit(response, null, new PhoneReply(true));
                    return;
                }
            } catch (e) { }
        }
        Background.exit(null);
    }
    function onTemporalEvent() as Void {
        if (!Application.Properties.getValue("autoUpload")) { Background.exit(null); return; }
        token = Application.Properties.getValue("serverToken");
        baseUrl = UploadRequest.endpoint(Application.Properties.getValue("serverUrl"), token);
        if (baseUrl == null) { Background.exit(null); return; }
        var items = Application.Storage.getValue("notes") as Lang.Array<Lang.Dictionary> or Null;
        if (items == null) { Background.exit(null); return; }
        note = UploadRequest.nextNote(items, true);
        if (note == null) { Background.exit(null); return; }
        // A terminated recording still has recoverable saved chunks.
        if ("recording".equals(note["state"])) { note["state"] = "interrupted"; }
        var cursor = Application.Storage.getValue("upload:" + note["id"]);
        index = cursor == null ? 0 : cursor as Lang.Number;
        started = System.getTimer();
        send();
    }
    function send() as Void {
        if (System.getTimer() - started > 20000) { Background.exit(null); return; }
        try {
            if (!UploadRequest.send(baseUrl, token, note, index, method(:response))) {
                UploadRequest.defer(note, true);
                Background.exit(null);
            }
        } catch (e) {
            try { UploadRequest.defer(note, false); } catch (ignored) { }
            Background.exit(null);
        }
    }
    function response(code as Lang.Number, data as Communications.ContentType or Null) as Void {
        if (!UploadRequest.acknowledged(code, data)) {
            // Server data may have been restored or removed: replay safely next time.
            try {
                if (code == 409) { Application.Storage.deleteValue("upload:" + note["id"]); }
                UploadRequest.defer(note, UploadRequest.rejected(code));
            } catch (e) { }
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
