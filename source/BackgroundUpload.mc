import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;

(:background)
class BackgroundUpload extends System.ServiceDelegate {
    var transfer = null;
    var items as Lang.Array<Lang.Dictionary>?;
    var deadline;
    var nextSlot;
    var skipped as Lang.Array<Lang.Boolean> = [false, false, false];

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        if (!System.getDeviceSettings().connectionAvailable) {
            Background.exit(null);
            return;
        }
        SyncTargets.bindLegacy();
        items = Application.Storage.getValue("notes") as Lang.Array<Lang.Dictionary>?;
        if (items == null) {
            Background.exit(null);
            return;
        }
        nextSlot = Application.Storage.getValue("sync:nextSlot");
        if (nextSlot == null) {
            nextSlot = 0;
        }
        deadline = System.getTimer() + 20000;
        runNext();
    }

    function runNext() {
        if (System.getTimer() < deadline) {
            var auto = Application.Properties.getValue("autoUpload");
            for (var offset = 0; offset < SyncTargets.COUNT; offset++) {
                var slot = (nextSlot + offset) % SyncTargets.COUNT;
                if (skipped[slot]) {
                    continue;
                }
                var target = SyncTargets.get(slot);
                if (target == null) {
                    continue;
                }
                var rotationKey = "sync:nextNote:" + slot;
                var savedIndex = Application.Storage.getValue(rotationKey);
                var first = savedIndex == null ? 0 : savedIndex as Lang.Number;
                for (var scanned = 0; scanned < items.size(); scanned++) {
                    var i = (first + scanned) % items.size();
                    var note = items[i] as Lang.Dictionary;
                    if (note["bytes"] == 0) {
                        continue;
                    }
                    var progress = SyncTargets.progress(
                        note,
                        SyncTargets.read(note),
                        slot,
                        target[0]
                    );
                    if (progress[1] == -1 || (!auto && !progress[2])) {
                        continue;
                    }
                    if (note["state"].equals("recording")) {
                        note["state"] = "interrupted";
                    }
                    nextSlot = (slot + 1) % SyncTargets.COUNT;
                    Application.Storage.setValue("sync:nextSlot", nextSlot);
                    Application.Storage.setValue(rotationKey, i + 1);
                    transfer = new SyncTransfer(
                        note,
                        slot,
                        target,
                        progress,
                        deadline,
                        method(:finished)
                    );
                    transfer.send();
                    return;
                }
            }
        }
        Background.exit(null);
    }

    function finished(error) {
        if (error != null) {
            skipped[transfer.slot] = true;
        }
        transfer = null;
        runNext();
    }
}
