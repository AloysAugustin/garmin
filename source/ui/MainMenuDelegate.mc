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

    hidden function runCommand(intent, title) {
        var status = new StatusView(title);
        mController.setSink(status);
        WatchUi.pushView(status, new StatusDelegate(mController), WatchUi.SLIDE_LEFT);
        mController.start(intent);
    }
}
