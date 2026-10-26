using Toybox.WatchUi;

// Handles selections from the main menu.
class MainMenuDelegate extends WatchUi.Menu2InputDelegate {

    hidden var mController;
    hidden var mKey;

    function initialize(controller, key) {
        Menu2InputDelegate.initialize();
        mController = controller;
        mKey = key;
    }

    function onSelect(item) {
        var id = item.getId();
        if (id == :unlock) {
            runCommand(TeslaController.INTENT_UNLOCK, "Unlock");
        } else if (id == :lock) {
            runCommand(TeslaController.INTENT_LOCK, "Lock");
        } else if (id == :trunk) {
            runCommand(TeslaController.INTENT_TRUNK, "Trunk");
        } else if (id == :frunk) {
            runCommand(TeslaController.INTENT_FRUNK, "Frunk");
        } else if (id == :wake) {
            runCommand(TeslaController.INTENT_WAKE, "Wake");
        } else if (id == :drive) {
            var code = DriveGuard.precheck();
            if (code == DriveGuard.PIN_OK) {
                var pinView = new PinView();
                WatchUi.pushView(pinView, new PinDelegate(pinView, self), WatchUi.SLIDE_LEFT);
            } else {
                showMessage("Drive", DriveGuard.message(code));
            }
        } else if (id == :doors) {
            WatchUi.pushView(new DoorMenu(), new MainMenuDelegate(mController, mKey), WatchUi.SLIDE_LEFT);
        } else if (id == :doorFrontDriver) {
            runCommand(TeslaController.INTENT_DOOR_FRONT_DRIVER, "Open door");
        } else if (id == :doorFrontPassenger) {
            runCommand(TeslaController.INTENT_DOOR_FRONT_PASSENGER, "Open door");
        } else if (id == :doorRearDriver) {
            runCommand(TeslaController.INTENT_DOOR_REAR_DRIVER, "Open door");
        } else if (id == :doorRearPassenger) {
            runCommand(TeslaController.INTENT_DOOR_REAR_PASSENGER, "Open door");
        } else if (id == :pair) {
            WatchUi.pushView(new PairMenu(), new MainMenuDelegate(mController, mKey), WatchUi.SLIDE_LEFT);
        } else if (id == :pairDriver) {
            runCommand(TeslaController.INTENT_PAIR_DRIVER, "Pair (Driver)");
        } else if (id == :pairOwner) {
            runCommand(TeslaController.INTENT_PAIR_OWNER, "Pair (Owner)");
        } else if (id == :mykey) {
            WatchUi.pushView(new InfoView(InfoView.MODE_KEY, mKey), new InfoDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id == :vin) {
            WatchUi.pushView(new InfoView(InfoView.MODE_VIN, mKey), new InfoDelegate(), WatchUi.SLIDE_LEFT);
        }
    }

    // Called by PinDelegate once the Drive PIN is verified.
    function startDrive() {
        runCommand(TeslaController.INTENT_DRIVE, "Drive");
    }

    // A full-screen message (reusing StatusView's layout); BACK returns.
    function showMessage(title, msg) {
        var view = new StatusView(title);
        view.onResult(false, msg);
        WatchUi.pushView(view, new InfoDelegate(), WatchUi.SLIDE_LEFT);
    }

    hidden function runCommand(intent, title) {
        var status = new StatusView(title);
        mController.setSink(status);
        WatchUi.pushView(status, new StatusDelegate(mController), WatchUi.SLIDE_LEFT);
        mController.start(intent);
    }
}
