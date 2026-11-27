import Toybox.Audio;
import Toybox.Lang;

class DemoFixture {
    function save(store as Notes) as Lang.Dictionary {
        var format = {:containerFormat=>Audio.CONTAINER_WAV, :codec=>Audio.CODEC_LPCM,
            :frequency=>Audio.FREQ_8_KHZ, :channels=>Audio.CHANNEL_MONO};
        var note = store.create(format, "wav", "recording") as Lang.Dictionary;
        // Two seconds of 8 kHz, mono, signed 16-bit PCM with a standard RIFF header.
        var header = [82,73,70,70,36,125,0,0,87,65,86,69,102,109,116,32,16,0,0,0,
            1,0,1,0,64,31,0,0,128,62,0,0,2,0,16,0,100,97,116,97,0,125,0,0]b;
        try {
            store.append(note, header);
            var low = tone(20);
            var high = tone(16);
            var silence = new [160]b;
            for (var start = 0; start < 16000; start += 2000) {
                var pcm = new [0]b;
                var pitch = start < 8000 ? low : high;
                for (var i = start; i < start + 2000; i += 80) {
                    pcm.addAll(i % 4000 < 3200 ? pitch : silence);
                }
                store.append(note, pcm);
            }
            note["seconds"] = 2;
            note["state"] = "saved";
            store.save();
        } catch (e) {
            store.remove(note);
            throw e;
        }
        return note;
    }

    function tone(period as Lang.Number) as Lang.ByteArray {
        var pcm = new [0]b;
        for (var i = 0; i < 80; i++) {
            var sample = i % period < period / 2 ? 6000 : -6000;
            pcm.add(sample & 255);
            pcm.add((sample >> 8) & 255);
        }
        return pcm;
    }
}
