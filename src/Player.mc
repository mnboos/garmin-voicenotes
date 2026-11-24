import Toybox.Audio;
import Toybox.Lang;
import Toybox.WatchUi;

class NoteAudio extends Audio.Output.StreamingAudioSource {
    var store as Notes;
    var note as Lang.Dictionary;
    var index = 0;
    var offset = 0;
    var pending = null;
    var owner;
    function initialize(notes, selected, app) {
        store = notes; note = selected; owner = app;
        StreamingAudioSource.initialize({:format=>store.format(note), :bufferSize=>8192});
    }
    function onReadyForData(freeSpace as Lang.Number) as Void {
        while (freeSpace > 0 && index < note["chunks"]) {
            if (pending == null) { pending = store.read(note, index); }
            if (pending == null) { onError(Audio.Output.OUTPUT_ERROR_DECODING); end(); return; }
            var count = pending.size() - offset;
            if (count > freeSpace) { count = freeSpace; }
            var accepted = append(pending.slice(offset, offset + count));
            if (accepted == 0) { return; }
            offset += accepted;
            freeSpace -= accepted;
            if (offset == pending.size()) { index++; offset = 0; pending = null; }
        }
        if (index == note["chunks"]) { end(); }
    }
    function onError(error as Audio.Output.Error) as Void {
        owner.recorder.message = "Playback failed " + error;
        WatchUi.requestUpdate();
    }
}
