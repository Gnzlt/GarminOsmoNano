// The two checksums of a DJI DUML frame (Frame.mc): CRC8 over the first three
// header bytes and CRC16 over everything but the CRC16 itself. Parameters from
// KonradIT/DJI-ESP32-Remote mediaprotocol/duml.c; the tests check them against
// the reference frames quoted there.
import Toybox.Lang;

module Crc {

    // Poly 0x8C (0x31 reflected), seed 0x77, over b[from, to).
    function crc8(b as ByteArray, from as Number, to as Number) as Number {
        var crc = 0x77;
        for (var i = from; i < to; i++) {
            crc ^= b[i];
            for (var bit = 0; bit < 8; bit++) {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0x8C : crc >> 1;
            }
        }
        return crc;
    }

    // KERMIT poly 0x8408 (0x1021 reflected), seed 0x3692, over b[from, to).
    function crc16(b as ByteArray, from as Number, to as Number) as Number {
        var crc = 0x3692;
        for (var i = from; i < to; i++) {
            crc ^= b[i];
            for (var bit = 0; bit < 8; bit++) {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0x8408 : crc >> 1;
            }
        }
        return crc;
    }
}
