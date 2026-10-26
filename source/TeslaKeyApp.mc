using Toybox.Application;
using Toybox.WatchUi;
using Toybox.System;

// Application entry point. Owns the long-lived key store and controller.
class TeslaKeyApp extends Application.AppBase {

    hidden var mKey;
    hidden var mController;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
        mKey = new TeslaKey();
        mController = new TeslaController(mKey);
        mController.setup();
    }

    function onStop(state) {
        if (mController != null) {
            mController.cancel();
        }
    }

    // Re-read settings (e.g. VIN) when the user changes them in Garmin Connect.
    function onSettingsChanged() {
        if (mKey != null) {
            mKey.reloadSettings();
        }
    }

    function getController() {
        return mController;
    }

    function getKey() {
        return mKey;
    }

    function getInitialView() {
        return [ new MainMenu(), new MainMenuDelegate(mController, mKey) ];
    }
}
