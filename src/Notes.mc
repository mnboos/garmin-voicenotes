import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;

class Notes {
    var items as Lang.Array<Lang.Dictionary>;
    function initialize() {
        var stored = Application.Storage.getValue("notes");
        items = stored == null ? [] : stored as Lang.Array<Lang.Dictionary>;
        for (var i = items.size() - 1; i >= 0; i--) {
            var item = items[i] as Lang.Dictionary;
            if ("deleting".equals(item["state"])) {
                finishRemoval(item);
            } else if ("recording".equals(item["state"]) || "interrupted".equals(item["state"])) {
                // Discard the window that never committed to the catalog.
                Application.Storage.deleteValue(item["id"] + ":" + item["chunks"]);
                item["state"] = "interrupted";
            } else if ("draft".equals(item["state"])) {
                // Keep the committed draft available for the user's decision.
                Application.Storage.deleteValue(item["id"] + ":" + item["chunks"]);
            }
        }
        save();
    }
    function save() {
        Application.Storage.setValue("notes", items);
    }
    function create(format as Lang.Dictionary, extension, state) {
        if (items.size() >= 40) {
            throw new Lang.InvalidValueException("Storage full");
        }
        var seq = Application.Storage.getValue("sequence");
        if (seq == null) {
            seq = 0;
        }
        seq += 1;
        Application.Storage.setValue("sequence", seq);
        var installation = Application.Storage.getValue("installation");
        if (installation == null) {
            installation = Math.rand().format("%x") + Math.rand().format("%x");
            Application.Storage.setValue("installation", installation);
        }
        var id = installation + "-" + Time.now().value().toString() + "-" + seq.toString();
        var note = {
            "id" => id,
            "created" => Time.now().value(),
            "chunks" => 0,
            "bytes" => 0,
            "seconds" => 0,
            "state" => state,
            "extension" => extension,
            "format" => [
                format[:containerFormat],
                format[:codec],
                format[:frequency],
                format[:channels]
            ]
        };
        items.add(note);
        try {
            save();
        } catch (e) {
            items.remove(note);
            throw e;
        }
        return note;
    }
    function append(note as Lang.Dictionary, data as Lang.ByteArray) {
        // Write audio before publishing it in the catalogue.
        var key = note["id"] + ":" + note["chunks"];
        Application.Storage.setValue(key, data);
        note["chunks"] += 1;
        note["bytes"] += data.size();
        try {
            save();
        } catch (e) {
            note["chunks"] -= 1;
            note["bytes"] -= data.size();
            Application.Storage.deleteValue(key);
            throw e;
        }
    }
    function read(note as Lang.Dictionary, index) {
        return Application.Storage.getValue(note["id"] + ":" + index);
    }
    function format(note as Lang.Dictionary) {
        var f = note["format"] as Lang.Array;
        return { :containerFormat => f[0], :codec => f[1], :frequency => f[2], :channels => f[3] };
    }
    function remove(note as Lang.Dictionary) {
        var previous = note["state"];
        note["state"] = "deleting";
        try {
            save();
        } catch (e) {
            note["state"] = previous;
            throw e;
        }
        finishRemoval(note);
    }
    function finishRemoval(note as Lang.Dictionary) {
        for (var i = 0; i < note["chunks"]; i++) {
            Application.Storage.deleteValue(note["id"] + ":" + i);
        }
        Application.Storage.deleteValue("phone:" + note["id"]);
        Application.Storage.deleteValue(SyncTargets.key(note));
        Application.Storage.deleteValue("sent:" + note["id"]);
        Application.Storage.deleteValue("upload:" + note["id"]);
        Application.Storage.deleteValue("retry:" + note["id"]);
        items.remove(note);
        save();
    }
}
