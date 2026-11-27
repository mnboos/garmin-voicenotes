import Toybox.Application;
import Toybox.Test;
import Toybox.Lang;

(:test)
function partialCaptureStatus(logger) {
    var store = new Notes();
    var recorder = new Recorder(store);
    var note = queuedNote(store);
    note["state"] = "recording";
    recorder.note = note;
    recorder.active = true;
    recorder.finishing = true;
    recorder.partial = true;
    recorder.closing = true;
    recorder.onComplete();
    Test.assertEqual("interrupted", note["state"]);
    Test.assertEqual(4, note["bytes"]);
    store.remove(note);
    return true;
}

(:test)
function interruptedAppendRecovery(logger) {
    var store = new Notes();
    var note = store.create({}, "ogg", "recording");
    store.append(note, [1, 2]b);
    // Model a shutdown after the next window reaches storage, before catalog save.
    Application.Storage.setValue(note["id"] + ":1", [3]b);
    var reopened = new Notes();
    var recovered = reopened.items[reopened.items.size()-1];
    Test.assertEqual("interrupted", recovered["state"]);
    Test.assertEqual(2, recovered["bytes"]);
    Test.assertEqual(2, reopened.read(recovered, 0).size());
    Test.assert(reopened.read(recovered, 1) == null);
    reopened.remove(recovered);
    return true;
}

(:test)
function interruptedDeletionRecovery(logger) {
    var store = new Notes();
    var count = store.items.size();
    var note = store.create({}, "wav", "recording");
    store.append(note, [1]b);
    store.append(note, [2]b);
    note["state"] = "deleting";
    store.save();
    Application.Storage.deleteValue(note["id"] + ":0");
    var reopened = new Notes();
    Test.assertEqual(count, reopened.items.size());
    Test.assert(reopened.read(note, 0) == null);
    Test.assert(reopened.read(note, 1) == null);
    return true;
}

function queuedNote(store) {
    var note = store.create({}, "ogg", "recording");
    store.append(note, [79, 103, 103, 83]b);
    note["state"] = "saved";
    store.save();
    return note;
}

function enableTestUpload() {
    Application.Storage.clearValues();
    Application.Properties.setValue("autoUpload", true);
    Application.Properties.setValue("serverUrl", "https://receiver.example");
    Application.Properties.setValue("serverToken", "simulator-test");
}

(:test)
function receiverRetryKeepsOtherTargetProgress(logger) {
    enableTestUpload();
    var store = new Notes();
    var note = queuedNote(store);
    var primary = SyncTargets.get(0) as Lang.Array<Lang.String>;
    var other = ["https://second.example", -1, false, 0];
    Application.Storage.setValue(SyncTargets.key(note), {1 => other});
    var transfer = new SyncTransfer(note, 0, primary, [primary[0], 0, false, 0], null, null);

    Test.assert(transfer.acknowledge(422, null) != null);
    Test.assertEqual(0, transfer.cursor);
    Test.assert(transfer.acknowledge(200, {"ok" => true}) == null);
    Test.assertEqual(1, transfer.cursor);
    Test.assert(transfer.acknowledge(503, null) != null);
    Test.assertEqual(1, transfer.cursor);
    Test.assert(transfer.acknowledge(200, {"ok" => true}) == null);

    var progress = SyncTargets.read(note);
    Test.assertEqual(-1, progress[0][1]);
    Test.assertEqual(other[0], progress[1][0]);
    Test.assertEqual(-1, progress[1][1]);
    store.remove(note);
    return true;
}

(:test)
function recoveredDraftRequiresDecision(logger) {
    var store = new Notes();
    var draft = store.create({}, "wav", "draft");
    store.append(draft, [1, 2]b);
    Application.Storage.setValue(draft["id"] + ":1", [3]b);

    var reopened = new Notes();
    var recorder = new Recorder(reopened);
    Test.assert(recorder.awaitingDecision);
    var recovered = recorder.note;
    Test.assertEqual("draft", recovered["state"]);
    Test.assertEqual(2, recovered["bytes"]);
    Test.assert(reopened.read(recovered, 1) == null);
    recorder.resolveDraft(true);
    Test.assert(!recorder.awaitingDecision);
    Test.assertEqual("saved", recovered["state"]);
    reopened.remove(recovered);
    return true;
}

(:test)
function previouslyInterruptedNoteReclaimsUncommittedWindow(logger) {
    var store = new Notes();
    var note = queuedNote(store);
    note["state"] = "interrupted";
    store.save();
    Application.Storage.setValue(note["id"] + ":1", [5]b);
    var reopened = new Notes();
    var recovered = reopened.items[reopened.items.size()-1];
    Test.assert(reopened.read(recovered, 1) == null);
    Test.assertEqual(4, reopened.read(recovered, 0).size());
    reopened.remove(recovered);
    return true;
}
