import Toybox.Application;
import Toybox.Lang;
import Toybox.StringUtil;
import Toybox.Test;

// Watch storage chunk size used by the recorder.
const CHUNK_BYTES = 4096;
// Larger than the 80,000-byte limit the phone sync used to have.
const LARGE_BYTES = 96044;

function ask(op as Lang.String, extra as Lang.Dictionary) as Lang.Dictionary? {
    var request = { "v" => 1, "rid" => "r", "op" => op };
    var keys = extra.keys();
    for (var i = 0; i < keys.size(); i++) {
        request[keys[i]] = extra[keys[i]];
    }
    return PhoneSync.reply(request);
}

function op(reply as Lang.Dictionary?) as Lang.String? {
    return reply == null ? null : reply["op"] as Lang.String;
}

// Byte p of every stored test note is p % 256, so any block can be checked from its offset.
function storeNote(id as Lang.String, bytes as Lang.Number, state as Lang.String) as Lang.Dictionary {
    var pattern = new [256]b;
    for (var i = 0; i < 256; i++) {
        pattern[i] = i;
    }
    var chunks = 0;
    for (var start = 0; start < bytes; start += CHUNK_BYTES) {
        var size = bytes - start < CHUNK_BYTES ? bytes - start : CHUNK_BYTES;
        var data = new [0]b;
        while (data.size() + 256 <= size) {
            data.addAll(pattern);
        }
        data.addAll(pattern.slice(0, size - data.size()));
        Application.Storage.setValue(id + ":" + chunks, data);
        chunks++;
    }
    return {
        "id" => id,
        "state" => state,
        "bytes" => bytes,
        "chunks" => chunks,
        "extension" => "wav",
        "created" => 1
    };
}

function decode(reply as Lang.Dictionary) as Lang.ByteArray {
    return (
        StringUtil.convertEncodedString(reply["data"], {
            :fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64,
            :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
        }) as Lang.ByteArray
    );
}

function checkBlock(reply as Lang.Dictionary, offset as Lang.Number) as Lang.Number {
    Test.assertEqual("block", reply["op"]);
    Test.assertEqual(offset, reply["offset"]);
    var data = decode(reply);
    var size = data.size();
    Test.assert(size > 0 && size <= PhoneSync.BLOCK_BYTES);
    // Blocks never cross a storage chunk, so each read loads one chunk.
    Test.assert((offset % CHUNK_BYTES) + size <= CHUNK_BYTES);
    Test.assertEqual(offset % 256, data[0]);
    Test.assertEqual((offset + size - 1) % 256, data[size - 1]);
    return size;
}

(:test)
function phoneProtocolBasics(logger) {
    Application.Storage.clearValues();
    try {
        Test.assertEqual("pong", op(ask("ping", {})));
        Test.assertEqual("empty", op(ask("next", {})));
        Test.assert(ask("bogus", {}) == null);
        Test.assert(PhoneSync.reply({ "v" => 2, "rid" => "r", "op" => "ping" }) == null);
        Test.assert(PhoneSync.reply({ "v" => 1, "op" => "ping" }) == null);
        var reply = ask("ping", {}) as Lang.Dictionary;
        Test.assertEqual("r", reply["rid"]);
        Test.assertEqual(1, reply["v"]);
    } finally {
        Application.Storage.clearValues();
    }
    return true;
}

(:test)
function phoneSkipsUnsendableNotes(logger) {
    Application.Storage.clearValues();
    try {
        Application.Storage.setValue("notes", [
            storeNote("deleting", 10, "deleting"),
            storeNote("recording", 10, "recording"),
            storeNote("draft", 10, "draft"),
            { "id" => "empty", "state" => "interrupted", "bytes" => 0, "chunks" => 0 },
            storeNote("sent", 10, "saved"),
            storeNote("partial", 20, "interrupted")
        ]);
        Application.Storage.setValue("phone:sent", true);
        var offer = ask("next", {}) as Lang.Dictionary;
        Test.assertEqual("offer", offer["op"]);
        Test.assertEqual("partial", offer["id"]);
        Test.assertEqual(20, offer["bytes"]);
        Test.assertEqual("wav", offer["ext"]);
        Test.assertEqual("missing", op(ask("read", { "id" => "deleting", "offset" => 0 })));
        Test.assertEqual("missing", op(ask("read", { "id" => "recording", "offset" => 0 })));
        Test.assertEqual("missing", op(ask("saved", { "id" => "deleting", "bytes" => 10 })));
        Test.assertEqual("missing", op(ask("read", { "id" => "draft", "offset" => 0, "binary" => true })));
        Test.assertEqual("missing", op(ask("saved", { "id" => "draft", "bytes" => 10 })));
        Test.assert(Application.Storage.getValue("phone:draft") == null);
    } finally {
        Application.Storage.clearValues();
    }
    return true;
}

(:test)
function phoneReportsMissingAudio(logger) {
    Application.Storage.clearValues();
    try {
        var note = storeNote("gap", 3 * CHUNK_BYTES, "saved");
        Application.Storage.setValue("notes", [note]);
        Application.Storage.deleteValue("gap:1");
        Test.assertEqual("block", op(ask("read", { "id" => "gap", "offset" => 0 })));
        Test.assertEqual("missing", op(ask("read", { "id" => "gap", "offset" => CHUNK_BYTES })));
        Test.assertEqual("missing", op(ask("read", { "id" => "gap", "offset" => -1 })));
        Test.assertEqual("missing", op(ask("read", { "id" => "gap", "offset" => 3 * CHUNK_BYTES })));
        Test.assertEqual("missing", op(ask("read", { "id" => "gap", "offset" => "0" })));
        Test.assertEqual("missing", op(ask("read", { "id" => "gap" })));
        Test.assertEqual("missing", op(ask("read", { "id" => "nope", "offset" => 0 })));
        Test.assertEqual("missing", op(ask("read", { "offset" => 0 })));
        Test.assertEqual("missing", op(ask("saved", { "id" => "gap", "bytes" => 1 })));
        Test.assertEqual("gap", ask("saved", { "id" => "gap", "bytes" => 1 })["id"]);
        Test.assert(Application.Storage.getValue("phone:gap") == null);
    } finally {
        Application.Storage.clearValues();
    }
    return true;
}

(:test)
function phoneReportsFailure(logger) {
    Application.Storage.clearValues();
    try {
        // A damaged catalogue fails the lookup itself, which is not the same as a missing note.
        Application.Storage.setValue("notes", [{ "id" => "bad" }]);
        Test.assertEqual("error", op(ask("next", {})));
        Test.assertEqual("error", op(ask("read", { "id" => "bad", "offset" => 0 })));
    } finally {
        Application.Storage.clearValues();
    }
    return true;
}

(:test)
function phoneSendsLargeNote(logger) {
    Application.Storage.clearValues();
    try {
        Application.Storage.setValue("notes", [storeNote("big", LARGE_BYTES, "saved")]);
        var offer = ask("next", {}) as Lang.Dictionary;
        Test.assertEqual("offer", offer["op"]);
        Test.assertEqual(LARGE_BYTES, offer["bytes"]);

        var offset = 0;
        var blocks = 0;
        while (offset < LARGE_BYTES) {
            offset += checkBlock(ask("read", { "id" => "big", "offset" => offset }), offset);
            blocks++;
        }
        Test.assertEqual(LARGE_BYTES, offset);
        logger.debug("large note sent in " + blocks + " blocks");

        Test.assertEqual("confirmed", op(ask("saved", { "id" => "big", "bytes" => LARGE_BYTES })));
        Test.assertEqual("empty", op(ask("next", {})));
    } finally {
        Application.Storage.clearValues();
    }
    return true;
}

(:test)
function phoneResumesMidTransfer(logger) {
    Application.Storage.clearValues();
    try {
        Application.Storage.setValue("notes", [storeNote("resume", 3 * CHUNK_BYTES, "saved")]);
        var binary = ask("read", { "id" => "resume", "offset" => CHUNK_BYTES, "binary" => true });
        Test.assertEqual("block", op(binary));
        var data = binary["data"] as Lang.ByteArray;
        Test.assertEqual(CHUNK_BYTES, data.size());
        Test.assertEqual(0, data[0]);
        Test.assertEqual(255, data[CHUNK_BYTES - 1]);
        // Mid-block, near a chunk end, and inside a later chunk.
        Test.assertEqual(PhoneSync.BLOCK_BYTES, checkBlock(ask("read", { "id" => "resume", "offset" => 1000 }), 1000));
        Test.assertEqual(100, checkBlock(ask("read", { "id" => "resume", "offset" => 3996 }), 3996));
        Test.assertEqual(
            PhoneSync.BLOCK_BYTES,
            checkBlock(ask("read", { "id" => "resume", "offset" => 9001 }), 9001)
        );
        Test.assertEqual(1, checkBlock(ask("read", { "id" => "resume", "offset" => 12287 }), 12287));
    } finally {
        Application.Storage.clearValues();
    }
    return true;
}

(:test)
function phoneStatusTexts(logger) {
    var items = [{ "id" => "n", "bytes" => 2000 }];
    Test.assertEqual("Phone connected", PhoneStatus.text({ "op" => "pong" }, items));
    Test.assertEqual("Sent to phone", PhoneStatus.text({ "op" => "confirmed" }, items));
    Test.assertEqual("Note unavailable", PhoneStatus.text({ "op" => "missing" }, items));
    Test.assertEqual("Phone sync failed", PhoneStatus.text({ "op" => "error" }, items));
    Test.assertEqual(
        "To phone 50%",
        PhoneStatus.text({ "op" => "block", "id" => "n", "offset" => 1000 }, items)
    );
    Test.assert(PhoneStatus.text({ "op" => "block", "id" => "x", "offset" => 0 }, items) == null);
    Test.assert(PhoneStatus.text({ "op" => "offer" }, items) == null);
    return true;
}
