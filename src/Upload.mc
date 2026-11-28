import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class Upload {
    var store as Notes;
    var transfer = null;
    var busy = false;
    var message = "";
    var retryAt as Lang.Array<Lang.Number> = [0, 0, 0];
    var nextNote as Lang.Array<Lang.Number> = [0, 0, 0];
    var connected = false;

    function initialize(notes) {
        store = notes;
        SyncTargets.bindLegacy();
    }

    function tick() {
        var online = System.getDeviceSettings().connectionAvailable;
        if (online && !connected) {
            retryAt = [0, 0, 0];
        }
        connected = online;
        if (busy || !online) {
            return;
        }
        var auto = Application.Properties.getValue("autoUpload");
        var now = System.getTimer();
        for (var slot = 0; slot < SyncTargets.COUNT; slot++) {
            if (now < retryAt[slot]) {
                continue;
            }
            var target = SyncTargets.get(slot);
            if (target == null) {
                continue;
            }
            for (var scanned = 0; scanned < store.items.size(); scanned++) {
                var i = (nextNote[slot] + scanned) % store.items.size();
                var note = store.items[i] as Lang.Dictionary;
                if (
                    note["bytes"] <= 0 ||
                    "deleting".equals(note["state"]) ||
                    "draft".equals(note["state"]) ||
                    "recording".equals(note["state"])
                ) {
                    continue;
                }
                var progress = SyncTargets.progress(note, SyncTargets.read(note), slot, target[0]);
                if (progress[1] == -1 || (!auto && !progress[2])) {
                    continue;
                }
                nextNote[slot] = i + 1;
                busy = true;
                message = "Syncing to target " + (slot + 1);
                transfer = new SyncTransfer(note, slot, target, progress, null, method(:finished));
                transfer.send();
                return;
            }
        }
    }

    function resync(note as Lang.Dictionary) {
        if (
            note["bytes"] <= 0 ||
            "deleting".equals(note["state"]) ||
            "draft".equals(note["state"])
        ) {
            message = "No audio to sync";
            return;
        }
        var state = SyncTargets.read(note);
        var count = 0;
        for (var slot = 0; slot < SyncTargets.COUNT; slot++) {
            var target = SyncTargets.get(slot);
            if (target == null) {
                continue;
            }
            var previous = state[slot] as Lang.Array?;
            state[slot] = [target[0], 0, true, previous == null ? 1 : previous[3] + 1];
            count++;
        }
        if (count == 0) {
            message = "Set a sync target";
            return;
        }
        Application.Storage.setValue(SyncTargets.key(note), state);
        retryAt = [0, 0, 0];
        message = "Sync queued";
    }

    function status(note as Lang.Dictionary) {
        if (
            note["bytes"] <= 0 ||
            "deleting".equals(note["state"]) ||
            "draft".equals(note["state"])
        ) {
            return "No audio";
        }
        var state = SyncTargets.read(note);
        var total = 0;
        var synced = 0;
        var queued = Application.Properties.getValue("autoUpload");
        for (var slot = 0; slot < SyncTargets.COUNT; slot++) {
            var target = SyncTargets.get(slot);
            if (target == null) {
                continue;
            }
            var progress = SyncTargets.progress(note, state, slot, target[0]);
            total++;
            if (progress[1] == -1) {
                synced++;
            }
            queued = queued || progress[2];
        }
        if (total == 0 || (synced == 0 && !queued)) {
            return "On watch";
        }
        if (synced == 0) {
            return "Sync queued";
        }
        return "Synced " + synced + "/" + total;
    }

    function finished(error) {
        if (error == null) {
            message = "Synced to target " + (transfer.slot + 1);
        } else {
            retryAt[transfer.slot] = System.getTimer() + 15000;
            message = "Queued: " + error;
        }
        transfer = null;
        busy = false;
        WatchUi.requestUpdate();
    }
}
