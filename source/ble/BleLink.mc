// The BLE side: find the Osmo Nano, pair, prepare its GATT service, and move
// frames. One GATT operation in flight, the next started from the previous
// one's callback; writes split into 20-byte chunks (the Connect IQ maximum).
//
// The Nano's GATT setup, from KonradIT/osmosis MEDIA_PROTOCOL.md ("missing any
// step: the camera ATT-acks every write and answers nothing"):
//   - service FFF0: FFF4 notifies, FFF5 takes write-without-response
//   - subscribe the CCCDs of both FFF4 and FFF5
//   - write 01 00 to the FFF4 value itself, with response, and settle ~200 ms
//   - frames at least 120 ms apart (Action Multicam's gap; Osmosis says 100):
//     back-to-back writes are dropped
// One step there is out of reach: the 500-byte MTU. Connect IQ stays at 23.
//
// Until a camera is chosen, the scan runs on and pairs nothing: the rider
// picks the camera from what it has seen (Camera.P_CHOOSE). After that the
// chosen camera is remembered (its ScanResult and name) and paired directly;
// attempts alternate between that and a scan for it. Disconnect pauses the
// link until the rider reconnects.
import Toybox.Application;
import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.System;

class BleLink extends BluetoothLowEnergy.BleDelegate {

    enum {
        L_OFF,
        L_REGISTER,
        L_SCAN,
        L_BACKOFF,    // between attempts
        L_CONNECT,    // paired, waiting for the connection
        L_SETUP,      // CCCDs and the FFF4 arm write
        L_SETTLE,     // the 200 ms after the arm write
        L_READY
    }

    // The setup writes, in order.
    enum {
        W_CCCD4,
        W_CCCD5,
        W_ARM,
        W_DONE
    }

    private const CHUNK = 20;
    private const FRAME_GAP = 120;
    private const WRITE_WAIT = 500;      // a write-without-response whose callback never came
    private const SETUP_TIMEOUT = 5000;
    private const ATTEMPT_MS = 15000;    // a scan window, or the wait for a connection
    private const BACKOFF_MS = 3000;
    private const SETTLE_MS = 200;
    private const STORE_CAMERA = "camera";
    private const STORE_NAME = "cameraName";   // the name the rider chose, matched on later scans

    private var _session as NanoSession? = null;
    private var _service as BluetoothLowEnergy.Uuid;
    private var _notifyUuid as BluetoothLowEnergy.Uuid;
    private var _writeUuid as BluetoothLowEnergy.Uuid;

    private var _l as Number = L_OFF;
    private var _since as Number = 0;
    private var _directNext as Boolean = true;
    private var _choosing as Boolean = false;   // no camera saved: scan, pair nothing
    private var _device as BluetoothLowEnergy.Device? = null;
    private var _pairedWith as BluetoothLowEnergy.ScanResult? = null;
    private var _notify as BluetoothLowEnergy.Characteristic? = null;
    private var _write as BluetoothLowEnergy.Characteristic? = null;
    private var _setupStep as Number = W_CCCD4;

    private var _seen as Array<BluetoothLowEnergy.ScanResult> = [] as Array<BluetoothLowEnergy.ScanResult>;
    private const SEEN_MAX = 60;
    private const LOG_FIRST = 60;     // every device is logged in full while the Nano is not found

    private var _frames as Array<ByteArray> = [] as Array<ByteArray>;
    private var _chunks as Array<ByteArray> = [] as Array<ByteArray>;
    private var _busy as Boolean = false;
    private var _opAt as Number = 0;
    private var _lastFrameAt as Number = -1000000;
    private var _lastChunkAt as Number = -1000000;
    private var _chunkGap as Number = 0;
    private var _assembler as FrameAssembler;

    function initialize() {
        BleDelegate.initialize();
        _service = uuid16("FFF0");
        _notifyUuid = uuid16("FFF4");
        _writeUuid = uuid16("FFF5");
        _assembler = new FrameAssembler();
    }

    function setSession(session as NanoSession) as Void {
        _session = session;
    }

    function start() as Void {
        if (!(Toybox has :BluetoothLowEnergy)) {
            phase(Camera.P_NO_BLE);
            return;
        }
        BluetoothLowEnergy.setDelegate(self);
        to(L_REGISTER);
        try {
            BluetoothLowEnergy.registerProfile({
                :uuid => _service,
                :characteristics => [
                    { :uuid => _notifyUuid, :descriptors => [BluetoothLowEnergy.cccdUuid()] },
                    { :uuid => _writeUuid, :descriptors => [BluetoothLowEnergy.cccdUuid()] }
                ]
            });
        } catch (e) {
            Log.add("register failed");
            phase(Camera.P_NO_BLE);
            to(L_OFF);
        }
    }

    function stop() as Void {
        if (!(Toybox has :BluetoothLowEnergy)) {
            return;
        }
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
        unpair();
        to(L_OFF);
    }

    // ---- For NanoSession, through BleTransport ---------------------------

    function sendFrame(frame as ByteArray, priority as Boolean) as Boolean {
        if (_l != L_READY) {
            return false;
        }
        if (priority) {
            var all = [frame] as Array<ByteArray>;
            all.addAll(_frames);
            _frames = all;
        } else {
            _frames.add(frame);
        }
        pump(System.getTimer());
        return true;
    }

    function queued() as Number {
        return _frames.size() + (_chunks.size() > 0 ? 1 : 0);
    }

    // Drop the camera and look again shortly.
    function restart() as Void {
        if (_l == L_SCAN) {
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
        }
        unpair();
        phase(savedCamera() != null ? Camera.P_SCAN : Camera.P_CHOOSE);
        to(L_BACKOFF);
    }

    // Disconnect: drop the camera and stay down until restart().
    function pause() as Void {
        if (_l == L_SCAN) {
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
        }
        unpair();
        Log.add("disconnected by the rider");
        phase(Camera.P_OFF);
        to(L_OFF);
    }

    function forget() as Void {
        Store.remove(STORE_CAMERA);
        Store.remove(STORE_NAME);
        _directNext = false;
        restart();
    }

    // Every 50 ms from the app's timer: the timeouts and the write pacing.
    function tick(now as Number) as Void {
        var age = now - _since;
        if (_l == L_READY) {
            if (_busy && now - _opAt > WRITE_WAIT) {
                // Write-without-response callbacks are not guaranteed: go on.
                _busy = false;
            }
            pump(now);
        } else if (_l == L_SETTLE && age >= SETTLE_MS) {
            ready();
        } else if (_l == L_SETUP && age > SETUP_TIMEOUT) {
            Log.add("GATT setup timeout");
            restart();
        } else if (((_l == L_SCAN && !_choosing) || _l == L_CONNECT) && age > ATTEMPT_MS) {
            if (_l == L_SCAN) {
                Log.add("scan window over: " + _seen.size().format("%d") + " devices seen, no Nano");
            } else {
                Log.add("no connection");
            }
            restart();
        } else if (_l == L_BACKOFF && age > BACKOFF_MS) {
            attempt();
        } else if (_l == L_REGISTER && age > SETUP_TIMEOUT) {
            Log.add("register timeout");
            attempt();
        }
    }

    // ---- Finding the camera --------------------------------------------

    function onProfileRegister(uuid as BluetoothLowEnergy.Uuid, status as BluetoothLowEnergy.Status) as Void {
        if (_l != L_REGISTER) {
            return;
        }
        if (status != BluetoothLowEnergy.STATUS_SUCCESS) {
            Log.add("register status " + status.format("%d"));
            phase(Camera.P_NO_BLE);
            to(L_OFF);
            return;
        }
        Log.add("profile registered");
        attempt();
    }

    private function attempt() as Void {
        var saved = savedCamera();
        _choosing = saved == null;
        phase(_choosing ? Camera.P_CHOOSE : Camera.P_SCAN);
        if (_session != null && saved != null) {
            (_session as NanoSession).name = savedName();
        }
        if (saved != null && _directNext) {
            _directNext = false;
            Log.add("pairing the saved camera");
            pair(saved);
            return;
        }
        _directNext = true;
        Log.add("scanning");
        to(L_SCAN);
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
    }

    // Named devices seen, likely Nanos first, then nearest first.
    function candidates() as Array<Candidate> {
        var named = named();
        var out = [] as Array<Candidate>;
        for (var pass = 0; pass < 2; pass++) {
            for (var i = 0; i < named.size(); i++) {
                var nano = isNano(named[i]);
                if (nano == (pass == 0)) {
                    out.add(new Candidate(named[i].getDeviceName() as String, named[i].getRssi(), nano));
                }
            }
        }
        return out;
    }

    // The rider points at the camera: remember it and its name, and pair now.
    function choose(name as String) as Void {
        var named = named();
        var r = null as BluetoothLowEnergy.ScanResult?;
        for (var i = 0; i < named.size() && r == null; i++) {
            if (name.equals(named[i].getDeviceName())) {
                r = named[i];
            }
        }
        if (r == null) {
            return;
        }
        _choosing = false;
        Store.put(STORE_CAMERA, r);
        Store.put(STORE_NAME, name);
        Log.add("chosen: " + name);
        if (_l == L_SCAN) {
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
        }
        unpair();
        pair(r as BluetoothLowEnergy.ScanResult);
    }

    private function named() as Array<BluetoothLowEnergy.ScanResult> {
        var out = [] as Array<BluetoothLowEnergy.ScanResult>;
        for (var i = 0; i < _seen.size(); i++) {
            if (_seen[i].getDeviceName() != null) {
                out.add(_seen[i]);
            }
        }
        // Nearest first: insertion sort on RSSI, the list is short.
        for (var i = 1; i < out.size(); i++) {
            var x = out[i];
            var j = i - 1;
            while (j >= 0 && out[j].getRssi() < x.getRssi()) {
                out[j + 1] = out[j];
                j--;
            }
            out[j + 1] = x;
        }
        return out;
    }

    private function chosenName() as String? {
        var v = null;
        try {
            v = Application.Storage.getValue(STORE_NAME);
        } catch (e) {
        }
        return v instanceof String ? v : null;
    }

    // What the screen calls the saved camera.
    private function savedName() as String {
        var n = chosenName();
        if (n != null) {
            return n;
        }
        var r = savedCamera();
        var rn = r != null ? r.getDeviceName() : null;
        return rn != null ? rn : "Osmo Nano";
    }

    private function savedCamera() as BluetoothLowEnergy.ScanResult? {
        var v = null;
        try {
            v = Application.Storage.getValue(STORE_CAMERA);
        } catch (e) {
        }
        return v instanceof BluetoothLowEnergy.ScanResult ? v : null;
    }

    // Every result goes to the picker's list. With a camera saved, the
    // closest match in this batch is paired.
    function onScanResults(scanResults as BluetoothLowEnergy.Iterator) as Void {
        if (_l != L_SCAN) {
            return;
        }
        var best = null as BluetoothLowEnergy.ScanResult?;
        var result = scanResults.next() as BluetoothLowEnergy.ScanResult?;
        while (result != null) {
            note(result);
            if (!_choosing && isSaved(result) && (best == null || result.getRssi() > best.getRssi())) {
                best = result;
            }
            result = scanResults.next() as BluetoothLowEnergy.ScanResult?;
        }
        if (best != null) {
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
            pair(best);
        }
    }

    // The saved camera, by its name; a camera saved without one (an older
    // install) matches any Nano.
    private function isSaved(result as BluetoothLowEnergy.ScanResult) as Boolean {
        var chosen = chosenName();
        if (chosen == null) {
            return isNano(result);
        }
        var n = result.getDeviceName();
        return n != null && n.equals(chosen);
    }

    // DJI's manufacturer data naming a Nano (Nano.advert), or the name it
    // alternates with, "OsmoNano-XXXX".
    private function isNano(result as BluetoothLowEnergy.ScanResult) as Boolean {
        if (Nano.advert(result.getManufacturerSpecificData(Nano.DJI_COMPANY) as ByteArray?) != Nano.ADV_NOT_NANO) {
            return true;
        }
        var n = result.getDeviceName();
        if (n != null && n.toUpper().find("OSMONANO") != null) {
            return true;
        }
        return Nano.rawAdvert(result.getRawData()) != Nano.ADV_NOT_NANO;
    }

    // Count each device once, keeping its newest result (a fresh RSSI and,
    // once it arrives, its name), and log it: the first few in full, and every
    // one whose advert carries DJI's company id or an Osmo-like name.
    private function note(result as BluetoothLowEnergy.ScanResult) as Void {
        for (var i = 0; i < _seen.size(); i++) {
            if (result.isSameDevice(_seen[i])) {
                if (result.getDeviceName() != null || _seen[i].getDeviceName() == null) {
                    _seen[i] = result;
                }
                return;
            }
        }
        if (_seen.size() >= SEEN_MAX) {
            return;
        }
        _seen.add(result);
        if (_session != null) {
            (_session as NanoSession).seen = _seen.size();
        }
        var n = result.getDeviceName();
        var raw = result.getRawData();
        var upper = n != null ? n.toUpper() : "";
        var djiLike = Nano.rawIsDji(raw) || upper.find("OSMO") != null || upper.find("DJI") != null
                || upper.find("NANO") != null;
        var fff0 = Nano.rawHasFff0(raw);
        if (djiLike || fff0 || _seen.size() <= LOG_FIRST) {
            Log.add("seen " + (n != null ? n : "-") + " rssi " + result.getRssi().format("%d")
                    + (djiLike ? " DJI" : "") + (fff0 ? " FFF0" : "") + " raw " + Log.hex(raw));
        }
    }

    private function pair(result as BluetoothLowEnergy.ScanResult) as Void {
        try {
            _device = BluetoothLowEnergy.pairDevice(result);
        } catch (e) {
            Log.add("pair failed");
            _device = null;
        }
        if (_device == null) {
            restart();
            return;
        }
        _pairedWith = result;
        var n = result.getDeviceName();
        if (_session != null) {
            (_session as NanoSession).name = n != null ? n : savedName();
        }
        var adv = Nano.advert(result.getManufacturerSpecificData(Nano.DJI_COMPANY) as ByteArray?);
        Log.add("pairing " + (n != null ? n : "camera") + " rssi " + result.getRssi().format("%d")
                + (adv == Nano.ADV_ASLEEP ? " asleep" : adv == Nano.ADV_AWAKE ? " awake" : ""));
        if (_session != null) {
            (_session as NanoSession).asleep = adv == Nano.ADV_ASLEEP;
        }
        phase(Camera.P_CONNECT);
        to(L_CONNECT);
        if ((_device as BluetoothLowEnergy.Device).isConnected()) {
            setup(_device as BluetoothLowEnergy.Device);
        }
    }

    private function unpair() as Void {
        if (_device != null) {
            try {
                BluetoothLowEnergy.unpairDevice(_device as BluetoothLowEnergy.Device);
            } catch (e) {
            }
        }
        var wasReady = _l == L_READY;
        _device = null;
        _notify = null;
        _write = null;
        _frames = [] as Array<ByteArray>;
        _chunks = [] as Array<ByteArray>;
        _busy = false;
        _assembler.reset();
        if (wasReady && _session != null) {
            (_session as NanoSession).onLinkDown();
        }
    }

    // ---- Connection and GATT setup -------------------------------------

    function onConnectedStateChanged(device as BluetoothLowEnergy.Device, state as BluetoothLowEnergy.ConnectionState) as Void {
        if (_device == null) {
            return;
        }
        if (state == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
            if (_l == L_CONNECT) {
                setup(device);
            }
            return;
        }
        Log.add("disconnected");
        restart();
    }

    private function setup(device as BluetoothLowEnergy.Device) as Void {
        var svc = device.getService(_service);
        if (svc == null) {
            Log.add("no FFF0 service");
            restart();
            return;
        }
        _notify = svc.getCharacteristic(_notifyUuid);
        _write = svc.getCharacteristic(_writeUuid);
        if (_notify == null || _write == null) {
            Log.add("no FFF4/FFF5");
            restart();
            return;
        }
        to(L_SETUP);
        _setupStep = W_CCCD4;
        nextSetupWrite();
    }

    // CCCD of FFF4, CCCD of FFF5 (if it has one), then 01 00 to FFF4 itself.
    private function nextSetupWrite() as Void {
        _busy = true;
        _opAt = System.getTimer();
        try {
            if (_setupStep == W_CCCD4 || _setupStep == W_CCCD5) {
                var c = (_setupStep == W_CCCD4 ? _notify : _write) as BluetoothLowEnergy.Characteristic;
                var d = c.getDescriptor(BluetoothLowEnergy.cccdUuid());
                if (d == null) {
                    Log.add("no CCCD on " + (_setupStep == W_CCCD4 ? "FFF4" : "FFF5"));
                    _busy = false;
                    _setupStep++;
                    nextSetupWrite();
                    return;
                }
                d.requestWrite([0x01, 0x00]b);
            } else if (_setupStep == W_ARM) {
                (_notify as BluetoothLowEnergy.Characteristic).requestWrite([0x01, 0x00]b,
                        { :writeType => BluetoothLowEnergy.WRITE_TYPE_WITH_RESPONSE });
            } else {
                _busy = false;
                to(L_SETTLE);
            }
        } catch (e) {
            Log.add("setup write " + _setupStep.format("%d") + " threw");
            _busy = false;
            _setupStep++;
            nextSetupWrite();
        }
    }

    function onDescriptorWrite(descriptor as BluetoothLowEnergy.Descriptor, status as BluetoothLowEnergy.Status) as Void {
        if (_l != L_SETUP || !_busy) {
            return;
        }
        _busy = false;
        if (status != BluetoothLowEnergy.STATUS_SUCCESS) {
            Log.add("CCCD " + (_setupStep == W_CCCD4 ? "FFF4" : "FFF5") + " status " + status.format("%d"));
            if (_setupStep == W_CCCD4) {
                restart();   // no notifications, no replies
                return;
            }
        }
        _setupStep++;
        nextSetupWrite();
    }

    function onCharacteristicWrite(characteristic as BluetoothLowEnergy.Characteristic, status as BluetoothLowEnergy.Status) as Void {
        if (_l == L_SETUP && _busy) {
            _busy = false;
            if (status != BluetoothLowEnergy.STATUS_SUCCESS) {
                Log.add("FFF4 arm status " + status.format("%d"));
            }
            _setupStep++;
            nextSetupWrite();
            return;
        }
        if (_l != L_READY || !_busy) {
            return;
        }
        _busy = false;
        if (status != BluetoothLowEnergy.STATUS_SUCCESS) {
            Log.add("write status " + status.format("%d"));
        }
        pump(System.getTimer());
    }

    private function ready() as Void {
        to(L_READY);
        _chunkGap = Settings.number("chunkGap", 0);
        var r = _pairedWith;
        if (r != null) {
            Store.put(STORE_CAMERA, r);
        }
        var n = r != null ? r.getDeviceName() : null;
        Log.add("GATT ready");
        if (_session != null) {
            (_session as NanoSession).onLinkUp(n != null ? n : "Osmo Nano");
        }
    }

    // ---- Data ----------------------------------------------------------

    // The next chunk of the current frame (after the chunk gap), or the next
    // frame (FRAME_GAP after the last one began).
    private function pump(now as Number) as Void {
        if (_busy || _write == null) {
            return;
        }
        if (_chunks.size() == 0) {
            if (_frames.size() == 0 || now - _lastFrameAt < FRAME_GAP) {
                return;
            }
            var frame = _frames[0];
            _frames = _frames.slice(1, null);
            for (var i = 0; i < frame.size(); i += CHUNK) {
                _chunks.add(frame.slice(i, i + CHUNK < frame.size() ? i + CHUNK : frame.size()));
            }
            _lastFrameAt = now;
        } else if (now - _lastChunkAt < _chunkGap) {
            return;
        }
        var chunk = _chunks[0];
        _chunks = _chunks.slice(1, null);
        _lastChunkAt = now;
        _busy = true;
        _opAt = now;
        try {
            (_write as BluetoothLowEnergy.Characteristic).requestWrite(chunk,
                    { :writeType => BluetoothLowEnergy.WRITE_TYPE_DEFAULT });
        } catch (e) {
            _busy = false;
            Log.add("write threw");
        }
    }

    function onCharacteristicChanged(characteristic as BluetoothLowEnergy.Characteristic, value as ByteArray) as Void {
        if (!characteristic.getUuid().equals(_notifyUuid)) {
            Log.rx(value);
            return;   // FFF5 notifies too; only FFF4 carries replies
        }
        var frames = _assembler.feed(value);
        if (frames.size() == 0) {
            Log.rx(value);   // not a frame start: noise, or a continuation
        }
        for (var i = 0; i < frames.size(); i++) {
            if (_session != null) {
                (_session as NanoSession).onFrame(frames[i]);
            }
        }
    }

    // ---- Helpers -------------------------------------------------------

    private function phase(p as Number) as Void {
        if (_session != null) {
            (_session as NanoSession).onLinkPhase(p);
        }
    }

    private function to(l as Number) as Void {
        _l = l;
        _since = System.getTimer();
    }

    // The Bluetooth SIG base UUID with a 16-bit id.
    private function uuid16(short as String) as BluetoothLowEnergy.Uuid {
        return BluetoothLowEnergy.stringToUuid("0000" + short + "-0000-1000-8000-00805f9b34fb");
    }
}
