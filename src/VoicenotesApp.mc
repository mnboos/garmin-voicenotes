import Toybox.Application;
import Toybox.Audio;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Timer;
import Toybox.WatchUi;

(:background)
class VoicenotesApp extends Application.AppBase {
    var notes as Notes? = null;
    var recorder as Recorder? = null;
    var upload as Upload? = null;
    var browsingNotes = false;
    var timer;
    var player = null;
    var phoneMessage = "";
    var phoneSyncActive = false;
    (:simulatorTest)
    var simulatorTest as SimulatorTest? = null;
    var autoStartPending = false;
    function initialize() {
        AppBase.initialize();
    }
    function getInitialView() {
        Background.deleteTemporalEvent();
        Background.deletePhoneAppMessageEvent();
        notes = new Notes();
        recorder = new Recorder(notes);
        upload = new Upload(notes);
        if (self has :startSimulatorTest) {
            startSimulatorTest();
        }
        if (self has :startPhoneSync) {
            startPhoneSync();
        }
        timer = new Timer.Timer();
        timer.start(method(:tick), 1000, true);
        if (self has :saveDemoNote) {
            recorder.message = "START saves sample";
        } else {
            autoStartPending = Application.Properties.getValue("autoRecord") == true;
        }
        return [new HomeView(self), new HomeDelegate(self)];
    }
    (:companion)
    function startPhoneSync() as Void {
        phoneSyncActive = PhoneSync.enabled();
        if (!phoneSyncActive) {
            return;
        }
        Communications.registerForPhoneAppMessages(method(:onPhoneMessage));
        // Wake the companion before its next poll.
        phoneMessage = "Phone: waiting";
        try {
            Communications.transmit({ "v" => 1, "op" => "sync" }, null, new PhoneHello(self));
        } catch (e) {
            phoneMessage = "Phone: link failed";
        }
    }
    (:companion)
    function phoneLink(ok as Lang.Boolean) as Void {
        // A late result must not replace newer transfer progress.
        if ("Phone: waiting".equals(phoneMessage)) {
            showPhoneStatus(ok ? "Phone: link OK" : "Phone: link failed");
        }
    }
    (:companion)
    function showPhoneStatus(text as Lang.String) as Void {
        if (isIdle()) {
            // An old upload result would otherwise hide the phone status.
            upload.message = "";
            phoneMessage = text;
            WatchUi.requestUpdate();
        }
    }
    (:companion)
    function stopPhoneSync() as Void {
        if (PhoneSync.enabled()) {
            Background.registerForPhoneAppMessageEvent();
        }
    }
    // Applies a change to the companion sync setting while the app is open.
    (:companion)
    function phoneSyncChanged() as Void {
        if (PhoneSync.enabled()) {
            startPhoneSync();
        } else {
            Communications.registerForPhoneAppMessages(null);
            phoneMessage = "";
            phoneSyncActive = false;
        }
    }
    (:companion)
    function onPhoneMessage(message as Communications.PhoneAppMessage) as Void {
        var request = message.data;
        if (!(request instanceof Lang.Dictionary)) {
            return;
        }
        try {
            var response = PhoneSync.reply(request);
            if (response != null) {
                Communications.transmit(response, null, new PhoneReply(false));
                var status = PhoneStatus.text(response, notes.items);
                if (status != null) {
                    showPhoneStatus(status);
                }
            }
        } catch (e) {
            showPhoneStatus("Phone sync failed");
        }
    }
    (:companion)
    function syncNow() {
        try {
            Communications.transmit({ "v" => 1, "op" => "sync" }, null, new PhoneReply(false));
            phoneMessage = "Open Android inbox";
        } catch (e) {
            phoneMessage = "Phone unavailable";
        }
    }
    (:simulatorFixture)
    function saveDemoNote() {
        try {
            (new DemoFixture()).save(notes);
            phoneMessage = "Sample saved";
        } catch (e) {
            phoneMessage = "Could not save sample";
        }
    }
    (:simulatorTest)
    function startSimulatorTest() as Void {
        simulatorTest = new SimulatorTest(notes);
    }
    (:simulatorTest)
    function tickSimulatorTest() as Void {
        simulatorTest.tick(notes);
    }
    (:simulatorTest)
    function stopSimulatorTest() as Void {
        simulatorTest.stop();
    }
    function tick() as Void {
        if (self has :tickSimulatorTest) {
            tickSimulatorTest();
        }
        recorder.tick();
        if (
            !recorder.active &&
            recorder.startTimer == null &&
            !recorder.awaitingDecision &&
            player == null &&
            !browsingNotes
        ) {
            upload.tick();
        }
        WatchUi.requestUpdate();
    }
    function onStop(state) {
        if (recorder == null) {
            return;
        }
        timer.stop();
        recorder.shutdown();
        Audio.Output.stop();
        if (self has :stopPhoneSync) {
            stopPhoneSync();
        }
        if (self has :stopSimulatorTest) {
            stopSimulatorTest();
        }
        if (upload.needsBackground()) {
            Background.registerForTemporalEvent(new Time.Duration(300));
        }
    }
    (:companion)
    function onSettingsChanged() as Void {
        if (phoneSyncActive != PhoneSync.enabled()) {
            phoneSyncChanged();
            WatchUi.requestUpdate();
        }
    }
    function getServiceDelegate() {
        return [new BackgroundUpload()];
    }
    function onBackgroundData(data) as Void {
        if (notes != null) {
            WatchUi.requestUpdate();
        }
    }
    function play(note) {
        if (recorder.active || upload.busy) {
            return;
        }
        phoneMessage = "";
        try {
            Audio.Output.stop();
            player = new NoteAudio(notes, note, self);
            Audio.Output.registerStateChangeHandler(method(:playbackState));
            Audio.Output.play(player, null);
            recorder.message = "Playing note";
        } catch (e) {
            player = null;
            recorder.message = "Playback unavailable";
        }
    }
    function playbackState(state as Audio.Output.PlaybackState) as Void {
        if (state == Audio.Output.PLAYBACK_STOPPED || state == Audio.Output.PLAYBACK_ERROR) {
            player = null;
            recorder.message =
                state == Audio.Output.PLAYBACK_ERROR ? "Playback failed" : "Playback finished";
        }
        WatchUi.requestUpdate();
    }
    function stopPlayback() {
        Audio.Output.stop();
        player = null;
    }
    function isIdle() {
        return (
            !recorder.active &&
            recorder.startTimer == null &&
            !recorder.awaitingDecision &&
            player == null &&
            !upload.busy
        );
    }
    function autoStart() {
        if (!autoStartPending) {
            return;
        }
        autoStartPending = false;
        if (isIdle()) {
            phoneMessage = "";
            recorder.start();
        }
    }
    function showSettings() {
        var menu = new WatchUi.Menu2({ :title => "Settings" });
        menu.addItem(
            new WatchUi.ToggleMenuItem(
                "Auto-record",
                "Start when app opens",
                "autoRecord",
                Application.Properties.getValue("autoRecord") == true,
                null
            )
        );
        addSettingToggle(menu, "Vibrate at start", "vibrateOnRecord", false);
        addSettingToggle(menu, "Vibrate at end", "vibrateOnStop", false);
        addSettingToggle(menu, "Sound at start", "soundOnStart", false);
        addSettingToggle(menu, "Sound at end", "soundOnStop", false);
        addSettingToggle(menu, "Auto-save", "autoSave", true);
        menu.addItem(
            new WatchUi.MenuItem("Max length", lengthLabel(maxSeconds()), "maxSeconds", null)
        );
        menu.addItem(
            new WatchUi.ToggleMenuItem(
                "Warn before end",
                "Vibrate 10 s before limit",
                "warnBeforeEnd",
                Application.Properties.getValue("warnBeforeEnd") != false,
                null
            )
        );
        if (self has :phoneSyncChanged) {
            menu.addItem(
                new WatchUi.ToggleMenuItem(
                    "Phone sync",
                    "Send notes to Android",
                    "phoneSync",
                    phoneSyncActive,
                    null
                )
            );
        }
        WatchUi.pushView(menu, new SettingsDelegate(self), WatchUi.SLIDE_UP);
    }
    function addSettingToggle(menu, label, key, enabledByDefault) {
        var value = Application.Properties.getValue(key);
        menu.addItem(
            new WatchUi.ToggleMenuItem(
                label,
                null,
                key,
                enabledByDefault ? value != false : value == true,
                null
            )
        );
    }
    const LENGTHS = [10, 30, 60, 120, 300, 600, 1800, 0];
    function maxSeconds() as Lang.Number {
        var value = Application.Properties.getValue("maxSeconds");
        return value instanceof Lang.Number && value > 0 ? value : 0;
    }
    function lengthLabel(seconds) as Lang.String {
        if (seconds <= 0) {
            return "No limit";
        }
        if (seconds < 60) {
            return seconds + " s";
        }
        return seconds / 60 + " min";
    }
    function showLengths(parent as WatchUi.MenuItem) {
        var menu = new WatchUi.Menu2({
            :title => "Max length",
            :focus => LENGTHS.indexOf(maxSeconds()) < 0 ? 0 : LENGTHS.indexOf(maxSeconds())
        });
        for (var i = 0; i < LENGTHS.size(); i++) {
            menu.addItem(new WatchUi.MenuItem(lengthLabel(LENGTHS[i]), null, LENGTHS[i], null));
        }
        WatchUi.pushView(menu, new LengthDelegate(self, parent), WatchUi.SLIDE_UP);
    }
    function toggle() {
        if (player != null) {
            stopPlayback();
            return;
        }
        if (recorder.awaitingDecision) {
            recorder.resolveDraft(true);
        } else if (recorder.active || recorder.startTimer != null) {
            recorder.stop();
        } else if (!upload.busy) {
            upload.message = "";
            phoneMessage = "";
            recorder.start();
        }
    }
    function showNotes() {
        if (!isIdle()) {
            return;
        }
        var menu = new WatchUi.Menu2({ :title => "Saved notes" });
        if (self has :syncNow && phoneSyncActive) {
            menu.addItem(new WatchUi.MenuItem("Sync now", null, "sync", null));
        }
        if (self has :saveDemoNote) {
            menu.addItem(new WatchUi.MenuItem("Save sample WAV", null, "sample", null));
        }
        var hasNotes = false;
        for (var i = notes.items.size() - 1; i >= 0; i--) {
            var n = notes.items[i] as Lang.Dictionary;
            if ("deleting".equals(n["state"])) {
                continue;
            }
            hasNotes = true;
            menu.addItem(
                new WatchUi.MenuItem(
                    noteTitle(n),
                    noteStatus(n) + " · " + n["seconds"] + "s",
                    n["id"],
                    null
                )
            );
        }
        if (!hasNotes) {
            menu.addItem(new WatchUi.MenuItem("No notes yet", null, "empty", null));
        }
        menu.addItem(new WatchUi.MenuItem("Settings", "Recording options", "settings", null));
        browsingNotes = true;
        WatchUi.pushView(menu, new NotesDelegate(self, menu), WatchUi.SLIDE_UP);
    }
    function noteTitle(n as Lang.Dictionary) as Lang.String {
        var date = Gregorian.info(new Time.Moment(n["created"]), Time.FORMAT_SHORT);
        return (
            date.day +
            "/" +
            date.month +
            " " +
            date.hour.format("%02d") +
            ":" +
            date.min.format("%02d")
        );
    }
    function noteStatus(n as Lang.Dictionary) as Lang.String {
        var status = upload.status(n);
        if (
            status.equals("On watch") &&
            self has :syncNow &&
            Application.Storage.getValue("phone:" + n["id"]) == true
        ) {
            status = "On phone";
        }
        if (n["state"] == "interrupted" && n["bytes"] > 0) {
            return "Partial / " + status;
        }
        return status;
    }
    // depth: views to pop, including the confirmation
    function confirmDelete(note as Lang.Dictionary, list as WatchUi.Menu2, depth as Lang.Number) {
        if (upload.busy || recorder.active) {
            return;
        }
        if (player != null) {
            stopPlayback();
        }
        var menu = new WatchUi.Menu2({ :title => "Delete note?" });
        menu.addItem(new WatchUi.MenuItem("Keep note", null, "keep", null));
        menu.addItem(new WatchUi.MenuItem("Delete permanently", null, "confirm", null));
        WatchUi.pushView(menu, new DeleteDelegate(self, note, list, depth), WatchUi.SLIDE_UP);
    }
}

class HomeView extends WatchUi.View {
    var app as VoicenotesApp;
    var startButton as Lang.Array;
    function initialize(owner) {
        View.initialize();
        app = owner;
        startButton = WatchUi.loadResource(Rez.JsonData.StartButton) as Lang.Array;
    }
    function onShow() {
        app.autoStart();
    }
    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        dc.drawText(
            w / 2,
            h * 0.14,
            Graphics.FONT_SMALL,
            "Voicenotes",
            Graphics.TEXT_JUSTIFY_CENTER
        );
        if (app.recorder.awaitingDecision) {
            dc.drawText(
                w / 2,
                h * 0.32,
                Graphics.FONT_XTINY,
                app.recorder.message,
                Graphics.TEXT_JUSTIFY_CENTER
            );
            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                w / 2,
                h * 0.48,
                Graphics.FONT_SMALL,
                "Start: Save",
                Graphics.TEXT_JUSTIFY_CENTER
            );
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                w / 2,
                h * 0.66,
                Graphics.FONT_SMALL,
                "Back: Delete",
                Graphics.TEXT_JUSTIFY_CENTER
            );
            drawButtonHint(dc);
            return;
        }
        dc.setColor(
            app.recorder.active ? Graphics.COLOR_RED : Graphics.COLOR_LT_GRAY,
            Graphics.COLOR_BLACK
        );
        dc.fillCircle(w / 2, h * 0.43, w * 0.13);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        if (app.recorder.active || app.player != null) {
            dc.fillRectangle(w / 2 - w * 0.045, h * 0.43 - w * 0.045, w * 0.09, w * 0.09);
        } else {
            dc.fillRoundedRectangle(w / 2 - w * 0.025, h * 0.43 - w * 0.065, w * 0.05, w * 0.09, 4);
            dc.setPenWidth(2);
            dc.drawLine(w / 2, h * 0.43, w / 2, h * 0.43 + w * 0.07);
            dc.drawLine(
                w / 2 - w * 0.035,
                h * 0.43 + w * 0.07,
                w / 2 + w * 0.035,
                h * 0.43 + w * 0.07
            );
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var status = app.notes.items.size() + " notes";
        if (app.recorder.active) {
            status =
                app.recorder.note["seconds"] +
                (app.recorder.limit > 0 ? " / " + app.recorder.limit + " s" : " seconds");
        }
        dc.drawText(w / 2, h * 0.59, Graphics.FONT_SMALL, status, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(
            w / 2,
            h * 0.7,
            Graphics.FONT_XTINY,
            statusMessage(),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        drawButtonHint(dc);
        if (app.isIdle()) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            for (var row = 0; row < 3; row++) {
                var y = h * 0.84 + row * 5;
                dc.drawLine(w / 2 - 10, y, w / 2 + 10, y);
            }
        }
    }
    function statusMessage() {
        if (
            !app.recorder.active &&
            app.recorder.startTimer == null &&
            app.upload.message.length() > 0
        ) {
            return app.upload.message;
        }
        if (app.isIdle() && app.phoneMessage.length() > 0) {
            return app.phoneMessage;
        }
        return app.recorder.message;
    }
    function drawButtonHint(dc) {
        var centerX = dc.getWidth() / 2.0;
        var centerY = dc.getHeight() / 2.0;
        var angle;
        if (startButton.size() == 1) {
            angle = (startButton[0].toFloat() * Math.PI) / 180.0;
        } else {
            var buttonX;
            var buttonY;
            if (startButton.size() == 2) {
                buttonX = startButton[0];
                buttonY = startButton[1];
            } else {
                if (!(Rez.Styles.system_loc__hint_button_right_top has :x)) {
                    return;
                }
                buttonX = Rez.Styles.system_loc__hint_button_right_top.x;
                buttonY = Rez.Styles.system_loc__hint_button_right_top.y + 18;
            }
            angle = Math.atan2(centerY - buttonY, buttonX - centerX);
        }
        var slope = -Math.tan(angle);
        var x = dc.getWidth() - 24;
        var y = centerY + (x - centerX) * slope;
        var stopping = app.recorder.active || app.recorder.startTimer != null || app.player != null;
        dc.setColor(
            app.recorder.awaitingDecision
                ? Graphics.COLOR_GREEN
                : app.upload.busy || app.recorder.finishing
                  ? Graphics.COLOR_DK_GRAY
                  : Graphics.COLOR_RED,
            Graphics.COLOR_TRANSPARENT
        );
        var strokeWidth = 4;
        dc.setPenWidth(strokeWidth);
        if (System.getDeviceSettings().screenShape == System.SCREEN_SHAPE_ROUND) {
            var degrees = (angle * 180.0) / Math.PI;
            var radius = centerX - strokeWidth / 2;
            dc.drawArc(
                centerX,
                centerY,
                radius,
                Graphics.ARC_COUNTER_CLOCKWISE,
                degrees - 5,
                degrees + 5
            );
            x = centerX + (radius - 19) * Math.cos(angle);
            y = centerY - (radius - 19) * Math.sin(angle);
        } else {
            var edge = dc.getWidth() - strokeWidth / 2;
            var edgeY = centerY + (edge - centerX) * slope;
            dc.drawLine(edge, edgeY - 16, edge, edgeY + 16);
        }
        if (app.recorder.awaitingDecision) {
            dc.drawLine(x - 7, y, x - 2, y + 5);
            dc.drawLine(x - 2, y + 5, x + 7, y - 5);
        } else if (stopping) {
            dc.fillRectangle(x - 7, y - 7, 14, 14);
        } else {
            dc.fillCircle(x, y, 7);
        }
        dc.setPenWidth(2);
    }
}
class HomeDelegate extends WatchUi.BehaviorDelegate {
    var app;
    function initialize(owner) {
        BehaviorDelegate.initialize();
        app = owner;
    }
    function onSelect() {
        if (app has :saveDemoNote) {
            app.saveDemoNote();
        } else {
            app.toggle();
        }
        return true;
    }
    function onMenu() {
        app.showNotes();
        return true;
    }
    function onNextPage() {
        app.showNotes();
        return true;
    }
    function onTap(event) {
        var point = event.getCoordinates();
        var height = System.getDeviceSettings().screenHeight;
        if (app.recorder.awaitingDecision) {
            if (point[1] >= height * 0.45 && point[1] < height * 0.62) {
                app.toggle();
            } else if (point[1] >= height * 0.63 && point[1] < height * 0.81) {
                app.recorder.resolveDraft(false);
            }
        } else if (point[1] > height * 0.72) {
            app.showNotes();
        } else {
            app.toggle();
        }
        return true;
    }
    function onBack() {
        if (app.recorder.awaitingDecision) {
            app.recorder.resolveDraft(false);
            return true;
        }
        if (app.recorder.active || app.recorder.startTimer != null) {
            app.recorder.stop();
            return true;
        }
        if (app.player != null) {
            app.stopPlayback();
            return true;
        }
        return false;
    }
}
class LengthDelegate extends WatchUi.Menu2InputDelegate {
    var app;
    var parent;
    function initialize(owner, item) {
        Menu2InputDelegate.initialize();
        app = owner;
        parent = item;
    }
    function onSelect(item) {
        Application.Properties.setValue("maxSeconds", item.getId() as Lang.Number);
        parent.setSubLabel(app.lengthLabel(item.getId()));
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
class SettingsDelegate extends WatchUi.Menu2InputDelegate {
    var app;
    function initialize(owner) {
        Menu2InputDelegate.initialize();
        app = owner;
    }
    function onSelect(item) {
        if (item.getId().equals("maxSeconds")) {
            app.showLengths(item as WatchUi.MenuItem);
            return;
        }
        if (item instanceof WatchUi.ToggleMenuItem) {
            Application.Properties.setValue(item.getId() as Lang.String, item.isEnabled());
            if (item.getId().equals("phoneSync") && app has :phoneSyncChanged) {
                app.phoneSyncChanged();
            }
        }
    }
}
class NotesDelegate extends WatchUi.Menu2InputDelegate {
    var app as VoicenotesApp;
    var list as WatchUi.Menu2;
    function initialize(owner, menu) {
        Menu2InputDelegate.initialize();
        app = owner;
        list = menu;
    }
    function onBack() {
        app.browsingNotes = false;
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
    function onSelect(item) {
        var id = item.getId();
        if (id.equals("sync") && app has :syncNow) {
            app.syncNow();
            app.browsingNotes = false;
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return;
        }
        if (id.equals("sample") && app has :saveDemoNote) {
            app.saveDemoNote();
            app.browsingNotes = false;
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return;
        }
        if (id.equals("settings")) {
            app.showSettings();
            return;
        }
        for (var i = 0; i < app.notes.items.size(); i++) {
            var note = app.notes.items[i] as Lang.Dictionary;
            if (note["id"].equals(id)) {
                WatchUi.pushView(
                    new NoteView(app, note),
                    new NoteDelegate(app, note, list),
                    WatchUi.SLIDE_LEFT
                );
                return;
            }
        }
    }
}

class NoteView extends WatchUi.View {
    var app as VoicenotesApp;
    var note as Lang.Dictionary;
    function initialize(owner, selected) {
        View.initialize();
        app = owner;
        note = selected;
    }
    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        dc.drawText(
            w / 2,
            h * 0.14,
            Graphics.FONT_SMALL,
            app.noteTitle(note),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            w / 2,
            h * 0.27,
            Graphics.FONT_XTINY,
            app.noteStatus(note) + " · " + note["seconds"] + "s",
            Graphics.TEXT_JUSTIFY_CENTER
        );
        var playing = app.player != null;
        var cy = h * 0.48;
        var r = w * 0.12;
        dc.setColor(playing ? Graphics.COLOR_GREEN : Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.fillCircle(w / 2, cy, r);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        if (playing) {
            dc.fillRectangle(w / 2 - r * 0.35, cy - r * 0.35, r * 0.7, r * 0.7);
        } else {
            dc.fillPolygon([
                [w / 2 - r * 0.3, cy - r * 0.45],
                [w / 2 - r * 0.3, cy + r * 0.45],
                [w / 2 + r * 0.45, cy]
            ]);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var msg = app.upload.message.length() > 0 ? app.upload.message : app.recorder.message;
        dc.drawText(w / 2, h * 0.66, Graphics.FONT_XTINY, msg, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        var hint = System.getDeviceSettings().isTouchScreen
            ? "Swipe left to delete"
            : "MENU: resync / delete";
        dc.drawText(w / 2, h * 0.78, Graphics.FONT_XTINY, hint, Graphics.TEXT_JUSTIFY_CENTER);
    }
}
class NoteDelegate extends WatchUi.BehaviorDelegate {
    var app;
    var note;
    var list;
    function initialize(owner, selected, menu) {
        BehaviorDelegate.initialize();
        app = owner;
        note = selected;
        list = menu;
    }
    function togglePlay() {
        if (app.player != null) {
            app.stopPlayback();
        } else if (!app.upload.busy) {
            app.upload.message = "";
            app.play(note);
        }
        WatchUi.requestUpdate();
    }
    function onSelect() {
        togglePlay();
        return true;
    }
    function onTap(event) {
        togglePlay();
        return true;
    }
    function onSwipe(event) {
        if (event.getDirection() == WatchUi.SWIPE_LEFT) {
            app.confirmDelete(note, list, 2);
            return true;
        }
        return false;
    }
    function onMenu() {
        showActions();
        return true;
    }
    function onNextPage() {
        showActions();
        return true;
    }
    function onBack() {
        if (app.player != null) {
            app.stopPlayback();
        }
        return false;
    }
    function showActions() {
        if (app.recorder.active) {
            return;
        }
        var menu = new WatchUi.Menu2({ :title => "Note" });
        menu.addItem(
            new WatchUi.MenuItem(app.player != null ? "Stop" : "Play", null, "play", null)
        );
        menu.addItem(new WatchUi.MenuItem("Resync", "Send to all targets", "resync", null));
        menu.addItem(new WatchUi.MenuItem("Delete", "Remove from watch", "delete", null));
        WatchUi.pushView(menu, new ActionsDelegate(app, note, list), WatchUi.SLIDE_UP);
    }
}
class ActionsDelegate extends WatchUi.Menu2InputDelegate {
    var app;
    var note;
    var list;
    function initialize(owner, selected, menu) {
        Menu2InputDelegate.initialize();
        app = owner;
        note = selected;
        list = menu;
    }
    function onSelect(item) {
        var id = item.getId();
        if (id.equals("delete")) {
            app.confirmDelete(note, list, 3);
            return;
        }
        if (id.equals("play")) {
            if (app.player != null) {
                app.stopPlayback();
            } else if (!app.upload.busy) {
                app.play(note);
            }
        }
        if (id.equals("resync") && !app.upload.busy && app.player == null) {
            try {
                app.upload.resync(note);
            } catch (e) {
                app.upload.message = "Could not queue sync";
            }
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
class DeleteDelegate extends WatchUi.Menu2InputDelegate {
    var app as VoicenotesApp;
    var note as Lang.Dictionary;
    var list as WatchUi.Menu2;
    var depth as Lang.Number;
    function initialize(owner, selected, menu, count) {
        Menu2InputDelegate.initialize();
        app = owner;
        note = selected;
        list = menu;
        depth = count;
    }
    function onSelect(item) {
        if (!item.getId().equals("confirm") || !app.isIdle()) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return;
        }
        app.phoneMessage = "";
        try {
            app.notes.remove(note);
            app.upload.message = "";
            app.recorder.message = "Deleted";
            var index = list.findItemById(note["id"]);
            if (index >= 0) {
                list.deleteItem(index);
            }
        } catch (e) {
            app.recorder.message = "Delete failed";
        }
        for (var i = 0; i < depth; i++) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
    }
}
