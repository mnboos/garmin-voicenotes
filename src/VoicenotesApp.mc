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
    var notes as Notes or Null = null;
    var recorder as Recorder or Null = null;
    var upload as Upload or Null = null;
    var timer;
    var player = null;
    var phoneMessage = "";
    (:simulatorTest)
    var simulatorTest as SimulatorTest or Null = null;
    function initialize() {
        AppBase.initialize();
    }
    function getInitialView() {
        Background.deleteTemporalEvent();
        Background.deletePhoneAppMessageEvent();
        notes = new Notes();
        recorder = new Recorder(notes);
        if (self has :saveDemoNote) { recorder.message = "START saves sample"; }
        upload = new Upload(notes);
        if (self has :startSimulatorTest) { startSimulatorTest(); }
        if (self has :startPhoneSync) { startPhoneSync(); }
        timer = new Timer.Timer();
        timer.start(method(:tick), 1000, true);
        return [new HomeView(self), new HomeDelegate(self)];
    }
    (:companion)
    function startPhoneSync() as Void {
        Communications.registerForPhoneAppMessages(method(:onPhoneMessage));
    }
    (:companion)
    function stopPhoneSync() as Void {
        Background.registerForPhoneAppMessageEvent();
    }
    (:companion)
    function onPhoneMessage(message as Communications.PhoneAppMessage) as Void {
        var request = message.data;
        if (!(request instanceof Lang.Dictionary)) { return; }
        try {
            var response = PhoneSync.reply(request);
            if (response != null) {
                Communications.transmit(response, null, new PhoneReply(false));
                if ("confirmed".equals(response["op"])) { phoneMessage = "On phone"; }
            }
        } catch (e) { phoneMessage = "Phone sync failed"; }
    }
    (:companion)
    function syncNow() {
        try {
            Communications.transmit({"v"=>1, "op"=>"sync"}, null, new PhoneReply(false));
            phoneMessage = "Open Android inbox";
        } catch (e) { phoneMessage = "Phone unavailable"; }
    }
    (:simulatorFixture)
    function saveDemoNote() {
        try {
            new DemoFixture().save(notes);
            phoneMessage = "Sample saved";
        } catch (e) { phoneMessage = "Could not save sample"; }
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
        if (self has :tickSimulatorTest) { tickSimulatorTest(); }
        recorder.tick();
        if (!recorder.active && player == null) { upload.tick(); }
        WatchUi.requestUpdate();
    }
    function onStop(state) {
        if (recorder == null) { return; }
        timer.stop();
        recorder.stop();
        Audio.Output.stop();
        if (self has :stopPhoneSync) { stopPhoneSync(); }
        if (self has :stopSimulatorTest) { stopSimulatorTest(); }
        if (Application.Properties.getValue("autoUpload")) {
            Background.registerForTemporalEvent(new Time.Duration(300));
        }
    }
    function getServiceDelegate() { return [new BackgroundUpload()]; }
    function onBackgroundData(data) as Void {
        if (notes != null) { notes.refreshUploads(); WatchUi.requestUpdate(); }
    }
    function play(note) {
        if (recorder.active || upload.busy) { return; }
        phoneMessage = "";
        try {
            Audio.Output.stop();
            player = new NoteAudio(notes, note, self);
            Audio.Output.registerStateChangeHandler(method(:playbackState));
            Audio.Output.play(player, null);
            recorder.message = "Playing note";
        } catch (e) { player = null; recorder.message = "Playback unavailable"; }
    }
    function playbackState(state as Audio.Output.PlaybackState) as Void {
        if (state == Audio.Output.PLAYBACK_STOPPED || state == Audio.Output.PLAYBACK_ERROR) {
            player = null;
            recorder.message = state == Audio.Output.PLAYBACK_ERROR ? "Playback failed" : "Playback finished";
        }
        WatchUi.requestUpdate();
    }
    function stopPlayback() {
        Audio.Output.stop();
        player = null;
    }
    function isIdle() {
        return !recorder.active && player == null && !upload.busy;
    }
    function toggle() {
        if (player != null) { stopPlayback(); return; }
        if (recorder.active) { recorder.stop(); }
        else if (!upload.busy) { upload.message = ""; phoneMessage = ""; recorder.start(); }
    }
    function showNotes() {
        if (!isIdle()) { return; }
        var menu = new WatchUi.Menu2({:title=>"Saved notes"});
        menu.addItem(new WatchUi.ToggleMenuItem("Save location", null, "location", recorder.savesLocation(), null));
        if (self has :syncNow) {
            menu.addItem(new WatchUi.MenuItem("Sync now", null, "sync", null));
        }
        if (self has :saveDemoNote) {
            menu.addItem(new WatchUi.MenuItem("Save sample WAV", null, "sample", null));
        }
        for (var i = notes.items.size()-1; i >= 0; i--) {
            var n = notes.items[i] as Lang.Dictionary;
            if ("deleting".equals(n["state"])) { continue; }
            var date = Gregorian.info(new Time.Moment(n["created"]), Time.FORMAT_SHORT);
            var title = date.day + "/" + date.month + " " + date.hour.format("%02d") + ":" + date.min.format("%02d");
            var subtitle = n["uploaded"] ? "Uploaded" : "On watch";
            if ("interrupted".equals(n["state"])) { subtitle = "Partial / interrupted"; }
            if ((self has :syncNow) && Application.Storage.getValue("phone:" + n["id"]) == true) { subtitle = "On phone"; }
            menu.addItem(new WatchUi.MenuItem(title, subtitle + " · " + n["seconds"] + "s", n["id"], null));
        }
        if (notes.items.size() == 0) { menu.addItem(new WatchUi.MenuItem("No notes yet", null, "empty", null)); }
        WatchUi.pushView(menu, new NotesDelegate(self), WatchUi.SLIDE_UP);
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
    function onUpdate(dc) {
        var w = dc.getWidth(); var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK); dc.clear();
        dc.drawText(w/2, h*0.14, Graphics.FONT_SMALL, "Voicenotes", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(app.recorder.active ? Graphics.COLOR_RED : Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.fillCircle(w/2, h*0.43, w*0.13);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        if (app.recorder.active || app.player != null) {
            dc.fillRectangle(w/2-w*0.045, h*0.43-w*0.045, w*0.09, w*0.09);
        } else {
            dc.fillRoundedRectangle(w/2-w*0.025, h*0.43-w*0.065, w*0.05, w*0.09, 4);
            dc.setPenWidth(2);
            dc.drawLine(w/2, h*0.43, w/2, h*0.43+w*0.07);
            dc.drawLine(w/2-w*0.035, h*0.43+w*0.07, w/2+w*0.035, h*0.43+w*0.07);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var status = app.recorder.active ? app.recorder.note["seconds"] + " seconds" : app.notes.items.size() + " notes";
        dc.drawText(w/2, h*0.59, Graphics.FONT_SMALL, status, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w/2, h*0.70, Graphics.FONT_XTINY, statusMessage(), Graphics.TEXT_JUSTIFY_CENTER);
        drawButtonHint(dc);
        if (app.isIdle()) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            for (var row = 0; row < 3; row++) {
                var y = h*0.84 + row*5;
                dc.drawLine(w/2-10, y, w/2+10, y);
            }
        }
    }
    function statusMessage() {
        if (!app.recorder.active && app.upload.message.length() > 0) { return app.upload.message; }
        if (app.isIdle() && app.phoneMessage.length() > 0) { return app.phoneMessage; }
        return app.recorder.message;
    }
    function drawButtonHint(dc) {
        var centerX = dc.getWidth() / 2.0;
        var centerY = dc.getHeight() / 2.0;
        var buttonX;
        var buttonY;
        if (startButton.size() == 2) {
            buttonX = startButton[0];
            buttonY = startButton[1];
        } else {
            if (!(Rez.Styles.system_loc__hint_button_right_top has :x)) { return; }
            buttonX = Rez.Styles.system_loc__hint_button_right_top.x;
            buttonY = Rez.Styles.system_loc__hint_button_right_top.y + 18;
        }
        var x = dc.getWidth() - 24;
        var slope = (buttonY - centerY) / (buttonX - centerX);
        var y = centerY + (x - centerX) * slope;
        var stopping = app.recorder.active || app.player != null;
        dc.setColor(app.upload.busy || app.recorder.finishing ? Graphics.COLOR_DK_GRAY : Graphics.COLOR_RED,
            Graphics.COLOR_TRANSPARENT);
        var strokeWidth = 4;
        dc.setPenWidth(strokeWidth);
        if (System.getDeviceSettings().screenShape == System.SCREEN_SHAPE_ROUND) {
            var angle = Math.atan2(centerY - buttonY, buttonX - centerX);
            var degrees = angle * 180.0 / Math.PI;
            var radius = centerX - strokeWidth / 2;
            dc.drawArc(centerX, centerY, radius, Graphics.ARC_COUNTER_CLOCKWISE, degrees - 5, degrees + 5);
            x = centerX + (radius - 19) * Math.cos(angle);
            y = centerY - (radius - 19) * Math.sin(angle);
        } else {
            var edge = dc.getWidth() - strokeWidth / 2;
            var edgeY = centerY + (edge - centerX) * slope;
            dc.drawLine(edge, edgeY - 16, edge, edgeY + 16);
        }
        if (stopping) { dc.fillRectangle(x-7, y-7, 14, 14); }
        else { dc.fillCircle(x, y, 7); }
        dc.setPenWidth(2);
    }
}
class HomeDelegate extends WatchUi.BehaviorDelegate {
    var app;
    function initialize(owner) { BehaviorDelegate.initialize(); app = owner; }
    function onSelect() {
        if (app has :saveDemoNote) { app.saveDemoNote(); }
        else { app.toggle(); }
        return true;
    }
    function onMenu() { app.showNotes(); return true; }
    function onNextPage() { app.showNotes(); return true; }
    function onTap(event) {
        var point = event.getCoordinates();
        if (point[1] > System.getDeviceSettings().screenHeight * 0.72) { app.showNotes(); }
        else { app.toggle(); }
        return true;
    }
    function onBack() {
        if (app.recorder.active) { app.recorder.stop(); return true; }
        if (app.player != null) { app.stopPlayback(); return true; }
        return false;
    }
}
class NotesDelegate extends WatchUi.Menu2InputDelegate {
    var app as VoicenotesApp;
    function initialize(owner) { Menu2InputDelegate.initialize(); app = owner; }
    function onSelect(item) {
        var id = item.getId();
        if (id.equals("location") && item instanceof WatchUi.ToggleMenuItem) {
            var enabled = app.recorder.savesLocation();
            try {
                app.recorder.setSaveLocation(!enabled);
                item.setSubLabel(null);
            } catch (e) {
                item.setEnabled(enabled);
                item.setSubLabel("Could not save setting");
            }
            return;
        }
        if (id.equals("sync") && (app has :syncNow)) {
            app.syncNow();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return;
        }
        if (id.equals("sample") && (app has :saveDemoNote)) {
            app.saveDemoNote();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return;
        }
        for (var i = 0; i < app.notes.items.size(); i++) {
            var note = app.notes.items[i] as Lang.Dictionary;
            if (note["id"].equals(id)) {
                var menu = new WatchUi.Menu2({:title=>"Note"});
                menu.addItem(new WatchUi.MenuItem("Play", null, "play", null));
                menu.addItem(new WatchUi.MenuItem("Upload", app.upload.message, "upload", null));
                menu.addItem(new WatchUi.MenuItem("Delete", "Remove from watch", "delete", null));
                WatchUi.pushView(menu, new ActionsDelegate(app, note), WatchUi.SLIDE_UP);
                return;
            }
        }
    }
}
class ActionsDelegate extends WatchUi.Menu2InputDelegate {
    var app; var note;
    function initialize(owner, selected) { Menu2InputDelegate.initialize(); app = owner; note = selected; }
    function onSelect(item) {
        if (!app.isIdle()) { return; }
        var id = item.getId();
        if (id.equals("play")) { app.play(note); }
        if (id.equals("upload")) { app.upload.start(note); }
        if (id.equals("delete")) {
            var menu = new WatchUi.Menu2({:title=>"Delete note?"});
            menu.addItem(new WatchUi.MenuItem("Keep note", null, "keep", null));
            menu.addItem(new WatchUi.MenuItem("Delete permanently", null, "confirm", null));
            WatchUi.pushView(menu, new DeleteDelegate(app, note), WatchUi.SLIDE_UP);
            return;
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
class DeleteDelegate extends WatchUi.Menu2InputDelegate {
    var app; var note;
    function initialize(owner, selected) { Menu2InputDelegate.initialize(); app = owner; note = selected; }
    function onSelect(item) {
        if (item.getId().equals("confirm") && !app.upload.busy) {
            app.phoneMessage = "";
            try { app.notes.remove(note); app.recorder.message = "Deleted"; }
            catch (e) { app.recorder.message = "Delete failed"; }
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else { WatchUi.popView(WatchUi.SLIDE_DOWN); }
    }
}
