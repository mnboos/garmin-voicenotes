import Toybox.Application;
import Toybox.Audio;
import Toybox.Background;
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
    var autoStartPending = false;
    function initialize() {
        AppBase.initialize();
    }
    function getInitialView() {
        Background.deleteTemporalEvent();
        notes = new Notes();
        recorder = new Recorder(notes);
        upload = new Upload(notes);
        timer = new Timer.Timer();
        timer.start(method(:tick), 1000, true);
        autoStartPending = Application.Properties.getValue("autoRecord") == true;
        return [new HomeView(self), new HomeDelegate(self)];
    }
    function tick() as Void {
        recorder.tick();
        if (!recorder.active && player == null) { upload.tick(); }
        WatchUi.requestUpdate();
    }
    function onStop(state) {
        if (recorder == null) { return; }
        timer.stop();
        recorder.stop();
        Audio.Output.stop();
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
    // Runs once when the home view first appears, if auto-record is enabled.
    function autoStart() {
        if (!autoStartPending) { return; }
        autoStartPending = false;
        if (!recorder.active && player == null && !upload.busy) { recorder.start(); }
    }
    function showSettings() {
        var menu = new WatchUi.Menu2({:title=>"Settings"});
        menu.addItem(new WatchUi.ToggleMenuItem("Auto-record", "Start when app opens", "autoRecord",
            Application.Properties.getValue("autoRecord") == true, null));
        menu.addItem(new WatchUi.ToggleMenuItem("Vibrate", "When recording starts", "vibrateOnRecord",
            Application.Properties.getValue("vibrateOnRecord") == true, null));
        menu.addItem(new WatchUi.MenuItem("Max length", lengthLabel(maxSeconds()), "maxSeconds", null));
        menu.addItem(new WatchUi.ToggleMenuItem("Warn before end", "Vibrate 10 s before limit", "warnBeforeEnd",
            Application.Properties.getValue("warnBeforeEnd") != false, null));
        WatchUi.pushView(menu, new SettingsDelegate(self), WatchUi.SLIDE_UP);
    }
    // Choices offered on the watch; Garmin Connect offers the same list (settings.xml).
    const LENGTHS = [30, 60, 120, 300, 600, 1800, 0];
    function maxSeconds() as Lang.Number {
        var value = Application.Properties.getValue("maxSeconds");
        return value instanceof Lang.Number && value > 0 ? value : 0;
    }
    function lengthLabel(seconds) as Lang.String {
        if (seconds <= 0) { return "No limit"; }
        if (seconds < 60) { return seconds + " s"; }
        return (seconds / 60) + " min";
    }
    function showLengths(parent as WatchUi.MenuItem) {
        var menu = new WatchUi.Menu2({:title=>"Max length", :focus=>LENGTHS.indexOf(maxSeconds()) < 0 ? 0 : LENGTHS.indexOf(maxSeconds())});
        for (var i = 0; i < LENGTHS.size(); i++) {
            menu.addItem(new WatchUi.MenuItem(lengthLabel(LENGTHS[i]), null, LENGTHS[i], null));
        }
        WatchUi.pushView(menu, new LengthDelegate(self, parent), WatchUi.SLIDE_UP);
    }
    function toggle() {
        if (player != null) { Audio.Output.stop(); player = null; return; }
        if (recorder.active) { recorder.stop(); }
        else if (!upload.busy) { upload.message = ""; recorder.start(); }
    }
    function showNotes() {
        if (recorder.active || upload.busy || player != null) { return; }
        var menu = new WatchUi.Menu2({:title=>"Saved notes"});
        for (var i = notes.items.size()-1; i >= 0; i--) {
            var n = notes.items[i] as Lang.Dictionary;
            var date = Gregorian.info(new Time.Moment(n["created"]), Time.FORMAT_SHORT);
            var title = date.day + "/" + date.month + " " + date.hour.format("%02d") + ":" + date.min.format("%02d");
            var subtitle = n["uploaded"] ? "Uploaded" : "On watch";
            if (n["state"] == "interrupted") { subtitle = "Partial / interrupted"; }
            menu.addItem(new WatchUi.MenuItem(title, subtitle + " · " + n["seconds"] + "s", n["id"], null));
        }
        if (notes.items.size() == 0) { menu.addItem(new WatchUi.MenuItem("No notes yet", null, "empty", null)); }
        // Last item; Menu2 wraps, so it is one UP press from the top.
        menu.addItem(new WatchUi.MenuItem("Settings", "Recording options", "settings", null));
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
    function onShow() { app.autoStart(); }
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
        var status = app.notes.items.size() + " notes";
        if (app.recorder.active) {
            status = app.recorder.note["seconds"] + (app.recorder.limit > 0 ? " / " + app.recorder.limit + " s" : " seconds");
        }
        dc.drawText(w/2, h*0.59, Graphics.FONT_SMALL, status, Graphics.TEXT_JUSTIFY_CENTER);
        var msg = !app.recorder.active && app.upload.message.length() > 0 ? app.upload.message : app.recorder.message;
        dc.drawText(w/2, h*0.70, Graphics.FONT_XTINY, msg, Graphics.TEXT_JUSTIFY_CENTER);
        drawButtonHint(dc);
        if (!app.recorder.active && app.player == null && !app.upload.busy) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            for (var row = 0; row < 3; row++) {
                var y = h*0.84 + row*5;
                dc.drawLine(w/2-10, y, w/2+10, y);
            }
        }
    }
    function drawButtonHint(dc) {
        var centerX = dc.getWidth() / 2.0;
        var centerY = dc.getHeight() / 2.0;
        // Angle of the START button, counter-clockwise from 3 o'clock, in radians.
        var angle;
        if (startButton.size() == 1) {
            // Per-device angle in degrees, e.g. resources-fenix8/start-button.xml.
            angle = startButton[0].toFloat() * Math.PI / 180.0;
        } else {
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
            angle = Math.atan2(centerY - buttonY, buttonX - centerX);
        }
        var slope = -Math.tan(angle);
        var x = dc.getWidth() - 24;
        var y = centerY + (x - centerX) * slope;
        var stopping = app.recorder.active || app.player != null;
        dc.setColor(app.upload.busy || app.recorder.finishing ? Graphics.COLOR_DK_GRAY : Graphics.COLOR_RED,
            Graphics.COLOR_TRANSPARENT);
        var strokeWidth = 4;
        dc.setPenWidth(strokeWidth);
        if (System.getDeviceSettings().screenShape == System.SCREEN_SHAPE_ROUND) {
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
    function onSelect() { app.toggle(); return true; }
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
        if (app.player != null) { Audio.Output.stop(); app.player = null; return true; }
        return false;
    }
}
class LengthDelegate extends WatchUi.Menu2InputDelegate {
    var app; var parent;
    function initialize(owner, item) { Menu2InputDelegate.initialize(); app = owner; parent = item; }
    function onSelect(item) {
        Application.Properties.setValue("maxSeconds", item.getId() as Lang.Number);
        parent.setSubLabel(app.lengthLabel(item.getId()));
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
class SettingsDelegate extends WatchUi.Menu2InputDelegate {
    var app;
    function initialize(owner) { Menu2InputDelegate.initialize(); app = owner; }
    function onSelect(item) {
        if (item.getId().equals("maxSeconds")) { app.showLengths(item as WatchUi.MenuItem); return; }
        if (item instanceof WatchUi.ToggleMenuItem) {
            Application.Properties.setValue(item.getId() as Lang.String, item.isEnabled());
        }
    }
}
class NotesDelegate extends WatchUi.Menu2InputDelegate {
    var app as VoicenotesApp;
    function initialize(owner) { Menu2InputDelegate.initialize(); app = owner; }
    function onSelect(item) {
        if (item.getId().equals("settings")) { app.showSettings(); return; }
        for (var i = 0; i < app.notes.items.size(); i++) {
            var note = app.notes.items[i] as Lang.Dictionary;
            if (note["id"].equals(item.getId())) {
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
        if (app.upload.busy || app.recorder.active || app.player != null) { return; }
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
            try { app.notes.remove(note); app.recorder.message = "Deleted"; }
            catch (e) { app.recorder.message = "Delete failed"; }
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else { WatchUi.popView(WatchUi.SLIDE_DOWN); }
    }
}
