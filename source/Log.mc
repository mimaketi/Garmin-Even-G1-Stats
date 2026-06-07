// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 mcc4075 — non-commercial use only (GPL-3.0 §7)
using Toybox.Lang;
using Toybox.System;

module Log {

    const DEBUG = false;
    const MAX_LINES = 9;
    var lines as Lang.Array<Lang.String> = [];

    function add(msg as Lang.String) as Void {
        if (!DEBUG) { return; }
        System.println(msg);
        lines.add(msg);
        while (lines.size() > MAX_LINES) {
            lines = lines.slice(1, null);
        }
    }

    function hex(bytes as Lang.ByteArray or Null) as Lang.String {
        if (!DEBUG) { return ""; }
        if (bytes == null) { return "(null)"; }
        var s = "";
        for (var i = 0; i < bytes.size(); i++) {
            var b = bytes[i] & 0xff;
            var hi = b / 16;
            var lo = b % 16;
            s = s + digit(hi) + digit(lo);
            if (i < bytes.size() - 1) { s = s + " "; }
        }
        return s;
    }

    function digit(n as Lang.Number) as Lang.String {
        if (n < 10) { return n.toString(); }
        var c = ['a', 'b', 'c', 'd', 'e', 'f'];
        return c[n - 10].toString();
    }
}
