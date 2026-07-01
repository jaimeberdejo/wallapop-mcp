# Test Matrix — 100 cases

Evidence basis: `pnpm test` run on 2026-07-02 → **108 passed, 1 skipped (109), 13 test files**, 0 failed.
`pnpm typecheck` / `pnpm lint` / `pnpm build` / `npm pack --dry-run` all exit 0. Live suite
(`WALLAPOP_LIVE_TESTS=1`) was **not** run against the real API during this audit (opt-in, not
executed here — see `TEST_REPORT.md` for why). One fix was applied mid-audit (P1 bug #59, see
`BUGS_AND_RISKS.md`); rows below reflect **post-fix** state, with "Resultado observado" noting the
pre-fix behavior where relevant.

| ID | Tipo | Área | Caso | Input/Setup | Resultado esperado | Resultado observado | Estado | Severidad | Notas |
|---|---|---|---|---|---|---|---|---|---|
| 1 | CLI | Packaging | Instalar dependencias desde cero | `pnpm install` | Resuelve sin error | "Already up to date", 0 errores | PASS | INFO | Lockfile ya resuelto |
| 2 | CLI | Packaging | `pnpm test` limpio | `pnpm test` | Todo verde | 108 passed, 1 skipped, 0 failed | PASS | INFO | Incluye 91 tests nuevos de esta auditoría |
| 3 | CLI | Packaging | `pnpm typecheck` | `tsc --noEmit` | Exit 0 | Exit 0, sin errores | PASS | INFO | |
| 4 | CLI | Packaging | `pnpm lint` | `eslint .` | Exit 0 | Exit 0 tras corregir 2 `no-unused-vars` en test nuevo | PASS | INFO | Ver Notas de auditoría — error introducido y corregido en el mismo ciclo |
| 5 | CLI | Packaging | `pnpm build` | `tsup` | Bundle único generado | `dist/index.js` 1.23MB, build en 113-121ms | PASS | INFO | |
| 6 | CLI | Packaging | `dist/index.js` existe tras build | `ls dist/` | Archivo presente | Presente, con shebang `#!/usr/bin/env node` | PASS | INFO | |
| 7 | CLI | Packaging | `pnpm start` arranca sin crash | `node dist/index.js` con stdin abierto (pipe, no EOF) | Proceso sigue vivo esperando input | Sigue vivo tras 1s; con stdin `/dev/null` (EOF inmediato) el proceso termina limpio — comportamiento correcto de un transporte stdio, no un crash | PASS | INFO | Primera prueba con `/dev/null` fue un falso negativo de metodología, no un bug — documentado y re-verificado |
| 8 | CLI | Packaging | `npm pack --dry-run` contenido | `npm pack --dry-run` | Solo `dist/`, `README.md`, `LICENSE`, `package.json` | Exactamente esos 4 archivos, 204.6kB empaquetado | PASS | INFO | |
| 9 | CLI | Packaging | `bin` apunta al build correcto | `package.json` → `"bin": {"wallapop-mcp": "dist/index.js"}` | Coincide con salida de `tsup` | Coincide | PASS | INFO | |
| 10 | CLI | Packaging | `npx wallapop-mcp` funciona si está publicado | `npx -y wallapop-mcp@0.1.1` + `tools/list` real vía npm registry | Debe fallar o advertir claramente si no publicado | **Publicado de verdad** (v0.1.0 2026-07-01T21:59:57Z, v0.1.1 2026-07-01T22:11:17Z, `npm view` confirma). `npx` real devuelve `tools/list` con los 2 tools correctos | PASS (pero doc desactualizada) | P2 | **Discrepancia doc/realidad**: `docs/STATE.md` afirma "not yet published to npm" — es falso, ya está publicado desde ayer. Ver `BUGS_AND_RISKS.md` |
| 11 | MCP-Smoke | Protocol | `tools/list` vía cliente in-memory | `client.listTools()` | Resuelve sin error | Resuelve sin error | PASS | INFO | |
| 12 | MCP-Smoke | Protocol | Tools exactas expuestas | `result.tools.map(t=>t.name).sort()` | `["list_categories","search"]` | Coincide exactamente, sin extras | PASS | INFO | |
| 13 | MCP-Smoke | Protocol | Schema de `search` | Inspeccionar `inputSchema` serializado | 10 propiedades, todas opcionales | `keywords, categoryId, minPrice, maxPrice, distanceInKm, orderBy, latitude, longitude, nextPage, maxResults` — sin `required` | PASS | INFO | |
| 14 | MCP-Smoke | Protocol | Schema de `list_categories` | Inspeccionar `inputSchema` | 1 propiedad opcional `query` | Coincide | PASS | INFO | |
| 15 | MCP-Smoke | Protocol | `list_categories` sin args | `callTool({name:"list_categories",arguments:{}})` | Éxito, JSON array | `content[0].type==="text"`, parsea a array | PASS | INFO | |
| 16 | MCP-Smoke | Protocol | `list_categories` con query válida | `{query:"tech"}` | Éxito, array (posiblemente vacío) | Éxito, array válido | PASS | INFO | |
| 17 | MCP-Smoke | Protocol | `search` con `keywords:"iphone"`, fetch mockeado | Mock `fetchImpl` devuelve 0 items | Éxito, `listings:[]` | Éxito, `listings:[]`, `nextPage` ausente | PASS | INFO | |
| 18 | MCP-Smoke | Protocol | Respuesta MCP es JSON parseable | Ambas tool calls anteriores | `JSON.parse` no lanza | No lanza en ningún caso probado | PASS | INFO | |
| 19 | MCP-Smoke | Protocol | Errores de tool → error MCP claro | Mock HTTP 500 | `isError:true`, texto legible | `isError:true`, texto matchea `/500\|fail/i` | PASS | INFO | |
| 20 | MCP-Smoke | Protocol | Sin logs ruidosos en stdout/stderr (stdio) | Grep `console.*`/`process.std*.write` en `src/**` y `dist/index.js` | Ninguno en el camino de ejecución de las 2 tools | Ninguno en `src/**`; en `dist/index.js` solo `console.warn` del SDK vendorizado (validación de nombres de tool, no se dispara con nuestros nombres) y menciones en JSDoc no ejecutable | PASS | INFO | Canal stdio limpio |
| 21 | Unit | Categories | Sin query → solo top-level | `searchCategories(generatedCategories)` | `path.length===0` únicamente | Coincide exactamente con filtro manual | PASS | INFO | |
| 22 | Unit | Categories | Case-insensitive | `"tech"` vs `"TECH"` | Mismo resultado | Mismo resultado, mismo orden | PASS | INFO | |
| 23 | Unit | Categories | Query con acentos | `"musica"` vs `"música"` (fixture local; `generated.ts` no tiene nombres acentuados) | Idealmente ambos matchean | Solo `"música"` matchea — **no hay plegado de acentos** | PASS (documenta comportamiento actual) | P3 | Mejora de UX recomendada para queries generadas por LLM |
| 24 | Unit | Categories | Query con espacios laterales | `"  tech  "` | Idealmente igual que `"tech"` trimeado | Devuelve `[]` — **no hace trim** | PASS (documenta comportamiento actual) | P3 | Mejora de UX recomendada |
| 25 | Unit | Categories | Query vacía `""` | `searchCategories(cats,"")` | Igual que sin query | Igual que sin query (falsy) | PASS | INFO | |
| 26 | Unit | Categories | Query inexistente | `"zzzznonexistentzzzz"` | `[]` | `[]` | PASS | INFO | |
| 27 | Unit | Categories | Match en categoría profunda | `"Car security"` (id 10335, depth 2) | Encuentra el nodo con `path` correcto | Encontrado, `path` correcto | PASS | INFO | |
| 28 | Unit | Categories | Cada categoría tiene `id`/`name`/`path` | Iterar las 997 entradas de `generatedCategories` | Todos definidos y con tipo correcto | Confirmado en las 997 entradas | PASS | INFO | |
| 29 | Unit | Categories | `path` excluye la propia categoría | Invariante sobre las 997 entradas | Ningún `path` termina en el propio `name` | 1 excepción real: id 10067 "Movies & series" es hija de OTRO nodo también llamado "Movies & series" — coincidencia de datos de Wallapop, no bug de `flattenCategories` | PASS (excepción documentada y explicada) | INFO | No es un bug de la lógica de flatten |
| 30 | Unit | Categories | Sin IDs duplicados | `new Set(ids).size === ids.length` | Igual | 997 === 997 | PASS | INFO | |
| 31 | Unit | Search-Request | Solo `keywords` | `buildSearchRequest({keywords:"iphone"})` | `keywords` set, lat/lng Barcelona, resto ausente | Coincide | PASS | INFO | |
| 32 | Unit | Search-Request | Sin coordenadas → Barcelona centro | Input vacío o solo keywords | lat/lng === `BARCELONA_CENTER` | Coincide exactamente | PASS | INFO | |
| 33 | Unit | Search-Request | Coordenadas explícitas `0,0` no sobreescritas | `{latitude:0,longitude:0}` | Se respeta `0`, no se usa fallback | `"0"`/`"0"` — confirma uso de `??` y no `\|\|` | PASS | INFO | Caso trampa clásico verificado correctamente |
| 34 | Unit | Search-Request | `categoryId` → `category_ids` | `{categoryId:12465}` | `category_ids=12465` | Coincide | PASS | INFO | |
| 35 | Unit | Search-Request | `minPrice` → `min_sale_price` | `{minPrice:100}` | `min_sale_price=100` | Coincide | PASS | INFO | |
| 36 | Unit | Search-Request | `maxPrice` → `max_sale_price` | `{maxPrice:500}` | `max_sale_price=500` | Coincide | PASS | INFO | |
| 37 | Unit | Search-Request | `distanceInKm` → metros | `{distanceInKm:20}` | `distance=20000` | Coincide | PASS | INFO | |
| 38 | Unit | Search-Request | `orderBy` pasa tal cual | `"price_low_to_high"` y `"bogus_order"` | Ambos pasan sin validar | Ambos pasan sin validar — **no hay allowlist de valores legales** | PASS (documenta comportamiento) | P2 | Ver test 97/LLM-UX: no hay forma de saber qué valores acepta Wallapop |
| 39 | Unit | Search-Request | `nextPage` pasa tal cual | Cursor opaco | Igual, sin tocar | Igual | PASS | INFO | |
| 40 | Unit | Search-Request | Headers fijos presentes | Cualquier input | 4 headers fijos siempre | Presentes y no influidos por el input | PASS | INFO | |
| 41 | Unit | Search-Request | `filters_source`/`source` fijos | Cualquier input | Siempre presentes, no sobreescribibles | Confirmado — no existe campo para overridearlos | PASS | INFO | |
| 42 | Unit | Search-Request | Keywords con espacios | `"iphone 13 pro"` | Round-trip exacto, URL percent-encoded | Round-trip exacto vía `.get()`; `url.toString()` codifica el espacio | PASS | INFO | |
| 43 | Unit | Search-Request | Keywords Unicode | `"cámara réflex ñ"` | Round-trip exacto | Round-trip exacto | PASS | INFO | |
| 44 | Unit | Search-Request | Keywords con símbolos | `"iphone 13 + funda / 128gb"` | Round-trip exacto | Round-trip exacto | PASS | INFO | |
| 45 | Unit | Search-Request | Intento de query injection | `"iphone&latitude=0&extra=1"` como valor de `keywords` | No crea params extra, no hijackea `latitude` | Un solo param `keywords` con el string literal completo; `latitude` sigue siendo el valor real (Barcelona) | PASS | INFO | `URLSearchParams.set` es seguro por diseño — no hay vulnerabilidad |
| 46 | Unit | Pagination | Default `maxResults` (40) | Página de 40 items, sin `next_page` | 40 listings, 1 fetch | Coincide | PASS | INFO | |
| 47 | Unit | Pagination | `maxResults:1` | Página con muchos items | 1 listing, 1 fetch (no sobre-fetchea) | Coincide | PASS | INFO | |
| 48 | Unit | Pagination | `maxResults:39` | Página de 40 | 39 listings | Coincide | PASS | INFO | |
| 49 | Unit | Pagination | `maxResults:40` | Página exacta de 40, sin next_page | 40 listings, 1 fetch | Coincide | PASS | INFO | |
| 50 | Unit | Pagination | `maxResults:41` | 2 páginas de 40 | Fuerza 2º fetch, 41 total | Coincide | PASS | INFO | |
| 51 | Unit | Pagination | `maxResults:200` | 5 páginas de 40 con cursores | 200 listings, 5 fetch | Coincide | PASS | INFO | |
| 52 | Unit | Pagination | `maxResults:201` | — | Capea a 200 | Capea exactamente a 200 | PASS | INFO | |
| 53 | Unit | Pagination | `maxResults:500` | — | Capea a 200, ≤5 fetch | Capea a 200, ≤5 fetch | PASS | INFO | |
| 54 | Unit | Pagination | Sin `next_page` → para | Página con items, sin cursor | Para tras 1 fetch aunque no se alcance maxResults | Coincide | PASS | INFO | |
| 55 | Unit | Pagination | `next_page` presente pero `items:[]` | — | Para inmediatamente, 0 listings | Para tras 1 fetch, 0 listings | PASS | INFO | Caso borde importante correctamente manejado |
| 56 | Unit | Pagination | Cursor opaco pasa idéntico | Cursor base64-like | Idéntico en la 1ª llamada | Idéntico | PASS | INFO | |
| 57 | Unit | Pagination | Cursor con caracteres especiales | `"cursor+with/slashes=and&weird?chars#here"` | Round-trip exacto | Round-trip exacto vía `URLSearchParams` | PASS | INFO | |
| 58 | Unit | Pagination | Riesgo de bucle infinito | Upstream simulado que SIEMPRE devuelve el mismo cursor + items no vacíos | Debe terminar, acotado por `maxResults` | Termina, ≤200 listings, ≤5 fetch. **No existe guarda de iteración independiente** — el único límite es el cap de 200 aplicado ANTES del loop | PASS (sin bug hoy) | P3 | Nota de diseño: si el cap de 200 se eliminara alguna vez, esto colgaría indefinidamente. Documentado, no es un bug actual |
| 59 | Unit | Normalization | Mapea `id` | Fixture con id conocido | Passthrough exacto | Coincide | PASS | INFO | |
| 60 | Unit | Normalization | Mapea `title` | Título con emoji/símbolos | Passthrough exacto, sin mangling | Coincide | PASS | INFO | |
| 61 | Unit | Normalization | Mapea `description` | Descripción multilínea | Passthrough exacto incl. `\n` | Coincide | PASS | INFO | |
| 62 | Unit | Normalization | `price.amount` → `price` | — | Coincide | Coincide | PASS | INFO | |
| 63 | Unit | Normalization | `price.currency` → `currency` | Moneda `"USD"` (no EUR) | Coincide, no hardcoded a EUR | Coincide | PASS | INFO | |
| 64 | Unit | Normalization | Imagen grande `images[0].urls.big` | 2+ imágenes con URLs distintas | `imageUrl` = `images[0].urls.big` exactamente | Coincide, distinto de `.medium`/`.small`/`images[1]` | PASS | INFO | |
| 65 | Unit | Normalization | URL construida con `web_slug` | Slug con guiones/números | `https://es.wallapop.com/item/<slug>` exacto | Coincide | PASS | INFO | |
| 66 | Unit | Normalization | Mapea ciudad/CP/país | — | `city`/`postalCode`/`countryCode` correctos, sin lat/lng/region | Coincide; lat/lng/region confirmados ausentes del `location` normalizado | PASS | INFO | |
| 67 | Unit | Normalization | `created_at` → ISO string | Epoch ms `1700000000000` | `new Date(x).toISOString()` | `"2023-11-14T22:13:20.000Z"` exacto | PASS | INFO | |
| 68 | Unit | Normalization | Excluye campos internos | 12 campos internos (`bump`,`favorited`,`taxonomy`,`reserved`,`shipping`,`is_favoriteable`,`is_refurbished`,`is_top_profile`,`has_warranty`,`user_id`,`category_id`,`modified_at`) todos truthy en el fixture | Ninguno en `Object.keys(listing)` | Ninguno presente | PASS | INFO | |
| 69 | Unit | Normalization | Conserva `condition` si existe | `condition:"new"` | `listing.condition==="new"` | Coincide | PASS | INFO | |
| 70 | Unit | Normalization | `condition` ausente → `undefined` consistente | Campo ausente vs. explícitamente `undefined` | Ambos → `listing.condition===undefined` | Ambos → `undefined`. Nota informativa: `Object.keys(listing).includes('condition')` es `true` en AMBOS casos (la asignación explícita del literal de retorno aplana la distinción absent-key vs explicit-undefined) | PASS | INFO | No es un bug, comportamiento consistente y documentado |
| 71 | Integración | Error-Handling | Upstream HTTP 400 | Mock `ok:false,status:400` | Error MCP claro con "400" | `Wallapop search request failed: HTTP 400` | PASS | INFO | |
| 72 | Integración | Error-Handling | Upstream HTTP 403 | — | Error claro con "403" | `Wallapop search request failed: HTTP 403` | PASS | INFO | |
| 73 | Integración | Error-Handling | Upstream HTTP 429 | — | Error claro con "429" | `Wallapop search request failed: HTTP 429` — sin manejo de `Retry-After` (coherente con el diseño "sin retry/backoff") | PASS | INFO | |
| 74 | Integración | Error-Handling | Upstream HTTP 500 | — | Error claro con "500" | `Wallapop search request failed: HTTP 500` | PASS | INFO | |
| 75 | Integración | Error-Handling | Fallo de red | `fetchImpl` rechaza con `TypeError("fetch failed")` | Se propaga, no se traga | Error original propagado sin modificar | PASS | INFO | |
| 76 | Integración | Error-Handling | JSON inválido | `response.json()` rechaza con `SyntaxError` | Se propaga | Error original propagado sin modificar | PASS | INFO | |
| 77 | Integración | Error-Handling | Falta `data` | Body `{}` | Debería ser un error claro/manejado | `TypeError: Cannot read properties of undefined (reading 'section')` — mensaje crudo, no accionable | PASS (documenta comportamiento) | P2 | No arreglado — fuera del alcance mínimo de este ciclo, ver `BUGS_AND_RISKS.md` |
| 78 | Integración | Error-Handling | Falta `section` | `data:{}` | Idem | `TypeError: Cannot read properties of undefined (reading 'payload')` | PASS (documenta comportamiento) | P2 | Idem |
| 79 | Integración | Error-Handling | Falta `payload` | `data:{section:{}}` | Idem | `TypeError: Cannot read properties of undefined (reading 'items')` | PASS (documenta comportamiento) | P2 | Idem |
| 80 | Integración | Error-Handling | Falta `items` | `data:{section:{payload:{}}}` | Idem | `TypeError: items is not iterable` (el `for...of` sobre `undefined`) | PASS (documenta comportamiento) | P2 | Idem |
| 81 | Integración | Error-Handling | Item sin imágenes | `images:[]` en un item de una página válida | Error claro identificando el item, no un TypeError crudo | **Antes**: `TypeError: Cannot read properties of undefined (reading 'urls')` (crudo). **Después del fix**: `Malformed Wallapop item bad: missing images` | PASS (post-fix) | P1→FIXED | Bug real corregido en este ciclo — ver `BUGS_AND_RISKS.md` #1 |
| 82 | Integración | Error-Handling | Item sin `price` | Campo `price` ausente en un item | Idem | **Antes**: `TypeError: Cannot read properties of undefined (reading 'amount')`. **Después**: `Malformed Wallapop item good: missing price` | PASS (post-fix) | P1→FIXED | Mismo fix que #81 |
| 83 | Unit | Validation | `minPrice` negativo | `{minPrice:-50}` | Sin validación (documentar) | `min_sale_price=-50` verbatim, sin rechazo/clamping | PASS (documenta comportamiento) | P3 | Decisión de producto, no arreglado |
| 84 | Unit | Validation | `maxPrice` negativo | `{maxPrice:-10}` | Idem | `max_sale_price=-10` verbatim | PASS (documenta comportamiento) | P3 | Idem |
| 85 | Unit | Validation | `minPrice > maxPrice` | `{minPrice:500,maxPrice:10}` | Sin validación cruzada | Ambos set tal cual, sin swap/error | PASS (documenta comportamiento) | P3 | Idem |
| 86 | Unit | Validation | `distanceInKm:0` | — | `distance=0` presente, no omitido | Coincide | PASS | INFO | |
| 87 | Unit | Validation | `distanceInKm` negativo | `{distanceInKm:-5}` | `distance=-5000` sin validar | Coincide | PASS (documenta comportamiento) | P3 | |
| 88 | Unit | Validation | Latitud fuera de rango | `{latitude:999}` | Sin chequeo de rango (-90..90) | `latitude=999` verbatim | PASS (documenta comportamiento) | P3 | |
| 89 | Unit | Validation | Longitud fuera de rango | `{longitude:999}` | Sin chequeo de rango (-180..180) | `longitude=999` verbatim | PASS (documenta comportamiento) | P3 | |
| 90 | MCP-Smoke | Validation | `maxResults:0` vía tool MCP completo | `callTool({name:"search",arguments:{maxResults:0}})` | `listings:[]`, 0 fetch | Coincide, `fetchImpl` nunca invocado | PASS | INFO | |
| 91 | MCP-Smoke | Validation | `maxResults` negativo vía tool MCP completo | `{maxResults:-20}` | Debe decidirse: ¿error o vacío silencioso? | `listings:[]`, 0 fetch, `isError` falsy — **éxito silencioso con resultado vacío**, no error | PASS (documenta comportamiento) | P3 | Posible gap de UX: un valor claramente inválido no se señala como tal. Decisión de producto, no arreglado |
| 92 | MCP-Smoke | Validation | Tipo incorrecto vía MCP (`maxResults:"40"` string) | `callTool({...,arguments:{maxResults:"40"}})` | Zod debe rechazar con error claro, sin crash | `isError:true`, `MCP error -32602: Input validation error... expected number, received string`, `fetchImpl` nunca invocado. Mismo resultado para `latitude:"41.1"` | PASS | INFO | **Confusión de tipos de un cliente LLM está correctamente blindada** por el schema Zod del SDK — hallazgo positivo importante |
| 93 | LLM-sim | LLM-UX | "Encuentra iPhone 11 por menos de 80€" | Análisis de contrato (no ejecutable) | Debe llamar `search({keywords:"iPhone 11", maxPrice:80})` | Mapeo directo y sin ambigüedad sobre el schema Zod actual | PASS (análisis) | INFO | |
| 94 | LLM-sim | LLM-UX | "Busca bicis cerca de Barcelona" | Idem | Usa default Barcelona sin pasar lat/lng | La descripción del tool (visible al LLM en tiempo de llamada, no solo el README) ya lo indica explícitamente | PASS (análisis) | INFO | |
| 95 | LLM-sim | LLM-UX | "Busca portátiles baratos en tecnología" | Idem | Idealmente `list_categories` primero → `categoryId` → `search` | La relación entre ambos tools NO está en las descripciones/schema, solo en el README — un cliente que no lea el README puede no descubrir el flujo de 2 pasos | PASS (análisis, gap documentado) | P3 | Mejora sugerida: enlazar ambos tools en su `description` |
| 96 | LLM-sim | LLM-UX | "Dame más resultados" | Idem | Debe reusar el `nextPage` de la respuesta previa | El campo está etiquetado explícitamente `.describe("Opaque pagination cursor from a previous search's response.")` — señal suficiente | PASS (análisis) | INFO | |
| 97 | LLM-sim | LLM-UX | "Ordena PS5 por precio bajo" | Idem | Usar `orderBy` con un valor legal si existe soporte documentado | **Ningún valor legal de `orderBy` está enumerado en ningún sitio** (schema, descripción, ni comentario en `request.ts`) — el único ejemplo (`"price_low_to_high"`) está solo en el README, no en el contrato que ve el LLM | PASS (análisis, gap real documentado) | P2 | Ver también test 38 |
| 98 | LLM-sim | LLM-UX | "Busca solo nuevos" (filtro de condición) | Idem | Debe explicar que `condition` no es fiable, no fingir un filtro | La limitación NO aparece en la descripción/schema del tool en tiempo de llamada — solo en el README | PASS (análisis, gap documentado) | P2 | El LLM que solo ve el schema no tiene esta señal |
| 99 | LLM-sim | LLM-UX | "Escríbele al vendedor" | Idem | Debe rechazar — no hay mensajería | Confirmado por grep: cero capacidad de mensajería en `src/**` | PASS (análisis) | INFO | |
| 100 | LLM-sim | LLM-UX | "Cómpralo por mí" | Idem | Debe rechazar — no hay compra/auth | Confirmado por grep: cero capacidad de compra/checkout/auth en `src/**` | PASS (análisis) | INFO | |
