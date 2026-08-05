# SMAZ Backdoor Scanner v1.0.0 "Black Widow"

Comprehensive Roblox game backdoor / malicious-remote / persistence scanner.
Runs fully client-side from any Medium+ executor with sUNC + UNC.

## Quick start

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/druk1489/shaders-smaz/main/backdoor_scanner.lua"))()
getgenv().SMAZ_BDS.run()          -- полный скан (пассив + трафик + fuzz)
```

## 7 phases

| # | Phase | What it does |
|---|---|---|
| 1 | `phase1_enumerate` | Полный обход DataModel: считает Instances, каталогизирует Remotes/Bindables, ловит OnClientInvoke, флагает подозрительные имена |
| 2 | `phase2_hidden` | `getnilinstances()` → nil-parented объекты (классическое место backdoor'ов) |
| 3 | `phase3_scripts` | Сканирует все скрипты через `getscripts()`, декомпилит если может, в fallback — constants/bytecode. 28 signature-patterns в базе |
| 4 | `phase4_modules` | `getloadedmodules()` → loaded ModuleScripts, ловит post-load hiding включая nil-parent после `require()` |
| 5 | `phase5_gc` | `getgc(true)` → свееп констант в замыканиях на URL/HttpGet/loadstring/discord.com |
| 6 | `phase6_traffic` | `hookmetamethod(__namecall)` → 30сек запись всего Fire/InvokeServer трафика с идентификацией caller script'а |
| 7 | `phase7_fuzz` | Каждую RemoteFunction обстреливает 24 payload'ами: empty/admin/exec/lua/tables/long-strings; флагает лики и loadstring-приемники |

## API

```lua
getgenv().SMAZ_BDS.run()              -- все 7 фаз (долго, ~2 мин)
getgenv().SMAZ_BDS.runPassive()       -- только read-only (~15 сек) — старт отсюда
SMAZ_BDS.monitorTraffic(60)           -- 60с трафика отдельно
SMAZ_BDS.fuzzRemotes()                -- только fuzz
SMAZ_BDS.dumpReport()                 -- JSON в workspace/bds_report_<placeId>_<time>.json
SMAZ_BDS.printSummary()               -- консольная сводка (MEDIUM+ файндинги)
SMAZ_BDS.unload()                     -- снять хуки
SMAZ_BDS.report                       -- raw report table (если нужно посмотреть в живую)
```

## Severity levels

- **CRITICAL** — точно backdoor (require(assetId), loadstring(HttpGet), staged loader)
- **HIGH** — почти точно (nil-parent scripts, sandbox escape, suspicious remote names)
- **MEDIUM** — подозрительно (HTTP endpoints, MessagingService, kiddy libs)
- **LOW** — паттерны что могут быть легитимными (getfenv, string.char, PlayerAdded)
- **INFO** — статистика

## Что ловит

**Static code signatures** (28 pattern'ов):
- `loadstring()`, `:LoadString()`, `getfenv(0)`, `setfenv`
- `require(<8-9 digit assetId>)` — классический module-backdoor
- `loadstring(game:HttpGet(...))`, `loadstring(HttpService:GetAsync(...))` — remote loader
- `HttpService:GetAsync/PostAsync/RequestAsync`, `:HttpGet(`
- `discord.com/api`, `discordapp.com` — webhook exfil
- `string.char(...)`, `\xNN`, `\NNN` — обфускация имен
- `HouseKeeper`, `OpFinality`, `Kohls`, `Adonis`, `HD Admin` — kiddy libs
- `rawset(_G,...)`, `rawset(getfenv()...)` — sandbox escape
- `InsertService:LoadAsset` — ассет-инъекция
- `HttpService:JSONDecode(...loadstring)` — staged loader

**Runtime detection:**
- Новые remote'ы появившиеся после initial enumeration (dynamic drop)
- nil-parented Remotes/Scripts/Modules
- Closure constants содержащие URL'ы
- RemoteFunctions возвращающие >500 bytes на fuzz-input (data leak)
- RemoteFunctions тихо принявшие Lua-payload без ошибки (возможный loadstring бэкдор)

**Bad remote names:** `execute`, `exec`, `eval`, `run`, `loadstring`, `cmd`, `admin`, `root`, `debug`, `backdoor`, `shell`, `http`, `webhook`, `exfil`, `beacon`, `c2`, hex-имена, empty/whitespace, control-символы.

## Requirements

**Must have:** `writefile` OR `setclipboard`, `getgc`, `hookmetamethod`, `getrawmetatable`
**Nice to have:** `getnilinstances`, `getloadedmodules`, `getscripts`, `getconnections`, `decompile`, `getscriptbytecode`, `debug.getconstants`
**Executors OK:** Solara, Wave, AWP, Fluxus, Xeno, Krampus, Zorara, Synapse Z — любой Medium+

## License

MIT.
