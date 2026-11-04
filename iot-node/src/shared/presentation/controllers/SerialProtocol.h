#ifndef SERIAL_PROTOCOL_H
#define SERIAL_PROTOCOL_H

#include <Arduino.h>

// Responses of the serial API. Keys have one or two characters to keep every line short
// (they travel over a 115200 baud link, and later over LoRa). Full reference with examples:
// docs/tundra/SERIAL_API.md
//
// Every response is one JSON object per line:
//
//   s   status        "ok" | "error"
//   m   message       human readable text (confirmations and errors)
//
// Command specific keys:
//
//   info            mc  MAC address            v   firmware variant ("coap", "isolated", ...)
//   sensor list     d   array of sensors, each:
//                       i   id      p   pin       t   type        dr  driver
//                       pr  precision           o   offset      iv  interval (ms)
//   wifi get        ss  SSID
//   coap get        h   host      pt  port
//   time get        t   Unix time (s)           v   clock valid (bool)
//   status          c   clock    {t: Unix time, v: valid}
//   (isolated)      b   battery  {mv: millivolts, p: percent}
//                   st  storage  {n: next seq, a: acked seq, pd: pending, f: free bytes,
//                                 tt: total bytes, fw: failed writes}
//                   pw  power    {bc: boot count, aw: total awake ms, rr: reset reason}
namespace SerialProtocol {

inline void ok(const char* message) {
    Serial.printf("{\"s\":\"ok\",\"m\":\"%s\"}\n", message);
}

inline void error(const char* message) {
    Serial.printf("{\"s\":\"error\",\"m\":\"%s\"}\n", message);
}

} // namespace SerialProtocol

#endif // SERIAL_PROTOCOL_H
