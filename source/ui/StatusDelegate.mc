using Toybox.WatchUi;

// Back = cancel the in-flight operation (if any) and return to the menu.
class StatusDelegate extends WatchUi.BehaviorDelegate {

    hidden var mController;

    function initialize(controller) {
        BehaviorDelegate.initialize();
        mController = controller;
    }

    function onBack() {
        mController.setSink(null);
        mController.cancel();
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
