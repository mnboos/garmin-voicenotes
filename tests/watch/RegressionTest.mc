import Toybox.Application;
import Toybox.Test;

(:test)
function recordingLocationPreferencePersists(logger) {
    Application.Storage.deleteValue("saveLocation");
    var store = new Notes();
    var recorder = new Recorder(store);
    try {
        Test.assert(!recorder.savesLocation());
        recorder.setSaveLocation(true);
        Test.assert(new Recorder(store).savesLocation());
        recorder.setSaveLocation(false);
        Test.assert(!new Recorder(store).savesLocation());
    } finally {
        Application.Storage.deleteValue("saveLocation");
    }
    return true;
}

(:test)
function partialCaptureStatus(logger) {
    var store = new Notes();
    var recorder = new Recorder(store);
    recorder.note = {"state"=>"interrupted", "bytes"=>32};
    recorder.active = true;
    recorder.message = "Storage full; partial note";
    recorder.onComplete();
    Test.assertEqual("Storage full; partial note", recorder.message);
    return true;
}

(:test)
function interruptedAppendRecovery(logger) {
    var store = new Notes();
    var note = store.create({}, "ogg");
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
    var note = store.create({}, "wav");
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

// Stand in for the receiver at the request boundary, including its completion ACK.
class TestForegroundUpload extends Upload {
    var rejected;
    function initialize(store, badId) { Upload.initialize(store); rejected = badId; }
    function send() {
        if (rejected.equals(current["id"])) { response(422, null); }
        else { response(200, {"ok"=>true}); }
    }
}

function queuedNote(store) {
    var note = store.create({}, "ogg");
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
function foregroundSkipsRejectedNote(logger) {
    enableTestUpload();
    var store = new Notes();
    var bad = queuedNote(store);
    var good = queuedNote(store);
    var uploader = new TestForegroundUpload(store, bad["id"]);
    uploader.tick();
    uploader.tick();
    Test.assert(good["uploaded"]);
    Test.assert(!bad["uploaded"]);
    store.remove(bad);
    store.remove(good);
    return true;
}

class TestBackgroundUpload extends BackgroundUpload {
    var missingId;
    function initialize(badId) { BackgroundUpload.initialize(); missingId = badId; }
    function send() as Void {
        if (missingId.equals(note["id"])) { BackgroundUpload.send(); }
        else { response(200, {"ok"=>true}); }
    }
}

(:test)
function backgroundAdvancesAfterMissingChunk(logger) {
    enableTestUpload();
    var store = new Notes();
    var bad = queuedNote(store);
    var good = queuedNote(store);
    Application.Storage.deleteValue(bad["id"] + ":0");
    new TestBackgroundUpload(bad["id"]).onTemporalEvent();
    new TestBackgroundUpload(bad["id"]).onTemporalEvent();
    store.refreshUploads();
    Test.assert(good["uploaded"]);
    Test.assert(!bad["uploaded"]);
    store.remove(bad);
    store.remove(good);
    return true;
}

class UnavailableBackgroundUpload extends BackgroundUpload {
    function send() as Void { response(503, null); }
}

(:test)
function backgroundRetriesFairlyAcrossWakes(logger) {
    enableTestUpload();
    var store = new Notes();
    var bad = queuedNote(store);
    var good = queuedNote(store);
    new UnavailableBackgroundUpload().onTemporalEvent();
    // Advance the persisted retry deadline to model the next scheduled wake.
    Application.Storage.setValue("retry:" + bad["id"], 1);
    new TestBackgroundUpload("none").onTemporalEvent();
    store.refreshUploads();
    Test.assert(good["uploaded"]);
    Test.assert(!bad["uploaded"]);
    new TestBackgroundUpload("none").onTemporalEvent();
    store.refreshUploads();
    Test.assert(bad["uploaded"]);
    store.remove(bad);
    store.remove(good);
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
