# Pruebas end-to-end

Pruebas en el navegador (Playwright) de la aplicación corriendo de verdad. Los nodos son **simulados** dentro de la página (`fake_node.mjs`) y hablan el protocolo real del firmware ([`docs/tundra/SERIAL_API.md`](../docs/tundra/SERIAL_API.md)), así que no hace falta una ESP32. La prueba de gráficos además envía mediciones por **CoAP real** al servidor.

## Requisitos

- Base de datos levantada (`docker compose --env-file .env up -d`) y el servidor corriendo (`mix phx.server`).
- Dependencias: `cd e2e && npm install`. Para usar un Chrome ya instalado en vez de descargar navegadores: `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install` y `CHROME_PATH=/ruta/a/chrome`.

## Ejecutar

```bash
cd e2e
npm test                    # todas, una tras otra
node device_sync.mjs 5000   # una sola (algunas aceptan argumentos)
HEADLESS=1 npm test         # sin ventana
```

| Variable      | Uso                                                 | Por defecto             |
| ------------- | --------------------------------------------------- | ----------------------- |
| `BASE_URL`    | Aplicación bajo prueba                              | `http://localhost:4000` |
| `CHROME_PATH` | Navegador a usar                                    | el de Playwright        |
| `HEADLESS`    | `1` para correr sin ventana                         | con ventana             |
| `SLOW_MO`     | Milisegundos entre acciones (para seguir la prueba) | `100`                   |

Las capturas quedan en `e2e/shots/`.

## Pruebas

| Archivo              | Qué verifica                                                                                                                                                                                       |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `definitions.mjs`    | Definiciones de lectura con tipo libre, sugerencias y validación; iniciar una lectura; diálogos de borrado (Escape, definición en uso); borrar lectura y luego la definición                       |
| `device_setup.mjs`   | `/devices/setup`: identificación por MAC, preset, agregar/editar sensores sincronizados, cambio en el nodo detectado, "Send all", "Delete all"                                                     |
| `device_sync.mjs`    | `/devices/sync`: extracción por USB con créditos, trama dañada reenviada, liberación tras confirmar, sin duplicados, hora corregida                                                                |
| `devices_health.mjs` | Devices: batería, almacenamiento, "visto hace" y alertas a partir del `status` del nodo; historial en el modal                                                                                     |
| `coap_sync.mjs`      | Almacenar y reenviar por CoAP real (`coap_sync.exs` simula el nodo): ventana, confirmación asíncrona, trama perdida y reenviada, sin inundar al servidor; el nodo aparece en Devices con su estado |
| `charts.mjs`         | Gráficos en vivo de una lectura: tooltip, estado de rango, tabla, tema oscuro, eje en UTC, mediciones en vivo por CoAP                                                                             |

## Datos de prueba

Cada prueba empieza ejecutando `cleanup.exs`, que borra lo que dejaron corridas anteriores:

- nodos con MAC simulada `02:00:00:00:E2:*` (con sus sensores y mediciones), sus estados de sincronización, reportes de estado y configuraciones de sensores;
- áreas y definiciones de lectura cuyo nombre empieza con `e2e-` (sus lecturas se borran en cascada).

Para limpiar a mano: `npm run cleanup` (desde `e2e/`).

| Script        | Uso                                                                             |
| ------------- | ------------------------------------------------------------------------------- |
| `inject.exs`  | Envía mediciones al servidor por CoAP/UDP como lo haría la ESP32                |
| `seed.exs`    | Crea un área, una definición y una lectura del nodo con 20 minutos de historial |
| `cleanup.exs` | Borra los datos de prueba                                                       |
