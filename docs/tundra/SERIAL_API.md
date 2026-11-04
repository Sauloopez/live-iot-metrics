# API serial del nodo

Protocolo entre el navegador (Web Serial, pantalla `/devices/setup`) y el firmware del nodo, a 115200 baudios. Un objeto JSON por línea en cada sentido.

- **Comandos** (navegador → nodo): `{"command": "...", "data": {...}}`.
- **Respuestas** (nodo → navegador): claves de **uno o dos caracteres** para mantener las líneas cortas, porque viajan por un enlace serial lento y más adelante por LoRa.

La fuente de verdad de las claves está en `iot-node/src/shared/presentation/controllers/SerialProtocol.h`; el navegador las traduce en `assets/js/hooks/web_serial_hook.js`.

## Respuesta común

| Clave | Significado | Valores                          |
| ----- | ----------- | -------------------------------- |
| `s`   | Estado      | `"ok"` o `"error"`               |
| `m`   | Mensaje     | Texto de confirmación o de error |

```json
{"s":"ok","m":"Sensor added"}
{"s":"error","m":"Unknown driver"}
```

Al arrancar, el nodo imprime `{"s":"ok","m":"Serial controller ready"}`; no responde a ningún comando.

## Comandos disponibles por configuración

| Comando  | `coap` | `isolated` |
| -------- | :----: | :--------: |
| `ping`   |   ✅   |     ✅     |
| `info`   |   ✅   |     ✅     |
| `sensor` |   ✅   |     ✅     |
| `wifi`   |   ✅   |     —      |
| `coap`   |   ✅   |     —      |
| `time`   |   —    |     ✅     |
| `status` |   —    |     ✅     |

Un comando no disponible responde `{"s":"error","m":"Unknown command"}`.

## `ping`

```json
→ {"command":"ping"}
← {"s":"ok","m":"pong"}
```

## `info`

Identifica el nodo.

```json
→ {"command":"info"}
← {"s":"ok","mc":"B4:BF:E9:04:E6:C4","v":"isolated"}
```

| Clave | Significado                                                             |
| ----- | ----------------------------------------------------------------------- |
| `mc`  | MAC de la estación WiFi (la misma que envían los nodos en red)          |
| `v`   | Variante del firmware: `coap`, `isolated`, `lora_field`, `lora_gateway` |

## `sensor`

```json
→ {"command":"sensor","data":{"action":"add","id":1,"pin":34,"type":"temperature","driver":"analog","precision":0.0806,"offset":0,"interval":10000}}
→ {"command":"sensor","data":{"action":"update", ...mismos campos}}
→ {"command":"sensor","data":{"action":"remove","id":1}}
→ {"command":"sensor","data":{"action":"list"}}
← {"s":"ok","d":[{"i":1,"p":34,"t":"temperature","dr":"analog","pr":0.0806,"o":0,"iv":10000}]}
```

Respuesta de `list`, cada elemento de `d`:

| Clave | Significado          | Campo del comando |
| ----- | -------------------- | ----------------- |
| `i`   | Id del sensor        | `id`              |
| `p`   | Pin (GPIO)           | `pin`             |
| `t`   | Tipo (`sensor_type`) | `type`            |
| `dr`  | Driver               | `driver`          |
| `pr`  | Precisión (factor)   | `precision`       |
| `o`   | Offset               | `offset`          |
| `iv`  | Intervalo en ms      | `interval`        |

## `wifi` (solo `coap`)

```json
→ {"command":"wifi","data":{"action":"set","ssid":"MiRed","password":"secreto"}}
← {"s":"ok","m":"WiFi config saved"}
→ {"command":"wifi","data":{"action":"get"}}
← {"s":"ok","ss":"MiRed"}
```

`ss`: SSID configurado. La contraseña nunca se devuelve.

## `coap` (solo `coap`)

```json
→ {"command":"coap","data":{"action":"set","host":"192.168.1.70","port":5683}}
← {"s":"ok","m":"CoAP config saved"}
→ {"command":"coap","data":{"action":"get"}}
← {"s":"ok","h":"192.168.1.70","pt":5683}
```

`h`: host del servidor · `pt`: puerto.

## `time` (nodos con reloj)

```json
→ {"command":"time","data":{"action":"set","ts":1762164450}}
← {"s":"ok","m":"Time set"}
→ {"command":"time","data":{"action":"get"}}
← {"s":"ok","t":1762164450,"v":true}
```

`t`: hora Unix en segundos (UTC) · `v`: si la hora es confiable (falso si el reloj nunca se ajustó o el DS3231 perdió la alimentación). `set` rechaza horas anteriores a 2024.

## `status` (solo `isolated`)

```json
→ {"command":"status"}
← {"s":"ok",
   "c":{"t":1762164450,"v":true},
   "b":{"mv":3912,"p":69},
   "st":{"n":1201,"a":1000,"pd":200,"f":2097152,"tt":2228224,"fw":0},
   "pw":{"bc":96,"aw":153000,"rr":8}}
```

(La respuesta real llega en una sola línea.)

| Objeto              | Clave | Significado                                                                    |
| ------------------- | ----- | ------------------------------------------------------------------------------ |
| `c` reloj           | `t`   | Hora Unix (s)                                                                  |
|                     | `v`   | Hora confiable                                                                 |
| `b` batería         | `mv`  | Voltaje en milivoltios                                                         |
|                     | `p`   | Porcentaje estimado (curva de una celda Li-ion)                                |
| `st` almacenamiento | `n`   | Siguiente `seq` que se asignará                                                |
|                     | `a`   | Último `seq` confirmado por el servidor                                        |
|                     | `pd`  | Mediciones pendientes de sincronizar                                           |
|                     | `f`   | Bytes libres en la partición de datos                                          |
|                     | `tt`  | Bytes totales de la partición de datos                                         |
|                     | `fw`  | Escrituras fallidas desde el arranque                                          |
| `pw` energía        | `bc`  | Despertares desde el último encendido                                          |
|                     | `aw`  | Tiempo total despierto (ms) desde el último encendido                          |
|                     | `rr`  | Causa del último reinicio (`esp_reset_reason_t`: 1 encendido, 8 deep sleep, …) |
