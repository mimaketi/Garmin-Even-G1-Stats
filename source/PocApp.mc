using Toybox.Application;
using Toybox.WatchUi;
using Toybox.Lang;

class PocApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Lang.Dictionary or Null) as Void {}

    function onStop(state as Lang.Dictionary or Null) as Void {
        PocBle.instance().shutdown();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [ new PocView() ];
    }
}
