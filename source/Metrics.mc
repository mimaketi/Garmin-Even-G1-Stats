// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 mcc4075 — non-commercial use only (GPL-3.0 §7)
using Toybox.Lang;
using Toybox.UserProfile;

module Metrics {

    const METERS_PER_KM = 1000.0;
    const METERS_PER_MI = 1609.34;

    function num(n as Lang.Number or Null) as Lang.String {
        return (n == null) ? "--" : n.toString();
    }

    function pace(speedMps as Lang.Float or Null, metric as Lang.Boolean) as Lang.String {
        if (speedMps == null || speedMps < 0.3) { return "--:--"; }
        var metersPerUnit = metric ? METERS_PER_KM : METERS_PER_MI;
        return mmss((metersPerUnit / speedMps).toNumber());
    }

    function paceFromDistTime(distM as Lang.Float or Null, timeMs as Lang.Number or Null, metric as Lang.Boolean) as Lang.String {
        if (distM == null || timeMs == null || distM < 1.0 || timeMs < 1000) { return "--:--"; }
        var metersPerUnit = metric ? METERS_PER_KM : METERS_PER_MI;
        var sec = (timeMs / 1000.0) / (distM / metersPerUnit);
        return mmss(sec.toNumber());
    }

    function dist(distM as Lang.Float or Null, metric as Lang.Boolean) as Lang.String {
        if (distM == null) { return "0.00"; }
        var u = distM / (metric ? METERS_PER_KM : METERS_PER_MI);
        return u.format("%.2f");
    }

    function duration(ms as Lang.Number or Null) as Lang.String {
        if (ms == null) { return "0:00"; }
        var total = ms / 1000;
        var h = total / 3600;
        var m = (total % 3600) / 60;
        var s = total % 60;
        if (h > 0) { return h.toString() + ":" + pad(m) + ":" + pad(s); }
        return m.toString() + ":" + pad(s);
    }

    function hrZone(hr as Lang.Number or Null) as Lang.String {
        if (hr == null) { return "Z?"; }
        var zones = UserProfile.getHeartRateZones(UserProfile.HR_ZONE_SPORT_RUNNING);
        if (zones == null || zones.size() < 5) { return "Z?"; }
        var z = 0;
        for (var i = 0; i < 5; i++) {
            if (hr > (zones[i] as Lang.Number)) { z = i + 1; }
        }
        return "Z" + z.toString();
    }

    function mmss(sec as Lang.Number) as Lang.String {
        if (sec <= 0 || sec > 3599) { return "--:--"; }
        return (sec / 60).toString() + ":" + pad(sec % 60);
    }

    function elev(m as Lang.Float or Null, metric as Lang.Boolean) as Lang.String {
        if (m == null) { return "--"; }
        if (metric) { return m.toNumber().toString() + "m"; }
        return ((m * 3.28084).toNumber()).toString() + "ft";
    }

    function pad(n as Lang.Number) as Lang.String {
        return (n < 10) ? ("0" + n.toString()) : n.toString();
    }
}
