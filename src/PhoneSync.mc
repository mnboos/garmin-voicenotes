import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.StringUtil;

(:background, :companion)
module PhoneSync {
    const BLOCK_BYTES = 768;
    const BINARY_BLOCK_BYTES = 4096;

    function reply(request as Lang.Dictionary) as Lang.Dictionary? {
        var rid = request["rid"];
        var op = request["op"];
        if (request["v"] != 1 || !(rid instanceof Lang.String) || !(op instanceof Lang.String)) {
            return null;
        }
        var response = null;
        try {
            if (op.equals("ping")) {
                response = { "op" => "pong" };
            } else if (op.equals("next")) {
                response = offer();
            } else if (op.equals("read")) {
                response = block(request["id"], request["offset"], request["binary"] == true);
            } else if (op.equals("saved")) {
                response = confirm(request["id"], request["bytes"]);
            }
        } catch (e) {
            response = { "op" => "error" };
        }
        if (response != null) {
            response["v"] = 1;
            response["rid"] = rid;
        }
        return response;
    }

    function catalogue() as Lang.Array<Lang.Dictionary> {
        var items = Application.Storage.getValue("notes") as Lang.Array<Lang.Dictionary>?;
        return items == null ? [] as Lang.Array<Lang.Dictionary> : items;
    }

    function sendable(note as Lang.Dictionary) as Lang.Boolean {
        return (
            !"deleting".equals(note["state"]) &&
            !"recording".equals(note["state"]) &&
            !"draft".equals(note["state"]) &&
            note["bytes"] > 0
        );
    }

    function find(id) as Lang.Dictionary? {
        if (!(id instanceof Lang.String)) {
            return null;
        }
        var items = catalogue();
        for (var i = 0; i < items.size(); i++) {
            var note = items[i] as Lang.Dictionary;
            if (id.equals(note["id"]) && sendable(note)) {
                return note;
            }
        }
        return null;
    }

    function offer() as Lang.Dictionary {
        var items = catalogue();
        for (var i = 0; i < items.size(); i++) {
            var note = items[i] as Lang.Dictionary;
            if (!sendable(note) || Application.Storage.getValue("phone:" + note["id"]) == true) {
                continue;
            }
            return {
                "op" => "offer",
                "id" => note["id"],
                "bytes" => note["bytes"],
                "ext" => note["extension"],
                "created" => note["created"]
            };
        }
        return { "op" => "empty" };
    }

    // The requested note or audio does not exist. "error" means the lookup itself failed.
    function missing(id) as Lang.Dictionary {
        return { "op" => "missing", "id" => id };
    }

    function block(id, offset, binary as Lang.Boolean) as Lang.Dictionary {
        var note = find(id);
        if (note == null || !(offset instanceof Lang.Number)) {
            return missing(id);
        }
        var data = readBlock(note, offset, binary ? BINARY_BLOCK_BYTES : BLOCK_BYTES);
        if (data == null) {
            return missing(id);
        }
        return {
            "op" => "block",
            "id" => id,
            "offset" => offset,
            "data" => binary
                ? data
                : StringUtil.convertEncodedString(data, {
                      :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
                      :toRepresentation => StringUtil.REPRESENTATION_STRING_BASE64
                  })
        };
    }

    function confirm(id, bytes) as Lang.Dictionary {
        var note = find(id);
        if (note == null || bytes != note["bytes"]) {
            return missing(id);
        }
        Application.Storage.setValue("phone:" + id, true);
        return { "op" => "confirmed", "id" => id };
    }

    function readBlock(
        note as Lang.Dictionary,
        offset as Lang.Number,
        limit as Lang.Number
    ) as Lang.ByteArray? {
        if (offset < 0 || offset >= note["bytes"]) {
            return null;
        }
        for (var i = 0; i < note["chunks"]; i++) {
            var data = Application.Storage.getValue(note["id"] + ":" + i);
            if (!(data instanceof Lang.ByteArray)) {
                return null;
            }
            if (offset < data.size()) {
                var end = offset + limit;
                if (end > data.size()) {
                    end = data.size();
                }
                return data.slice(offset, end);
            }
            offset -= data.size();
        }
        return null;
    }
}

// What the watch shows after answering the phone. Not needed by the background service.
(:companion)
module PhoneStatus {
    function text(response as Lang.Dictionary, items as Lang.Array) as Lang.String? {
        var op = response["op"];
        if ("pong".equals(op)) {
            return "Phone connected";
        }
        if ("confirmed".equals(op)) {
            return "Sent to phone";
        }
        if ("missing".equals(op)) {
            return "Note unavailable";
        }
        if ("error".equals(op)) {
            return "Phone sync failed";
        }
        if ("block".equals(op)) {
            for (var i = 0; i < items.size(); i++) {
                var note = items[i] as Lang.Dictionary;
                if (note["id"].equals(response["id"])) {
                    return "To phone " + (response["offset"] * 100) / note["bytes"] + "%";
                }
            }
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
        if (service) {
            Background.exit(null);
        }
    }
    function onError() as Void {
        onComplete();
    }
}

// Reports whether the opening message reached the phone.
(:companion)
class PhoneHello extends Communications.ConnectionListener {
    var app as VoicenotesApp;
    function initialize(owner as VoicenotesApp) {
        ConnectionListener.initialize();
        app = owner;
    }
    function onComplete() as Void {
        app.phoneLink(true);
    }
    function onError() as Void {
        app.phoneLink(false);
    }
}
