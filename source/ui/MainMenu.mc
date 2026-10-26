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
        addItem(new WatchUi.MenuItem("Doors", "Experimental", :doors, {}));
        addItem(new WatchUi.MenuItem("Pair this watch", "Enroll as a key", :pair, {}));
        addItem(new WatchUi.MenuItem("My key", "Show public key", :mykey, {}));
        addItem(new WatchUi.MenuItem("Vehicle", "VIN status", :vin, {}));
    }
}

// Submenu for opening a single door. Experimental: Tesla's reference client
// never sends door commands, so the car may ignore them.
class DoorMenu extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({ :title => Layout.subscreen() != null ? "Doors" : "Open door" });
        addItem(new WatchUi.MenuItem("Front driver", null, :doorFrontDriver, {}));
        addItem(new WatchUi.MenuItem("Front passenger", null, :doorFrontPassenger, {}));
        addItem(new WatchUi.MenuItem("Rear driver", null, :doorRearDriver, {}));
        addItem(new WatchUi.MenuItem("Rear passenger", null, :doorRearPassenger, {}));
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
