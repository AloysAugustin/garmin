using Toybox.WatchUi;

// The main menu of actions.
class MainMenu extends WatchUi.Menu2 {
    function initialize() {
        // The title strip beside the Instinct subscreen only fits one short word.
        Menu2.initialize({ :title => Layout.subscreen() != null ? "Tesla" : "Tesla Key" });
        addItem(new WatchUi.MenuItem("Unlock", null, :unlock, {}));
        addItem(new WatchUi.MenuItem("Lock", null, :lock, {}));
        addItem(new WatchUi.MenuItem("Trunk", null, :trunk, {}));
        addItem(new WatchUi.MenuItem("Frunk", null, :frunk, {}));
        addItem(new WatchUi.MenuItem("Wake", null, :wake, {}));
        addItem(new WatchUi.MenuItem("Pair this watch", "Enroll as a key", :pair, {}));
        addItem(new WatchUi.MenuItem("My key", "Show public key", :mykey, {}));
        addItem(new WatchUi.MenuItem("Vehicle", "VIN status", :vin, {}));
    }
}

// Submenu for choosing the role when pairing.
class PairMenu extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({ :title => "Pair as" });
        addItem(new WatchUi.MenuItem("Driver", "Drive & unlock", :pairDriver, {}));
        addItem(new WatchUi.MenuItem("Owner", "Full access", :pairOwner, {}));
    }
}
