import Toybox.Application;
import Toybox.Audio;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;

// Each chunk is below Storage's 32 KB value limit. The catalogue is small.
// Persist the chunk before the catalogue so a failed write never references missing audio.
class Notes {
    var items as Lang.Array<Lang.Dictionary>;
    const LIMIT = 80000;
    function initialize() {
        var stored = Application.Storage.getValue("notes");
        items = stored == null ? [] : stored as Lang.Array<Lang.Dictionary>;
        for (var i = 0; i < items.size(); i++) {
            var item = items[i] as Lang.Dictionary;
            if (item["state"] == "recording") {
                item["state"] = "interrupted";
            }
        }
        refreshUploads();
        save();
    }
    function refreshUploads() {
        for (var i = 0; i < items.size(); i++) {
            var item = items[i] as Lang.Dictionary;
            if (Application.Storage.getValue("sent:" + item["id"]) == true) { item["uploaded"] = true; }
        }
    }
    function save() { Application.Storage.setValue("notes", items); }
    function used() {
        var size = 0;
        for (var i = 0; i < items.size(); i++) { size += items[i]["bytes"]; }
        return size;
    }
    function create(format as Lang.Dictionary, extension) {
        if (used() > LIMIT - 8192 || items.size() >= 40) {
            throw new Lang.InvalidValueException("Storage full");
        }
        var seq = Application.Storage.getValue("sequence");
        if (seq == null) { seq = 0; }
        seq += 1;
        Application.Storage.setValue("sequence", seq);
        var installation = Application.Storage.getValue("installation");
        if (installation == null) {
            installation = Math.rand().format("%x") + Math.rand().format("%x");
            Application.Storage.setValue("installation", installation);
        }
        var id = installation + "-" + Time.now().value().toString() + "-" + seq.toString();
        var note = {"id"=>id, "created"=>Time.now().value(), "chunks"=>0,
            "bytes"=>0, "seconds"=>0, "state"=>"recording", "uploaded"=>false,
            "extension"=>extension, "format"=>[format[:containerFormat], format[:codec],
                format[:frequency], format[:channels]]};
        items.add(note);
        save();
        return note;
    }
    function append(note as Lang.Dictionary, data as Lang.ByteArray) {
        if (used() + data.size() > LIMIT) { return false; }
        var key = note["id"] + ":" + note["chunks"];
        Application.Storage.setValue(key, data);
        note["chunks"] += 1;
        note["bytes"] += data.size();
        try { save(); } catch (e) {
            note["chunks"] -= 1;
            note["bytes"] -= data.size();
            Application.Storage.deleteValue(key);
            throw e;
        }
        return true;
    }
    function read(note as Lang.Dictionary, index) {
        return Application.Storage.getValue(note["id"] + ":" + index);
    }
    function format(note as Lang.Dictionary) {
        var f = note["format"] as Lang.Array;
        return {:containerFormat=>f[0], :codec=>f[1], :frequency=>f[2], :channels=>f[3]};
    }
    function remove(note as Lang.Dictionary) {
        // Remove chunks first; deletion is explicit and confirmed in the UI.
        for (var i = 0; i < note["chunks"]; i++) {
            Application.Storage.deleteValue(note["id"] + ":" + i);
        }
        items.remove(note);
        save();
        Application.Storage.deleteValue("sent:" + note["id"]);
        Application.Storage.deleteValue("upload:" + note["id"]);
    }
}
