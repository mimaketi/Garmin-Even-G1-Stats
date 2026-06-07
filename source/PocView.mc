// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 mcc4075 — non-commercial use only (GPL-3.0 §7)
using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Activity;
using Toybox.Lang;

class PocView extends WatchUi.DataField {

    hidden var mBle as PocBle;

    function initialize() {
        DataField.initialize();
        mBle = PocBle.instance();
    }

    function onLayout(dc as Graphics.Dc) as Void {}

    function compute(info as Activity.Info) as Void {
        mBle.onCompute(info);
    }

    function onTimerLap()           as Void { mBle.onLap(); }
    function onTimerReset()         as Void { mBle.onActivityReset(); }
    function onTimerStop()          as Void { mBle.onWorkoutStopped(); }
    function onTimerResume()        as Void { mBle.onWorkoutResumed(); }
    function onTimerStart()         as Void { mBle.onWorkoutResumed(); }
    function onWorkoutStarted()     as Void { mBle.onWorkoutStepBoundary(); }
    function onWorkoutStepComplete() as Void { mBle.onWorkoutStepBoundary(); }

    function onUpdate(dc as Graphics.Dc) as Void {
        var bg = getBackgroundColor();
        dc.setColor(bg, bg);
        dc.clear();

        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;

        if (!Log.DEBUG) {
            var font = Graphics.FONT_LARGE;
            var fw   = dc.getTextWidthInPixels("L", font);
            var gap  = fw / 2;

            var batt = mBle.battPct();
            var battStr = (batt >= 0) ? (batt.toString() + "%") : "";
            var battFont = Graphics.FONT_SMALL;
            var battH = dc.getFontHeight(battFont);

            var yLR = (battStr.length() > 0) ? (cy - battH / 2) : cy;

            dc.setColor(armColor(mBle.leftArmState(), bg), Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx - fw - gap, yLR, font, "L", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            dc.setColor(armColor(mBle.rightArmState(), bg), Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx + fw + gap, yLR, font, "R", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            if (battStr.length() > 0) {
                var fg = (bg == Graphics.COLOR_BLACK) ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
                dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, yLR + battH, battFont, battStr, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            }
        }

        if (Log.DEBUG) {
            var fg = (bg == Graphics.COLOR_BLACK) ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
            dc.setColor(fg, bg);
            dc.drawText(cx, 2, Graphics.FONT_XTINY,
                "G1: " + mBle.status() + " dev:" + mBle.devCount().toString(),
                Graphics.TEXT_JUSTIFY_CENTER);
            var lh = dc.getFontHeight(Graphics.FONT_XTINY) - 2;
            dc.drawText(cx, 2 + lh, Graphics.FONT_XTINY, mBle.diag(),
                Graphics.TEXT_JUSTIFY_CENTER);
            var y = 22 + lh;
            var lines = Log.lines;
            for (var i = 0; i < lines.size(); i++) {
                dc.drawText(2, y, Graphics.FONT_XTINY, lines[i], Graphics.TEXT_JUSTIFY_LEFT);
                y += lh;
            }
        }
    }

    hidden function armColor(state as Lang.Number, bg as Graphics.ColorType) as Graphics.ColorType {
        if (state == ARM_STREAMING)  { return Graphics.COLOR_GREEN; }
        if (state == ARM_ERROR)      { return Graphics.COLOR_RED; }
        if (state == ARM_CONNECTED)  {
            return (bg == Graphics.COLOR_BLACK) ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
        }
        return Graphics.COLOR_DK_GRAY;
    }
}
