import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.StringUtil;
import Toybox.System;
import Toybox.WatchUi;

class PhoneSync {
    // The phone app accepts at most 768 bytes per block.
    const BLOCK_BYTES = 768;
    const VERSION = 1;

    var store as Notes;
    var upload as Upload;
    // Cache the current chunk for sequential reads.
    var cursorId as Lang.String? = null;
    var cursorChunk = 0;
    var cursorStart = 0;
    var cursorData as Lang.ByteArray? = null;

    function initialize(notes as Notes, uploads as Upload) {
        store = notes;
        upload = uploads;
        Communications.registerForPhoneAppMessages(method(:onPhone));
        // Wake the companion before its next poll.
        System.println("phone sync registered");
        upload.message = "Phone: waiting";
        Communications.transmit({ "v" => VERSION, "op" => "sync" }, null, new PhoneReply(self));
    }

    function linkResult(ok as Lang.Boolean) as Void {
        System.println(ok ? "phone hello delivered" : "phone hello failed");
        if (upload.message.find("Phone:") == 0) {
            show(ok ? "Phone: link OK" : "Phone: link failed");
        }
    }

    function show(text as Lang.String) as Void {
        if (!upload.busy) {
            upload.message = text;
            WatchUi.requestUpdate();
        }
    }

    static function deliveredKey(note as Lang.Dictionary) as Lang.String {
        return "phone:" + note["id"];
    }

    static function delivered(note as Lang.Dictionary) as Lang.Boolean {
        return Application.Storage.getValue(deliveredKey(note)) == true;
    }

    function onPhone(message as Communications.PhoneAppMessage) as Void {
        var request = message.data;
        System.println("phone in: " + request);
        if (!(request instanceof Lang.Dictionary) || request["v"] != VERSION) {
            return;
        }
        var rid = request["rid"];
        var op = request["op"];
        if (!(rid instanceof Lang.String) || !(op instanceof Lang.String)) {
            return;
        }
        var reply = null;
        try {
            if (op.equals("ping")) {
                show("Phone connected");
                reply = { "op" => "pong" };
            } else if (op.equals("next")) {
                reply = offer();
            } else if (op.equals("read")) {
                reply = block(request["id"], request["offset"]);
            } else if (op.equals("saved")) {
                reply = confirm(request["id"], request["bytes"]);
            }
        } catch (e) {
            reply = { "op" => "error" };
        }
        if (reply == null) {
            return;
        }
        reply["v"] = VERSION;
        reply["rid"] = rid;
        System.println("phone out: " + reply["op"]);
        Communications.transmit(reply, null, new PhoneReply(null));
    }

    function offer() as Lang.Dictionary {
        for (var i = 0; i < store.items.size(); i++) {
            var note = store.items[i] as Lang.Dictionary;
            if (note["bytes"] == 0 || note["state"].equals("recording") || delivered(note)) {
                continue;
            }
            return {
                "op" => "offer",
                "id" => note["id"],
                "ext" => note["extension"],
                "bytes" => note["bytes"],
                "created" => note["created"]
            };
        }
        return { "op" => "empty" };
    }

    function block(id, offset) as Lang.Dictionary {
        var note = find(id);
        if (
            note == null ||
            !(offset instanceof Lang.Number) ||
            offset < 0 ||
            offset >= note["bytes"]
        ) {
            return { "op" => "missing", "id" => id };
        }
        var data = bytesAt(note, offset);
        if (data == null) {
            return { "op" => "missing", "id" => id };
        }
        show("To phone " + (offset * 100) / note["bytes"] + "%");
        return {
            "op" => "block",
            "id" => id,
            "offset" => offset,
            "data" => StringUtil.convertEncodedString(data, {
                :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
                :toRepresentation => StringUtil.REPRESENTATION_STRING_BASE64
            })
        };
    }

    function confirm(id, bytes) as Lang.Dictionary {
        var note = find(id);
        if (note == null || bytes != note["bytes"]) {
            return { "op" => "missing", "id" => id };
        }
        Application.Storage.setValue(deliveredKey(note), true);
        show("Sent to phone");
        if (id.equals(cursorId)) {
            forget();
        }
        return { "op" => "confirmed", "id" => id };
    }

    function bytesAt(note as Lang.Dictionary, offset as Lang.Number) as Lang.ByteArray? {
        if (!note["id"].equals(cursorId) || offset < cursorStart) {
            cursorId = note["id"];
            cursorChunk = 0;
            cursorStart = 0;
            cursorData = null;
        }
        while (cursorChunk < note["chunks"]) {
            if (cursorData == null) {
                var chunk = store.read(note, cursorChunk);
                if (!(chunk instanceof Lang.ByteArray)) {
                    forget();
                    return null;
                }
                cursorData = chunk;
            }
            var data = cursorData as Lang.ByteArray;
            if (offset < cursorStart + data.size()) {
                var from = offset - cursorStart;
                var to = from + BLOCK_BYTES < data.size() ? from + BLOCK_BYTES : data.size();
                return data.slice(from, to);
            }
            cursorStart += data.size();
            cursorChunk++;
            cursorData = null;
        }
        forget();
        return null;
    }

    function find(id) as Lang.Dictionary? {
        if (!(id instanceof Lang.String)) {
            return null;
        }
        for (var i = 0; i < store.items.size(); i++) {
            var note = store.items[i] as Lang.Dictionary;
            if (id.equals(note["id"])) {
                return note;
            }
        }
        return null;
    }

    function forget() as Void {
        cursorId = null;
        cursorChunk = 0;
        cursorStart = 0;
        cursorData = null;
    }
}

// The phone retries unanswered requests.
class PhoneReply extends Communications.ConnectionListener {
    var owner as PhoneSync?;

    function initialize(sync as PhoneSync?) {
        ConnectionListener.initialize();
        owner = sync;
    }

    function onComplete() as Void {
        if (owner != null) {
            owner.linkResult(true);
        }
    }

    function onError() as Void {
        System.println("phone transmit failed");
        if (owner != null) {
            owner.linkResult(false);
        }
    }
}
