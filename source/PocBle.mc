// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 mcc4075 — non-commercial use only (GPL-3.0 §7)
using Toybox.BluetoothLowEnergy as Ble;
using Toybox.Lang;
using Toybox.System;
using Toybox.Activity;
using Toybox.Time;
using Toybox.UserProfile;

const ARM_SCANNING  = 0;
const ARM_CONNECTED = 1;
const ARM_STREAMING = 2;
const ARM_ERROR     = 3;

class PocBle extends Ble.BleDelegate {

    const SERVICE_UUID = Ble.longToUuid(0x6E400001B5A3F393l, 0xE0A9E50E24DCCA9El);
    const RX_CHAR_UUID = Ble.longToUuid(0x6E400002B5A3F393l, 0xE0A9E50E24DCCA9El);
    const TX_CHAR_UUID = Ble.longToUuid(0x6E400003B5A3F393l, 0xE0A9E50E24DCCA9El);
    const PROFILE = {
        :uuid => SERVICE_UUID,
        :characteristics => [
            { :uuid => RX_CHAR_UUID },
            { :uuid => TX_CHAR_UUID, :descriptors => [Ble.cccdUuid()] }
        ]
    };

    const CMD_TEXT      = 0x4E;
    const CMD_HEARTBEAT = 0x25;
    const NEW_SCREEN    = 0x71;
    const TEXT_CHUNK      = 11;
    const MAX_RETRY       = 1;
    const FRAME_SETTLE    = 2;
    const ACK_TIMEOUT     = 3;
    const MAX_RESENDS     = 4;
    const SINGLE_ARM_GRACE = 8;
    const CLEAR_SCREEN = 0x18;
    const CMD_BATT      = 0x2C;
    const BATT_POLL_EVERY = 300;
    const TIME_SYNC_EVERY =  60;

    const SLOT_BY_PHYSICAL   = true;
    const INVERT_SIDES       = true;
    const SINGLE_ARM_DISPLAY = false;

    const MODE_UNKNOWN = 0;
    const MODE_RUN     = 1;
    const MODE_GLANCE  = 2;
    const GLANCE_SECS    = 12;
    const GLANCE_LOCKOUT = 10;
    const GLANCE_HB      = 8;
    const GLANCE_ON_LAP  = true;
    const ROTATE_SECS    = 10;
    const ROTATE_SLOTS   = 5;

    const SIDE_LEFT  = 1;
    const SIDE_RIGHT = 2;

    hidden static var mInstance as PocBle or Null = null;
    static function instance() as PocBle {
        if (mInstance == null) {
            mInstance = new PocBle();
        }
        return mInstance;
    }

    hidden var mLeftArmState  as Lang.Number = ARM_SCANNING;
    hidden var mRightArmState as Lang.Number = ARM_SCANNING;

    function leftArmState()  as Lang.Number { return mLeftArmState; }
    function rightArmState() as Lang.Number { return mRightArmState; }

    hidden var mLeftRx  as Ble.Characteristic or Null = null;
    hidden var mRightRx as Ble.Characteristic or Null = null;
    hidden var mLeftTx  as Ble.Characteristic or Null = null;
    hidden var mRightTx as Ble.Characteristic or Null = null;
    hidden var mLeftReady  as Lang.Boolean = false;
    hidden var mRightReady as Lang.Boolean = false;
    hidden var mFirstReadyTick as Lang.Number = -1;
    hidden var mLeftAckN as Lang.Number = 0;
    hidden var mRightAckN as Lang.Number = 0;
    hidden var mChunkN as Lang.Number = 0;
    hidden var mMissN as Lang.Number = 0;
    hidden var mLastMissOp as Lang.Number = -1;
    hidden var mPairingSide as Lang.Number = 0;
    hidden var mWrFail as Lang.Number = 0;
    hidden var mRetryN as Lang.Number = 0;
    hidden var mInFlightChar as Ble.Characteristic or Null = null;
    hidden var mInFlightBytes as Lang.ByteArray or Null = null;
    hidden var mFrameSettleTick as Lang.Number = 0;
    hidden var mLeftAckBase  as Lang.Number = 0;
    hidden var mRightAckBase as Lang.Number = 0;
    hidden var mFrameAckTimeout as Lang.Number = 0;
    hidden var mLastFrame as Lang.Array or Null = null;
    hidden var mLeftResendN  as Lang.Number = 0;
    hidden var mRightResendN as Lang.Number = 0;
    hidden var mLeftBypassed  as Lang.Boolean = false;
    hidden var mRightBypassed as Lang.Boolean = false;
    hidden var mPairBusy as Lang.Boolean = false;
    hidden var mLockedChannel as Lang.String or Null = null;
    hidden var mLeftScan  as Ble.ScanResult or Null = null;
    hidden var mRightScan as Ble.ScanResult or Null = null;
    hidden var mScanning as Lang.Boolean = false;
    hidden var mDevCount as Lang.Number = 0;

    hidden var mQueue as Lang.Array = [];
    hidden var mInFlight as Lang.Boolean = false;
    hidden var mInFlightSide as Lang.Number = 0;
    hidden var mInFlightAge as Lang.Number = 0;
    hidden var mInitDone as Lang.Boolean = false;

    hidden var mInfo as Activity.Info or Null = null;
    hidden var mLapStartDist as Lang.Float = 0.0;
    hidden var mLapStartTime as Lang.Number = 0;
    hidden var mStepStartTimeMs as Lang.Number = 0;
    hidden var mStepStartDistM as Lang.Float = 0.0;

    hidden var mEndState as Lang.Number = 0;
    hidden var mEndShownTick as Lang.Number = 0;

    hidden var mMode as Lang.Number = MODE_UNKNOWN;
    hidden var mGlanceShownTick as Lang.Number = -1;
    hidden var mGlanceLockoutTick as Lang.Number = -1;

    hidden var mLeftBatt  as Lang.Number = -1;
    hidden var mRightBatt as Lang.Number = -1;
    hidden var mLeftWarnLevel  as Lang.Number = 100;
    hidden var mRightWarnLevel as Lang.Number = 100;
    hidden var mWarnUntilTick as Lang.Number = -1;
    hidden var mTimeSyncSeq as Lang.Number = 0;

    hidden var mSyncSeq as Lang.Number = 0;
    hidden var mBeatSeq as Lang.Number = 0;
    hidden var mTick as Lang.Number = 0;

    hidden var mStatus as Lang.String = "init";

    function status() as Lang.String { return mStatus; }
    function devCount() as Lang.Number { return mDevCount; }

    function diag() as Lang.String {
        return "La" + mLeftAckN.toString() + " Ra" + mRightAckN.toString() + " wf" + mWrFail.toString();
    }

    function initialize() {
        Ble.BleDelegate.initialize();
        Ble.setDelegate(self);
        clearStaleBonds();
        try {
            Ble.registerProfile(PROFILE);
            mStatus = "registering";
        } catch (ex) {
            mStatus = "register FAIL";
            Log.add("registerProfile EX: " + ex.getErrorMessage());
        }
    }

    function shutdown() as Void {
        sendFrame(" ");
        enqueueBoth([0x18]b);
        enqueueBoth([0x08, 0x06, 0x00, 0x00, 0x03, 0x00]b);
        pump();
    }

    function onProfileRegister(uuid as Ble.Uuid, status as Ble.Status) as Void {
        if (status == Ble.STATUS_SUCCESS) {
            startScan();
        } else {
            mStatus = "profile FAIL";
        }
    }

    hidden function clearStaleBonds() as Void {
        try {
            var it = Ble.getPairedDevices();
            var d = it.next();
            while (d != null) {
                try { Ble.unpairDevice(d as Ble.Device); } catch (ex) {}
                d = it.next();
            }
        } catch (ex) {}
    }

    hidden function startScan() as Void {
        mLockedChannel = null;
        mLeftScan = null;
        mRightScan = null;
        mPairBusy = false;
        try {
            Ble.setScanState(Ble.SCAN_STATE_SCANNING);
            mScanning = true;
            mStatus = "scanning";
        } catch (ex) {
            mStatus = "scan FAIL";
            Log.add("scan EX: " + ex.getErrorMessage());
        }
    }

    function onScanStateChange(scanState as Ble.ScanState, status as Ble.Status) as Void {
    }

    function onScanResults(scanResults as Ble.Iterator) as Void {
        var n = 0;
        var obj = scanResults.next();
        while (obj != null) {
            var r = obj as Ble.ScanResult;
            n += 1;
            considerScanResult(r, r.getDeviceName());
            obj = scanResults.next();
        }
        mDevCount = n;
        if (mScanning) {
            pairNext();
        }
    }

    hidden function considerScanResult(r as Ble.ScanResult, name as Lang.String or Null) as Void {
        if (name != null) {
            var parts = split(name, '_');
            if (parts.size() == 4 && parts[0].length() >= 2 && parts[0].substring(0, 2).equals("G1")) {
                var channel = parts[1];
                var side = parts[2];
                if (mLockedChannel == null) {
                    mLockedChannel = channel;
                } else if (!mLockedChannel.equals(channel)) {
                    return;
                }
                var ns = side.equals("L") ? SIDE_LEFT : (side.equals("R") ? SIDE_RIGHT : 0);
                ns = applyInvert(ns);
                if (ns == SIDE_LEFT) { mLeftScan = r; }
                else if (ns == SIDE_RIGHT) { mRightScan = r; }
                return;
            }
        }
        var s = g1SideFromMfg(r);
        if (s == SIDE_LEFT) {
            mLeftScan = r;
        } else if (s == SIDE_RIGHT) {
            mRightScan = r;
        }
    }

    hidden function g1SideFromMfg(r as Ble.ScanResult) as Lang.Number {
        var mit = r.getManufacturerSpecificDataIterator();
        var m = mit.next();
        while (m != null) {
            var id = (m as Lang.Dictionary)[:companyId] as Lang.Number;
            if ((id & 0xff00) == 0x5300) {
                var lo = id & 0xff;
                if (lo == 0x01) { return applyInvert(SIDE_LEFT); }
                if (lo == 0x02) { return applyInvert(SIDE_RIGHT); }
            }
            m = mit.next();
        }
        return 0;
    }

    hidden function applyInvert(side as Lang.Number) as Lang.Number {
        if (!INVERT_SIDES) { return side; }
        if (side == SIDE_LEFT)  { return SIDE_RIGHT; }
        if (side == SIDE_RIGHT) { return SIDE_LEFT; }
        return side;
    }

    hidden function pairNext() as Void {
        if (mPairBusy) { return; }
        if (mLeftRx != null && mRightRx != null) { return; }
        var scan = null;
        if (mLeftScan != null) {
            scan = mLeftScan; mLeftScan = null; mPairingSide = SIDE_LEFT;
        } else if (mRightScan != null) {
            scan = mRightScan; mRightScan = null; mPairingSide = SIDE_RIGHT;
        }
        if (scan == null) { return; }
        mPairBusy = true;
        mScanning = false;
        try { Ble.setScanState(Ble.SCAN_STATE_OFF); } catch (ex) {}
        mStatus = "connecting";
        try {
            Ble.pairDevice(scan);
        } catch (ex) {
            Log.add("pairEX -> rescan");
            mPairBusy = false;
            startScan();
        }
    }

    function onConnectedStateChanged(device as Ble.Device, state as Ble.ConnectionState) as Void {
        if (device == null) { return; }
        var nm = "(?)";
        try {
            var name = device.getName();
            if (name != null) { nm = name; }
        } catch (ex) {}
        if (state == Ble.CONNECTION_STATE_CONNECTED) {
            mPairBusy = true;
            Log.add("CONNECTED " + nm);
            discover(device);
        } else {
            Log.add("DISCONNECTED " + nm + " -> rescan");
            mLeftArmState  = ARM_SCANNING;
            mRightArmState = ARM_SCANNING;
            clearStaleBonds();
            resetLinks();
            startScan();
        }
    }

    function onEncryptionStatus(device as Ble.Device, status as Ble.Status) as Void {
    }

    hidden function discover(device as Ble.Device) as Void {
        var service = device.getService(SERVICE_UUID);
        if (service == null) { Log.add("NUS service MISSING"); return; }
        var rx = service.getCharacteristic(RX_CHAR_UUID);
        var tx = service.getCharacteristic(TX_CHAR_UUID);
        if (rx == null || tx == null) {
            Log.add("RX/TX MISSING rx=" + (rx == null ? "0" : "1") + " tx=" + (tx == null ? "0" : "1"));
            return;
        }
        if (rx == mLeftRx || rx == mRightRx) { return; }
        var side = 0;
        if (SLOT_BY_PHYSICAL) { side = mPairingSide; }
        if (side == SIDE_LEFT && mLeftRx == null)        { mLeftRx = rx;  mLeftTx = tx; }
        else if (side == SIDE_RIGHT && mRightRx == null) { mRightRx = rx; mRightTx = tx; }
        else if (mLeftRx == null)  { mLeftRx = rx;  mLeftTx = tx;  side = SIDE_LEFT; }
        else if (mRightRx == null) { mRightRx = rx; mRightTx = tx; side = SIDE_RIGHT; }
        else { return; }
        var cccd = tx.getDescriptor(Ble.cccdUuid());
        if (cccd == null) { Log.add("CCCD MISSING"); return; }
        enqueueDesc(cccd, [0x01, 0x00]b, side);
        pump();
    }

    function onDescriptorWrite(descriptor as Ble.Descriptor, status as Ble.Status) as Void {
        var side = mInFlightSide;
        mInFlight = false;
        if (status != Ble.STATUS_SUCCESS) { Log.add("notify FAIL side=" + side.toString() + " s=" + status.toString()); }
        if (status == Ble.STATUS_SUCCESS) {
            if (side == SIDE_LEFT) { mLeftReady = true; mLeftArmState = ARM_CONNECTED; }
            else if (side == SIDE_RIGHT) { mRightReady = true; mRightArmState = ARM_CONNECTED; }
            if (mFirstReadyTick < 0) { mFirstReadyTick = mTick; }
            mStatus = (mLeftReady && mRightReady) ? "READY" : "1 arm";
            mPairBusy = false;
            if (mLeftReady && mRightReady && !mInitDone) {
                mInitDone = true;
                sendInit();
            }
            ensureMoreArms();
        }
        pump();
    }

    hidden function ensureMoreArms() as Void {
        if (mLeftRx != null && mRightRx != null) {
            mScanning = false;
            try { Ble.setScanState(Ble.SCAN_STATE_OFF); } catch (ex) {}
            return;
        }
        if (!mScanning) { startScan(); }
    }

    function onCharacteristicWrite(characteristic as Ble.Characteristic, status as Ble.Status) as Void {
        if (status != Ble.STATUS_SUCCESS && mRetryN < MAX_RETRY && mInFlightChar != null && mInFlightBytes != null) {
            mWrFail += 1;
            mRetryN += 1;
            Log.add("retry side=" + mInFlightSide.toString());
            try {
                (mInFlightChar as Ble.Characteristic).requestWrite(mInFlightBytes,
                    { :writeType => Ble.WRITE_TYPE_WITH_RESPONSE });
                return;
            } catch (ex) {}
        }
        mRetryN = 0;
        mInFlight = false;
        pump();
    }

    function onCharacteristicChanged(characteristic as Ble.Characteristic, value as Lang.ByteArray) as Void {
        if (value == null || value.size() < 1) { return; }
        var b0 = value[0] & 0xff;
        if (b0 == CMD_TEXT) {
            if (characteristic == mLeftTx) {
                mLeftAckN += 1;
                if (mLeftBypassed) { mLeftBypassed = false; mLeftResendN = 0; mLeftArmState = ARM_STREAMING; Log.add("L back"); }
            } else if (characteristic == mRightTx) {
                mRightAckN += 1;
                if (mRightBypassed) { mRightBypassed = false; mRightResendN = 0; mRightArmState = ARM_STREAMING; Log.add("R back"); }
            } else {
                mMissN += 1; mLastMissOp = 0x4E;
            }
            return;
        }
        if (b0 == 0x22 && value.size() >= 2 && (value[1] & 0xff) == 0x0a) {
            showGlance();
            return;
        }
        if (b0 == CMD_BATT && value.size() >= 3 && (value[1] & 0xff) == 0x66) {
            var pct = value[2] & 0xff;
            var isLeft = (characteristic == mLeftTx);
            if (isLeft)                          { mLeftBatt  = pct; }
            else if (characteristic == mRightTx) { mRightBatt = pct; }
            else                                 { return; }
            checkBatteryWarning(isLeft, pct);
            return;
        }
        if (b0 == CMD_HEARTBEAT) { return; }
        mMissN += 1; mLastMissOp = b0;
    }

    function onCharacteristicRead(characteristic as Ble.Characteristic, status as Ble.Status, value as Lang.ByteArray) as Void {}
    function onDescriptorRead(descriptor as Ble.Descriptor, status as Ble.Status, value as Lang.ByteArray) as Void {}

    function onCompute(info as Activity.Info) as Void {
        mInfo = info;
        if (mInFlight) {
            mInFlightAge += 1;
            if (mInFlightAge >= 3) { mInFlight = false; }
        }
        if (mLeftReady || mRightReady) {
            mTick += 1;
            detectMode();
            if (mMode == MODE_UNKNOWN) { pump(); return; }
            var hbEvery = (mMode == MODE_GLANCE) ? GLANCE_HB : 10;
            if (mTick % hbEvery == 0) { enqueueHeartbeat(); }
            if (mTick % TIME_SYNC_EVERY == 2)  { sendTimeSync(); }
            if (mTick % BATT_POLL_EVERY  == 7) { sendBattQuery(); }
            if (mQueue.size() == 0 && !mInFlight) {
                if (mMode == MODE_GLANCE) { glanceTick(); }
                else { maybeRefresh(); }
            }
        }
        pump();
    }

    hidden function detectMode() as Void {
        if (mMode != MODE_UNKNOWN) { return; }
        var sport = null;
        try {
            var p = Activity.getProfileInfo();
            if (p != null) { sport = p.sport; }
        } catch (ex) {}
        if (sport == null) {
            if (mTick >= 3) { mMode = MODE_RUN; mStatus = "run?"; }
            return;
        }
        if (sport == Activity.SPORT_WALKING || sport == Activity.SPORT_HIKING) {
            mMode = MODE_GLANCE; mStatus = "glance";
        } else {
            mMode = MODE_RUN; mStatus = "run";
        }
        Log.add("mode=" + ((mMode == MODE_GLANCE) ? "GLANCE" : "RUN") + " sport=" + sport.toString());
    }

    hidden function glanceTick() as Void {
        if (mEndState == 1) {
            if (mLeftRx  != null) { mLeftArmState  = ARM_CONNECTED; }
            if (mRightRx != null) { mRightArmState = ARM_CONNECTED; }
            sendFrame(buildSummary()); mEndShownTick = mTick; mEndState = 2; mGlanceShownTick = -1; return;
        }
        if (mEndState == 2 && mTick - mEndShownTick >= 8) { sendFrame(" "); enqueueBoth([0x18]b); enqueueBoth([0x08, 0x06, 0x00, 0x00, 0x03, 0x00]b); mEndState = 3; return; }
        if (mEndState >= 2) { return; }
        if (mGlanceShownTick >= 0 && mTick - mGlanceShownTick >= GLANCE_SECS) {
            sendFrame(" ");
            enqueueBoth([0x18]b);
            mGlanceShownTick = -1;
            mGlanceLockoutTick = mTick;
            if (mLeftRx  != null) { mLeftArmState  = ARM_CONNECTED; }
            if (mRightRx != null) { mRightArmState = ARM_CONNECTED; }
            return;
        }
        if (mGlanceShownTick >= 0 && mTick - mFrameSettleTick >= FRAME_SETTLE) {
            sendFrame(buildHud());
        }
        if (mGlanceLockoutTick >= 0 && mTick - mGlanceLockoutTick >= GLANCE_LOCKOUT) {
            enqueueBoth([0x08, 0x06, 0x00, 0x00, 0x03, 0x00]b);
            mGlanceLockoutTick = -1;
        }
    }

    hidden function showGlance() as Void {
        if (mMode != MODE_GLANCE || mEndState != 0) { return; }
        if (mGlanceShownTick >= 0 || mGlanceLockoutTick >= 0) { return; }
        mGlanceShownTick = mTick;
        if (mLeftRx  != null) { mLeftArmState  = ARM_STREAMING; }
        if (mRightRx != null) { mRightArmState = ARM_STREAMING; }
        Log.add("head up -> HUD");
        enqueueBothFast([0x08, 0x06, 0x00, 0x00, 0x03, 0x02]b);
        enqueueBoth([0x18]b);
        sendFrame(buildHud());
    }

    hidden function maybeRefresh() as Void {
        if (mEndState == 0) {
            if (mLastFrame == null) {
                var bothReady = mLeftReady && mRightReady;
                var graceExpired = (mFirstReadyTick >= 0) && (mTick - mFirstReadyTick >= SINGLE_ARM_GRACE);
                if (!bothReady && !graceExpired) { return; }
            }
            if (mTick - mFrameSettleTick < FRAME_SETTLE) { return; }
            var neverSent = (mLastFrame == null);
            var need = neverSent ? 0 : ((mLastFrame as Lang.Array).size() - 1);
            if (need < 1) { need = 1; }
            var leftOk  = neverSent || (mLeftRx  == null) || mLeftBypassed  || (mLeftAckN  - mLeftAckBase  >= need);
            var rightOk = SINGLE_ARM_DISPLAY || neverSent || (mRightRx == null) || mRightBypassed || (mRightAckN - mRightAckBase >= need);
            if (leftOk && rightOk) {
                mLeftResendN  = 0;
                mRightResendN = 0;
                mFrameAckTimeout = 0;
                if (mLeftRx  != null) { mLeftArmState  = ARM_STREAMING; }
                if (mRightRx != null) { mRightArmState = ARM_STREAMING; }
                sendFrame(buildHud());
            } else {
                mFrameAckTimeout += 1;
                if (mFrameAckTimeout >= ACK_TIMEOUT) {
                    mFrameAckTimeout = 0;
                    if (!leftOk) {
                        mLeftResendN += 1;
                        if (mLeftResendN >= MAX_RESENDS) {
                            mLeftBypassed = true;
                            mLeftArmState = ARM_ERROR;
                            Log.add("bypass L");
                        } else { resend(mLeftRx, SIDE_LEFT); }
                    }
                    if (!rightOk) {
                        mRightResendN += 1;
                        if (mRightResendN >= MAX_RESENDS) {
                            mRightBypassed = true;
                            mRightArmState = ARM_ERROR;
                            Log.add("bypass R");
                        } else { resend(mRightRx, SIDE_RIGHT); }
                    }
                }
            }
        } else if (mEndState == 1) {
            if (mLeftRx  != null) { mLeftArmState  = ARM_CONNECTED; }
            if (mRightRx != null) { mRightArmState = ARM_CONNECTED; }
            sendFrame(buildSummary());
            mEndShownTick = mTick;
            mEndState = 2;
        } else if (mEndState == 2 && mTick - mEndShownTick >= 8) {
            sendFrame(" ");
            enqueueBoth([0x18]b);
            enqueueBoth([0x08, 0x06, 0x00, 0x00, 0x03, 0x00]b);
            mEndState = 3;
        }
    }

    hidden function resend(rx as Ble.Characteristic or Null, side as Lang.Number) as Void {
        if (rx == null || mLastFrame == null) { return; }
        Log.add("resend " + ((side == SIDE_LEFT) ? "L" : "R"));
        var chunks = mLastFrame as Lang.Array;
        for (var i = 0; i < chunks.size(); i++) {
            mQueue.add({ :t => rx, :b => chunks[i], :d => false, :side => side });
        }
        pump();
    }

    function onWorkoutStopped() as Void {
        if (mEndState == 0) { mEndState = 1; }
    }

    function onWorkoutResumed() as Void {
        if (mEndState != 0) { mEndState = 0; }
        mLastFrame = null;
        mLeftBypassed = false; mRightBypassed = false;
        mLeftResendN = 0; mRightResendN = 0;
    }

    function onLap() as Void {
        if (mInfo != null) {
            if (mInfo.elapsedDistance != null) { mLapStartDist = mInfo.elapsedDistance; }
            if (mInfo.timerTime != null) { mLapStartTime = mInfo.timerTime; }
        }
        if (GLANCE_ON_LAP && mMode == MODE_GLANCE) {
            showGlance();
        }
    }

    function onActivityReset() as Void {
        mLapStartDist = 0.0;
        mLapStartTime = 0;
        mStepStartTimeMs = 0;
        mStepStartDistM = 0.0;
    }

    function onWorkoutStepBoundary() as Void {
        if (mInfo == null) { return; }
        mStepStartTimeMs = (mInfo.timerTime != null) ? mInfo.timerTime : 0;
        mStepStartDistM  = (mInfo.elapsedDistance != null) ? mInfo.elapsedDistance : 0.0;
    }

    hidden function buildHud() as Lang.String {
        if (mWarnUntilTick > 0 && mTick < mWarnUntilTick) {
            return buildBatteryWarningText();
        }
        var info = mInfo;
        if (info == null) { return "G1 ready"; }
        var metric = (System.getDeviceSettings().distanceUnits == System.UNIT_METRIC);
        var u = metric ? "km" : "mi";

        var stepInfo = currentStepInfo();
        if (stepInfo != null) {
            return buildWorkoutHud(info, metric, u, stepInfo);
        }

        var line3 = (mMode == MODE_GLANCE)
            ? (Metrics.elev(info.totalAscent, metric) + " ^")
            : rotatingRunMetric(info, metric);
        return "HR: " + Metrics.num(info.currentHeartRate) + " " + Metrics.hrZone(info.currentHeartRate) + "\n"
             + Metrics.pace(info.currentSpeed, metric) + " /" + u + "\n"
             + line3 + "\n"
             + Metrics.dist(info.elapsedDistance, metric) + u + "  " + Metrics.duration(info.timerTime);
    }

    hidden function rotatingRunMetric(info as Activity.Info, metric as Lang.Boolean) as Lang.String {
        var slot = (mTick / ROTATE_SECS) % ROTATE_SLOTS;
        if (slot == 0) { return hrPctOfMax(info.currentHeartRate) + " HR%"; }
        if (slot == 1) { return Metrics.num(info.currentCadence) + " spm"; }
        if (slot == 2) { return Metrics.num(info.currentPower) + "w"; }
        if (slot == 3) { return Metrics.num(info.calories) + " cal"; }
        return Metrics.elev(info.totalAscent, metric) + " ^";
    }

    hidden function hrPctOfMax(hr as Lang.Number or Null) as Lang.String {
        if (hr == null) { return "--"; }
        var maxHr = null;
        try {
            var zones = UserProfile.getHeartRateZones(UserProfile.HR_ZONE_SPORT_RUNNING);
            if (zones != null && zones.size() >= 6) { maxHr = zones[5] as Lang.Number; }
        } catch (ex) {}
        if (maxHr == null || maxHr <= 0) { return "--"; }
        return ((hr * 100) / maxHr).toString();
    }

    hidden function buildWorkoutHud(info as Activity.Info, metric as Lang.Boolean, u as Lang.String, stepInfo as Activity.WorkoutStepInfo) as Lang.String {
        var step = unwrapStep(stepInfo);

        var hrLine = "HR " + Metrics.num(info.currentHeartRate);
        if (step != null && step.targetType == Activity.WORKOUT_STEP_TARGET_HEART_RATE) {
            var lo = step.targetValueLow;
            var hi = step.targetValueHigh;
            if (lo > 100) { lo -= 100; }
            if (hi > 100) { hi -= 100; }
            hrLine += " [" + lo.toString() + "-" + hi.toString() + "]";
        } else {
            hrLine += " " + Metrics.hrZone(info.currentHeartRate);
        }

        var paceLine = Metrics.pace(info.currentSpeed, metric) + " /" + u;
        if (step != null && step.targetType == Activity.WORKOUT_STEP_TARGET_SPEED) {
            var paceFast = Metrics.pace(step.targetValueHigh.toFloat(), metric);
            var paceSlow = Metrics.pace(step.targetValueLow.toFloat(), metric);
            paceLine = Metrics.pace(info.currentSpeed, metric) + " [" + paceFast + "-" + paceSlow + "]";
        }

        var line3 = "Open";
        if (step != null) {
            if (step.durationType == Activity.WORKOUT_STEP_DURATION_TIME) {
                var remainSec = stepRemainingSec(info, step);
                if (remainSec != null && remainSec >= 0) {
                    line3 = Metrics.mmss(remainSec - 2) + " left";
                }
            } else if (step.durationType == Activity.WORKOUT_STEP_DURATION_DISTANCE) {
                var nowM = (info.elapsedDistance != null) ? info.elapsedDistance : 0.0;
                var remainM = step.durationValue - (nowM - mStepStartDistM);
                if (remainM >= 0) {
                    line3 = Metrics.dist(remainM, metric) + u + " left";
                }
            }
        }

        var line4 = Metrics.dist(info.elapsedDistance, metric) + u + "  " + Metrics.duration(info.timerTime);
        var remain = stepRemainingSec(info, step);
        if (remain != null && remain >= 0 && remain <= 10) {
            var nextInfo = nextStepInfo();
            if (nextInfo != null) {
                line4 = "--- Next: " + describeStep(nextInfo, metric) + " ---";
            }
        }

        return hrLine + "\n" + paceLine + "\n" + line3 + "\n" + line4;
    }

    hidden function currentStepInfo() as Activity.WorkoutStepInfo or Null {
        try { return Activity.getCurrentWorkoutStep(); } catch (ex) { return null; }
    }

    hidden function nextStepInfo() as Activity.WorkoutStepInfo or Null {
        try { return Activity.getNextWorkoutStep(); } catch (ex) { return null; }
    }

    hidden function unwrapStep(stepInfo as Activity.WorkoutStepInfo) as Activity.WorkoutStep or Null {
        var s = stepInfo.step;
        if (s == null) { return null; }
        if (s has :activeStep) {
            if (stepInfo.intensity == Activity.WORKOUT_INTENSITY_REST && (s has :restStep)) {
                return s.restStep;
            }
            return s.activeStep;
        }
        return s;
    }

    hidden function stepRemainingSec(info as Activity.Info, step as Activity.WorkoutStep or Null) as Lang.Number or Null {
        if (step == null) { return null; }
        if (step.durationType == Activity.WORKOUT_STEP_DURATION_TIME) {
            var nowMs = (info.timerTime != null) ? info.timerTime : 0;
            var elapsedSec = (nowMs - mStepStartTimeMs) / 1000;
            return step.durationValue.toNumber() - elapsedSec;
        }
        if (step.durationType == Activity.WORKOUT_STEP_DURATION_DISTANCE) {
            if (info.currentSpeed == null || info.currentSpeed < 0.3) { return null; }
            var nowM = (info.elapsedDistance != null) ? info.elapsedDistance : 0.0;
            var remainM = step.durationValue - (nowM - mStepStartDistM);
            if (remainM < 0) { return 0; }
            return (remainM / info.currentSpeed).toNumber();
        }
        return null;
    }

    hidden function describeStep(stepInfo as Activity.WorkoutStepInfo, metric as Lang.Boolean) as Lang.String {
        if (stepInfo has :name && stepInfo.name != null && (stepInfo.name as Lang.String).length() > 0) {
            var nm = stepInfo.name as Lang.String;
            if (nm.length() > 14) { nm = nm.substring(0, 13) + "."; }
            return nm;
        }
        var prefix = "Step";
        if (stepInfo has :intensity) {
            var intensity = stepInfo.intensity;
            if      (intensity == Activity.WORKOUT_INTENSITY_WARMUP)   { prefix = "Warm"; }
            else if (intensity == Activity.WORKOUT_INTENSITY_REST)     { prefix = "Rec"; }
            else if (intensity == Activity.WORKOUT_INTENSITY_RECOVERY) { prefix = "Rec"; }
            else if (intensity == Activity.WORKOUT_INTENSITY_COOLDOWN) { prefix = "Cool"; }
            else                                                       { prefix = "Run"; }
        }
        var step = unwrapStep(stepInfo);
        if (step == null) { return prefix; }
        if (step.durationType == Activity.WORKOUT_STEP_DURATION_TIME) {
            return prefix + " " + Metrics.mmss(step.durationValue.toNumber());
        }
        if (step.durationType == Activity.WORKOUT_STEP_DURATION_DISTANCE) {
            return prefix + " " + Metrics.dist(step.durationValue.toFloat(), metric) + (metric ? "km" : "mi");
        }
        return prefix;
    }

    hidden function buildSummary() as Lang.String {
        var info = mInfo;
        if (info == null) { return "Well done!"; }
        var metric = (System.getDeviceSettings().distanceUnits == System.UNIT_METRIC);
        var u = metric ? "km" : "mi";
        return Metrics.dist(info.elapsedDistance, metric) + u + "  " + Metrics.duration(info.timerTime) + "\n"
             + Metrics.pace(info.averageSpeed, metric) + " /" + u + " avg\n"
             + "HR " + Metrics.num(info.averageHeartRate) + " avg\n"
             + Metrics.elev(info.totalAscent, metric) + " ^";
    }

    hidden function checkBatteryWarning(isLeft as Lang.Boolean, pct as Lang.Number) as Void {
        var threshold = (pct <= 10) ? 10 : ((pct <= 20) ? 20 : 100);
        var prevLowest = isLeft ? mLeftWarnLevel : mRightWarnLevel;
        if (threshold < prevLowest) {
            if (isLeft) { mLeftWarnLevel = threshold; }
            else        { mRightWarnLevel = threshold; }
            triggerBatteryWarning();
        }
    }

    hidden function buildBatteryWarningText() as Lang.String {
        var leftStr  = (mLeftBatt  >= 0) ? (mLeftBatt.toString()  + "%") : "--";
        var rightStr = (mRightBatt >= 0) ? (mRightBatt.toString() + "%") : "--";
        return "LOW BATTERY\nL " + leftStr + "   R " + rightStr;
    }

    hidden function triggerBatteryWarning() as Void {
        mWarnUntilTick = mTick + 6;
        var text = buildBatteryWarningText();
        Log.add("BATT WARN " + text);
        sendFrame(text);
    }

    hidden function sendFrame(text as Lang.String) as Void {
        var bytes = text.toUtf8Array();
        var total = bytes.size();
        var maxSeq = total / TEXT_CHUNK;
        if (total % TEXT_CHUNK != 0 || total == 0) { maxSeq += 1; }
        var sync = mSyncSeq;
        mSyncSeq = (mSyncSeq + 1) % 0x100;
        if (mLastFrame != null) {
            var k = (mLastFrame as Lang.Array).size();
            Log.add("K" + k.toString()
                + " L" + (mLeftAckN - mLeftAckBase).toString()
                + " R" + (mRightAckN - mRightAckBase).toString()
                + " m" + mMissN.toString()
                + (mLastMissOp < 0 ? "" : ("/" + Log.hex([mLastMissOp]b)))
                + "  " + mLeftAckN.toString() + "/" + mRightAckN.toString()
                + "/" + mChunkN.toString());
        }
        mChunkN += maxSeq;
        mLeftAckBase  = mLeftAckN;
        mRightAckBase = mRightAckN;
        mFrameSettleTick = mTick;
        mFrameAckTimeout = 0;
        var chunks = [];
        for (var seq = 0; seq < maxSeq; seq++) {
            var start = seq * TEXT_CHUNK;
            var end = start + TEXT_CHUNK;
            if (end > total) { end = total; }
            var pkt = []b;
            pkt.add(CMD_TEXT);
            pkt.add(sync);
            pkt.add(maxSeq & 0xff);
            pkt.add(seq & 0xff);
            pkt.add(NEW_SCREEN);
            pkt.add(0x00);
            pkt.add(0x00);
            pkt.add(0x00);
            pkt.add(0x01);
            for (var i = start; i < end; i++) {
                pkt.add(bytes[i] & 0xff);
            }
            chunks.add(pkt);
            enqueueBoth(pkt);
        }
        mLastFrame = chunks;
        pump();
    }

    hidden function enqueueBoth(pkt as Lang.ByteArray) as Void {
        if (mLeftRx != null)  { mQueue.add({ :t => mLeftRx,  :b => pkt, :d => false, :side => SIDE_LEFT,  :nr => false }); }
        if (!SINGLE_ARM_DISPLAY && mRightRx != null) { mQueue.add({ :t => mRightRx, :b => pkt, :d => false, :side => SIDE_RIGHT, :nr => false }); }
    }

    hidden function enqueueBothFast(pkt as Lang.ByteArray) as Void {
        if (mLeftRx != null)  { mQueue.add({ :t => mLeftRx,  :b => pkt, :d => false, :side => SIDE_LEFT,  :nr => true }); }
        if (!SINGLE_ARM_DISPLAY && mRightRx != null) { mQueue.add({ :t => mRightRx, :b => pkt, :d => false, :side => SIDE_RIGHT, :nr => true }); }
    }

    hidden function sendInit() as Void {
        enqueueBoth([0x6E, 0x74]b);
        enqueueBoth([0x4D, 0xFB]b);
        enqueueBoth([0x27, 0x00]b);
        enqueueBoth([0x03, 0x0A]b);
        enqueueBoth([0x08, 0x06, 0x00, 0x00, 0x03, 0x00]b);
        sendTimeSync();
        pump();
    }

    hidden function enqueueHeartbeat() as Void {
        var seq = mBeatSeq % 0xff;
        mBeatSeq = (mBeatSeq + 1) % 0xff;
        var pkt = []b;
        pkt.add(CMD_HEARTBEAT);
        pkt.add(0x06);
        pkt.add(seq);
        pkt.add(0x00);
        pkt.add(0x04);
        pkt.add(seq);
        enqueueBoth(pkt);
    }

    hidden function sendTimeSync() as Void {
        try {
            var nowUtc = Time.now();
            var info = Time.Gregorian.info(nowUtc, Time.FORMAT_SHORT);
            var localSec = Time.Gregorian.moment({
                :year => info.year, :month => info.month, :day => info.day,
                :hour => info.hour, :minute => info.min, :second => info.sec
            }).value();
            var localMs = localSec.toLong() * 1000l;
            var seq = mTimeSyncSeq;
            mTimeSyncSeq = (mTimeSyncSeq + 1) % 0x100;
            var pkt = []b;
            pkt.add(0x06);
            pkt.add(0x14);
            pkt.add(0x00);
            pkt.add(seq);
            pkt.add(0x01);
            pkt.add(localSec & 0xFF);
            pkt.add((localSec >> 8) & 0xFF);
            pkt.add((localSec >> 16) & 0xFF);
            pkt.add((localSec >> 24) & 0xFF);
            pkt.add((localMs        & 0xFFl).toNumber());
            pkt.add(((localMs >>  8) & 0xFFl).toNumber());
            pkt.add(((localMs >> 16) & 0xFFl).toNumber());
            pkt.add(((localMs >> 24) & 0xFFl).toNumber());
            pkt.add(((localMs >> 32) & 0xFFl).toNumber());
            pkt.add(((localMs >> 40) & 0xFFl).toNumber());
            pkt.add(((localMs >> 48) & 0xFFl).toNumber());
            pkt.add(((localMs >> 56) & 0xFFl).toNumber());
            pkt.add(0x00);
            pkt.add(0x00);
            pkt.add(0x00);
            enqueueBoth(pkt);
            enqueueBoth([0x06, 0x06, 0x00, seq, 0x02, 0x01]b);
        } catch (ex) {
            Log.add("timeSync EX: " + ex.getErrorMessage());
        }
        pump();
    }

    hidden function sendBattQuery() as Void {
        enqueueBoth([0x2C, 0x01]b);
        pump();
    }

    function battPct() as Lang.Number {
        if (mLeftBatt < 0 && mRightBatt < 0) { return -1; }
        if (mLeftBatt  < 0) { return mRightBatt; }
        if (mRightBatt < 0) { return mLeftBatt; }
        return (mLeftBatt < mRightBatt) ? mLeftBatt : mRightBatt;
    }

    hidden function enqueueDesc(desc as Ble.Descriptor, bytes as Lang.ByteArray, side as Lang.Number) as Void {
        mQueue.add({ :t => desc, :b => bytes, :d => true, :side => side });
    }

    hidden function pump() as Void {
        if (mInFlight) { return; }
        if (mQueue.size() == 0) { return; }
        var e = mQueue[0];
        mQueue = mQueue.slice(1, null);
        mInFlight = true;
        mInFlightSide = e[:side] as Lang.Number;
        mInFlightAge = 0;
        mRetryN = 0;
        mInFlightChar = e[:d] ? null : (e[:t] as Ble.Characteristic);
        mInFlightBytes = e[:b] as Lang.ByteArray;
        try {
            if (e[:d]) {
                (e[:t] as Ble.Descriptor).requestWrite(e[:b]);
            } else {
                var wt = (e[:nr] == true) ? Ble.WRITE_TYPE_DEFAULT : Ble.WRITE_TYPE_WITH_RESPONSE;
                (e[:t] as Ble.Characteristic).requestWrite(e[:b], { :writeType => wt });
            }
        } catch (ex) {
            mInFlight = false;
            Log.add("writeEX len=" + (e[:b] as Lang.ByteArray).size().toString());
        }
    }

    hidden function resetLinks() as Void {
        mTick = 0;
        mQueue = []; mInFlight = false;
        mLeftRx = null; mRightRx = null; mLeftTx = null; mRightTx = null;
        mLeftReady = false; mRightReady = false; mFirstReadyTick = -1;
        mLeftAckN = 0; mRightAckN = 0; mRetryN = 0;
        mLeftAckBase = 0; mRightAckBase = 0; mFrameSettleTick = 0;
        mFrameAckTimeout = 0; mLastFrame = null;
        mLeftResendN = 0; mRightResendN = 0;
        mLeftBypassed = false; mRightBypassed = false;
        mInFlightChar = null; mInFlightBytes = null;
        mPairBusy = false; mInitDone = false;
        mLockedChannel = null; mLeftScan = null; mRightScan = null;
        mPairingSide = 0;
        mMode = MODE_UNKNOWN; mGlanceShownTick = -1; mGlanceLockoutTick = -1;
        mLeftBatt = -1; mRightBatt = -1; mTimeSyncSeq = 0;
        mLeftWarnLevel = 100; mRightWarnLevel = 100;
        mWarnUntilTick = -1;
        mStepStartTimeMs = 0; mStepStartDistM = 0.0;
    }

    hidden function split(s as Lang.String, sep as Lang.Char) as Lang.Array {
        var out = [];
        var cur = "";
        var chars = s.toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            if (chars[i] == sep) { out.add(cur); cur = ""; }
            else { cur = cur + chars[i].toString(); }
        }
        out.add(cur);
        return out;
    }
}
