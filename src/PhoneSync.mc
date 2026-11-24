import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.StringUtil;

(:background, :companion)
module PhoneSync {
    const BLOCK_BYTES = 768;

    function reply(request as Lang.Dictionary) as Lang.Dictionary or Null {
        if (request["v"] != 1 || !(request["rid"] instanceof Lang.String)) { return null; }
        var op = request["op"];
        var next = "next".equals(op);
        var response = {"v"=>1, "rid"=>request["rid"], "op"=>next ? "empty" : "error"};
        if ("ping".equals(op)) {
            response["op"] = "pong";
            return response;
        }

        var items = Application.Storage.getValue("notes") as Lang.Array<Lang.Dictionary> or Null;
        if (items == null) { return response; }
        for (var i = 0; i < items.size(); i++) {
            var note = items[i] as Lang.Dictionary;
            if ("deleting".equals(note["state"]) || "recording".equals(note["state"]) || note["bytes"] <= 0) { continue; }
            var id = note["id"];
            if (next) {
                if (Application.Storage.getValue("phone:" + id) == true) { continue; }
                response["op"] = "offer";
                response["id"] = id;
                response["bytes"] = note["bytes"];
                response["ext"] = note["extension"];
                response["created"] = note["created"];
                return response;
            }
            if (!id.equals(request["id"])) { continue; }
            if ("read".equals(op) && request["offset"] instanceof Lang.Number) {
                var block = readBlock(note, request["offset"] as Lang.Number);
                if (block != null) {
                    response["op"] = "block";
                    response["id"] = id;
                    response["offset"] = request["offset"];
                    response["data"] = block;
                }
            } else if ("saved".equals(op) && request["bytes"] == note["bytes"]) {
                Application.Storage.setValue("phone:" + id, true);
                response["op"] = "confirmed";
                response["id"] = id;
            }
            break;
        }
        return response;
    }

    function readBlock(note as Lang.Dictionary, offset as Lang.Number) {
        if (offset < 0 || offset >= note["bytes"]) { return null; }
        for (var i = 0; i < note["chunks"]; i++) {
            var data = Application.Storage.getValue(note["id"] + ":" + i);
            if (!(data instanceof Lang.ByteArray)) { return null; }
            if (offset < data.size()) {
                var end = offset + BLOCK_BYTES;
                if (end > data.size()) { end = data.size(); }
                return StringUtil.convertEncodedString(data.slice(offset, end),
                    {:fromRepresentation=>StringUtil.REPRESENTATION_BYTE_ARRAY,
                     :toRepresentation=>StringUtil.REPRESENTATION_STRING_BASE64});
            }
            offset -= data.size();
        }
        return null;
    }
}

(:background, :companion)
class PhoneReply extends Communications.ConnectionListener {
    var service as Lang.Boolean;
    function initialize(background as Lang.Boolean) {
        ConnectionListener.initialize();
        service = background;
    }
    function onComplete() as Void {
        if (service) { Background.exit(null); }
    }
    function onError() as Void {
        onComplete();
    }
}
