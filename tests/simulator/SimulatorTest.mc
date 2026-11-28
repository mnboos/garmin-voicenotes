import Toybox.Application;
import Toybox.Lang;
import Toybox.System;

class SimulatorTest {
    var phase = 1;
    var id as Lang.String or Null = null;

    function initialize(store as Notes) {
        if (TEST_RUN.equals(Application.Storage.getValue("testRun"))) {
            var savedPhase = Application.Storage.getValue("testPhase");
            var savedId = Application.Storage.getValue("testNote");
            if (savedPhase instanceof Lang.Number) { phase = savedPhase; }
            if (savedId instanceof Lang.String) { id = savedId; }
        } else {
            while (store.items.size() > 0) { store.remove(store.items[0]); }
            Application.Properties.setValue("backgroundPhoneSync", true);
            Application.Storage.setValue("testRun", TEST_RUN);
            queue(store);
        }
        System.println("VN-E2E ready " + phase + " " + id);
    }

    function queue(store as Notes) as Void {
        var note = new DemoFixture().save(store);
        id = note["id"] as Lang.String;
        Application.Storage.setValue("testPhase", phase);
        Application.Storage.setValue("testNote", id);
        System.println("VN-E2E queued " + phase + " " + id);
    }

    function tick(store as Notes) as Void {
        if (id == null || Application.Storage.getValue("phone:" + id) != true) { return; }
        System.println("VN-E2E receipt " + phase + " " + id);
        if (phase == 3) { System.exit(); }

        // Keep the first two fixtures until both have receipts, then free a slot.
        if (phase == 2) { store.remove(store.items[0]); }
        phase++;
        queue(store);
        if (phase == 3) {
            System.println("VN-E2E exiting " + id);
            System.exit();
        }
    }
    function stop() as Void {
        System.println("VN-E2E stopped " + phase + " " + id);
    }
}
