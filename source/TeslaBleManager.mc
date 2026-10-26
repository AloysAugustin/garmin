using Toybox.BluetoothLowEnergy as Ble;
using Toybox.Timer;
using Toybox.System;
using Toybox.Lang;

// Low-level BLE transport for talking to a Tesla vehicle.
//
// The watch is the BLE central. It scans for the vehicle's advertisement (local
// name derived from the VIN), connects, enables notifications on the "from
// vehicle" characteristic, then exchanges length-prefixed protocol messages on
// the "to/from vehicle" characteristics.
//
// Connect IQ processes one GATT operation at a time, so writes are queued and
// sent one chunk at a time, each after the previous write completes. Incoming
// notifications are reassembled using the 2-byte big-endian length prefix that
// frames every protocol message.
class TeslaBleManager extends Ble.BleDelegate {

    // Tesla vehicle GATT identifiers (from the protocol spec).
    const SERVICE_UUID = "00000211-b2d1-43f0-9b88-960cebf8b91e";
    const TO_VEHICLE_UUID = "00000212-b2d1-43f0-9b88-960cebf8b91e";   // write
    const FROM_VEHICLE_UUID = "00000213-b2d1-43f0-9b88-960cebf8b91e"; // notify

    // Conservative per-write chunk size. The vehicle reassembles using the
    // length prefix, so smaller chunks are always safe.
    const CHUNK_SIZE = 20;
    const SCAN_TIMEOUT_MS = 20000;
    // Same framing guards as the reference client: no message is larger than
    // this, and a partial message older than RX_TIMEOUT_MS is discarded so a
    // lost chunk cannot desynchronize the length-prefix framing.
    const MAX_MESSAGE_SIZE = 1024;
    const RX_TIMEOUT_MS = 1000;

    hidden var mListener;          // object receiving high-level callbacks
    hidden var mTargetName;        // expected advertisement local name
    hidden var mServiceUuid;
    hidden var mToUuid;
    hidden var mFromUuid;

    hidden var mDevice;
    hidden var mWriteChar;
    hidden var mScanTimer;

    hidden var mWriteQueue;        // array of ByteArray chunks pending write
    hidden var mWriting;
    hidden var mInputBuffer;       // ByteArray accumulating notification data
    hidden var mLastRxMs;          // System.getTimer() of the last notification
    hidden var mScanning;
    hidden var mRegistered;

    function initialize(listener) {
        BleDelegate.initialize();
        mListener = listener;
        mWriteQueue = [];
        mWriting = false;
        mInputBuffer = []b;
        mScanning = false;
        mRegistered = false;
        mServiceUuid = Ble.stringToUuid(SERVICE_UUID);
        mToUuid = Ble.stringToUuid(TO_VEHICLE_UUID);
        mFromUuid = Ble.stringToUuid(FROM_VEHICLE_UUID);
    }

    // Must be called once, early, with BLE available. Registers the GATT
    // profile so the SDK knows which service/characteristics to expose.
    function setup() {
        Ble.setDelegate(self);
        if (!mRegistered) {
            Ble.registerProfile({
                :uuid => mServiceUuid,
                :characteristics => [
                    { :uuid => mToUuid },
                    {
                        :uuid => mFromUuid,
                        :descriptors => [ Ble.cccdUuid() ]
                    }
                ]
            });
            // mRegistered flips true in onProfileRegister.
        }
    }

    // Begin connecting to the vehicle whose advertisement local name is `name`.
    function connect(name) {
        mTargetName = name;
        mInputBuffer = []b;
        mLastRxMs = null;
        mWriteQueue = [];
        mWriting = false;
        startScan();
    }

    hidden function startScan() {
        mScanning = true;
        Ble.setScanState(Ble.SCAN_STATE_SCANNING);
        mScanTimer = new Timer.Timer();
        mScanTimer.start(method(:onScanTimeout), SCAN_TIMEOUT_MS, false);
    }

    function onScanTimeout() {
        if (mScanning) {
            stopScan();
            mListener.onBleError("Vehicle not found. Is it nearby and awake?");
        }
    }

    hidden function stopScan() {
        if (mScanning) {
            mScanning = false;
            Ble.setScanState(Ble.SCAN_STATE_OFF);
        }
        if (mScanTimer != null) {
            mScanTimer.stop();
            mScanTimer = null;
        }
    }

    function disconnect() {
        stopScan();
        if (mDevice != null) {
            Ble.unpairDevice(mDevice);
            mDevice = null;
        }
        mWriteChar = null;
    }

    // Send a complete protocol message: prepend the 2-byte big-endian length,
    // split into chunks, and queue them.
    function send(message) {
        var framed = []b;
        var len = message.size();
        framed.add((len >> 8) & 0xff);
        framed.add(len & 0xff);
        framed.addAll(message);

        var offset = 0;
        while (offset < framed.size()) {
            var end = offset + CHUNK_SIZE;
            if (end > framed.size()) {
                end = framed.size();
            }
            mWriteQueue.add(framed.slice(offset, end));
            offset = end;
        }
        if (!mWriting) {
            writeNext();
        }
    }

    hidden function writeNext() {
        if (mWriteQueue.size() == 0) {
            mWriting = false;
            return;
        }
        if (mWriteChar == null) {
            mListener.onBleError("Not connected");
            return;
        }
        mWriting = true;
        var chunk = mWriteQueue[0];
        mWriteQueue = mWriteQueue.slice(1, mWriteQueue.size());
        try {
            mWriteChar.requestWrite(chunk, { :writeType => Ble.WRITE_TYPE_WITH_RESPONSE });
        } catch (e) {
            mWriting = false;
            mListener.onBleError("Write failed");
        }
    }

    // --- BleDelegate callbacks ---------------------------------------------

    function onProfileRegister(uuid, status) {
        if (status == Ble.STATUS_SUCCESS) {
            mRegistered = true;
        } else {
            mListener.onBleError("Profile register failed");
        }
    }

    function onScanResults(scanResults) {
        for (var r = scanResults.next(); r != null; r = scanResults.next()) {
            if (matches(r)) {
                stopScan();
                try {
                    mDevice = Ble.pairDevice(r);
                } catch (e) {
                    mListener.onBleError("Connect failed");
                }
                return;
            }
        }
    }

    hidden function matches(scanResult) {
        var name = scanResult.getDeviceName();
        if (name != null) {
            // Another Tesla nearby advertises the same service UUID, so a
            // named advertisement must match our VIN-derived name exactly.
            return name.equals(mTargetName);
        }
        // Fall back to matching the Tesla service UUID only if the name wasn't
        // in the advertisement packet.
        var uuids = scanResult.getServiceUuids();
        if (uuids != null) {
            for (var u = uuids.next(); u != null; u = uuids.next()) {
                if (u.equals(mServiceUuid)) {
                    return true;
                }
            }
        }
        return false;
    }

    function onConnectedStateChanged(device, state) {
        if (state == Ble.CONNECTION_STATE_CONNECTED) {
            mDevice = device;
            enableNotifications();
        } else {
            mWriteChar = null;
            mListener.onBleDisconnected();
        }
    }

    hidden function enableNotifications() {
        var service = mDevice.getService(mServiceUuid);
        if (service == null) {
            mListener.onBleError("Tesla service not found");
            return;
        }
        mWriteChar = service.getCharacteristic(mToUuid);
        var fromChar = service.getCharacteristic(mFromUuid);
        if (mWriteChar == null || fromChar == null) {
            mListener.onBleError("Characteristics not found");
            return;
        }
        var cccd = fromChar.getDescriptor(Ble.cccdUuid());
        if (cccd == null) {
            mListener.onBleError("CCCD not found");
            return;
        }
        // [0x01, 0x00] = enable notifications.
        cccd.requestWrite([0x01, 0x00]b, {});
    }

    function onDescriptorWrite(descriptor, status) {
        if (status == Ble.STATUS_SUCCESS) {
            mListener.onBleReady();
        } else {
            mListener.onBleError("Could not subscribe to vehicle");
        }
    }

    function onCharacteristicWrite(characteristic, status) {
        if (status != Ble.STATUS_SUCCESS) {
            mWriting = false;
            mListener.onBleError("Write rejected by vehicle");
            return;
        }
        writeNext();
    }

    function onCharacteristicChanged(characteristic, value) {
        var now = System.getTimer();
        if (mLastRxMs != null && now - mLastRxMs > RX_TIMEOUT_MS) {
            mInputBuffer = []b;
        }
        mLastRxMs = now;
        mInputBuffer.addAll(value);
        drainInput();
    }

    // Extract any complete length-prefixed messages from the input buffer.
    hidden function drainInput() {
        while (mInputBuffer.size() >= 2) {
            var len = ((mInputBuffer[0] & 0xff) << 8) | (mInputBuffer[1] & 0xff);
            if (len > MAX_MESSAGE_SIZE) {
                mInputBuffer = []b; // garbage; resync on the next message
                break;
            }
            if (mInputBuffer.size() < 2 + len) {
                break; // wait for more chunks
            }
            var message = mInputBuffer.slice(2, 2 + len);
            mInputBuffer = mInputBuffer.slice(2 + len, mInputBuffer.size());
            mListener.onBleMessage(message);
        }
    }

    function onCharacteristicRead(characteristic, status, value) {
    }

    function onDescriptorRead(descriptor, status, value) {
    }

    function onScanStateChange(scanState, status) {
    }
}
