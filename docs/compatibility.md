# Compatibility and limits

Checked against Garmin's documentation on 23 November 2026.

The release manifest includes 29 Garmin product IDs. The D2 Mach 2 is excluded because the installed Connect IQ SDK lacks its device profile. The D2 Mach 2 Pro has its own profile and is included.

- Requires Connect IQ API 6.0.3 and the `AudioInput`, `AudioOutput`, `Communications`, and `Background` permissions.
- Targets Garmin's documented Audio device families. Shared Garmin product IDs also cover related tactix, quatix, and D2 models.
- Having a microphone does not guarantee API access. Older microphone devices absent from Garmin's Audio support list cannot be supported by adding their IDs.
- Some devices in Garmin's Audio list may only support output. The app checks capture-format support before recording and reports unavailable capture.
- Ogg/Opus mono at 16 kHz is preferred. WAV/LPCM mono at 8 kHz is the fallback.
- Recordings are limited by duration, not size. The maximum length is a setting (10 s to 30 min, or no limit; default 1 min), with an optional vibration 10 seconds before the end. The watch's own app storage limit, which Garmin varies by device (often around 128 KB), is the practical ceiling: when it is reached, recording stops early.
- Up to 40 notes. When the watch's storage is full, capture stops, earlier chunks are kept, and the note is labelled partial. Delete uploaded notes to free space.
- Audio is written in 4 KB chunks. Interrupted recordings are labelled partial.
- The app only captures in the foreground. The background service only uploads saved recordings.
- Automatic deferred uploads run while the app is open, retrying with a delay of 30 seconds up to five minutes. After closing the app, a background job requests five-minute intervals. Garmin controls actual scheduling and can terminate jobs to free memory.
- Background jobs save a progress marker after each acknowledged chunk, work on one note per invocation, and stop starting requests after 20 seconds to respect Garmin's 30-second job limit. An interrupted request is safely repeated later.
- Networking uses Garmin's normal web-request transport. There is no explicit LTE-session activation or custom phone companion in this version; Wi-Fi/LTE availability must be verified per device.
- Uploads are serial. Recording and playback wait for an active upload to finish. Notes are never automatically deleted.
- The receiver is for one owner. It accepts notes up to 40 MB and 10,000 chunks and total stored files to approximately 1 GB. It retains uploaded chunks to support safe retries; monitor disk use and archive complete note folders as needed.

Garmin's firmware may have capture/playback issues. A successful build does not prove working audio on a watch. The receiver keeps the original encoded stream, including any firmware-produced header or duration problems.

Sources:

- [Audio and device support](https://developer.garmin.com/connect-iq/api-docs/Toybox/Audio.html)
- [Capture API](https://developer.garmin.com/connect-iq/api-docs/Toybox/Audio/Capture.html)
- [Streaming playback](https://developer.garmin.com/connect-iq/api-docs/Toybox/Audio/Output/StreamingAudioSource.html)
- [Persistent storage limits](https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/Storage.html)
- [Web requests](https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications.html)
