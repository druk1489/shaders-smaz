--!nocheck
-- shaders-smaz / backdoor_scanner.lua
-- Version: 1.0.0 "Black Widow"
-- Purpose: Comprehensive Roblox game backdoor / malicious remote / persistence scanner
-- Requirements: Medium+ executor with sUNC + UNC (writefile, getgc, hookmetamethod, getconnections, decompile/getscriptbytecode)
-- Author: druk1489 / SMAZ project
-- License: MIT
--
-- Usage (после push в репу):
--   loadstring(game:HttpGet("https://raw.githubusercontent.com/druk1489/shaders-smaz/main/backdoor_scanner.lua"))()
--
-- API:
--   getgenv().SMAZ_BDS.run()              -- полный скан (все 7 фаз)
--   getgenv().SMAZ_BDS.runPassive()       -- только read-only фазы (без fuzz'а и без хуков)
--   getgenv().SMAZ_BDS.fuzzRemotes()      -- прожарить все RemoteFunctions payload'ами
--   getgenv().SMAZ_BDS.monitorTraffic(30) -- 30 сек __namecall трафик capture
--   getgenv().SMAZ_BDS.dumpReport()       -- записать полный JSON отчёт в workspace/
--   getgenv().SMAZ_BDS.printSummary()     -- красивая консольная сводка
--   getgenv().SMAZ_BDS.unload()           -- снять все хуки

local Players     = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService  = game:GetService("RunService")
local Stats       = game:GetService("Stats")
local LP          = Players.LocalPlayer

-- ===============================================================
-- 0) CAPABILITY DETECTION
-- ===============================================================
local function isfn(v) return type(v) == "function" end
local caps = {
    getgc             = isfn(rawget(_G, "getgc") or getgc),
    getnilinstances   = isfn(rawget(_G, "getnilinstances")),
    getscripts        = isfn(rawget(_G, "getscripts")),
    getloadedmodules  = isfn(rawget(_G, "getloadedmodules")),
    getconnections    = isfn(rawget(_G, "getconnections")),
    hookmetamethod    = isfn(rawget(_G, "hookmetamethod")),
    getrawmetatable   = isfn(rawget(_G, "getrawmetatable")),
    setreadonly       = isfn(rawget(_G, "setreadonly")),
    getsenv           = isfn(rawget(_G, "getsenv")),
    getreg            = isfn(rawget(_G, "getreg")),
    getcallbackvalue  = isfn(rawget(_G, "getcallbackvalue")),
    identifyexecutor  = isfn(rawget(_G, "identifyexecutor")),
    firesignal        = isfn(rawget(_G, "firesignal")),
    writefile         = isfn(rawget(_G, "writefile")),
    setclipboard      = isfn(rawget(_G, "setclipboard")),
    decompile         = isfn(rawget(_G, "decompile")),
    getscriptbytecode = isfn(rawget(_G, "getscriptbytecode")) or isfn(rawget(_G, "dumpstring")),
    debug_getconstants= type(debug) == "table" and isfn(debug.getconstants),
    debug_getprotos   = type(debug) == "table" and isfn(debug.getprotos),
    debug_getupvalues = type(debug) == "table" and isfn(debug.getupvalues),
    checkcaller       = isfn(rawget(_G, "checkcaller")),
}

local execName = "unknown"
if caps.identifyexecutor then
    local ok, a, b = pcall(identifyexecutor)
    if ok then execName = tostring(a).."/"..tostring(b or "?") end
end

-- ===============================================================
-- 1) REPORT STATE
-- ===============================================================
local report = {
    version     = "1.0.0",
    generatedAt = os.time(),
    placeId     = game.PlaceId,
    jobId       = game.JobId,
    playerName  = LP.Name,
    userId      = LP.UserId,
    executor    = execName,
    caps        = caps,
    stats       = { instances = 0, scripts = 0, remotes = 0, modules = 0, hidden = 0 },
    findings    = {},
    remotes     = {},   -- {path, class, name, hasClientListener, connectionCount, calls}
    scripts     = {},   -- {path, class, sourceHash, patternHits, contentSample}
    hidden      = {},
    traffic     = {},   -- {method, self, args, retVals, script}
    fuzz        = {},
}

local SEV = { CRITICAL = 5, HIGH = 4, MEDIUM = 3, LOW = 2, INFO = 1 }
local SEV_NAME = { [5]="CRITICAL",[4]="HIGH",[3]="MEDIUM",[2]="LOW",[1]="INFO" }

local function finding(sev, category, target, evidence, why)
    table.insert(report.findings, {
        severity = sev, sevName = SEV_NAME[sev], category = category,
        target = target, evidence = evidence, why = why, at = tick(),
    })
end

-- ===============================================================
-- 2) SIGNATURE DATABASE (updated 2026-08)
-- ===============================================================
local SIG_CODE = {
    -- direct execution primitives
    { p = "loadstring%s*%(",          s = SEV.HIGH,     w = "loadstring() — arbitrary code exec vector" },
    { p = ":LoadString%s*%(",         s = SEV.HIGH,     w = "LoadString method (obf loadstring alias)" },
    { p = "getfenv%s*%(%s*0%s*%)",     s = SEV.HIGH,     w = "getfenv(0) — global env access" },
    { p = "getfenv%s*%(",             s = SEV.LOW,      w = "getfenv usage (context dependent)" },
    { p = "setfenv%s*%(",             s = SEV.MEDIUM,   w = "setfenv usage — sandbox reshape" },
    -- module backdoors (assetId require)
    { p = "require%s*%(%s*%d%d%d%d%d%d%d%d%d", s = SEV.CRITICAL, w = "require(9+digit assetId) — external ModuleScript backdoor" },
    { p = "require%s*%(%s*%d%d%d%d%d%d%d%d",   s = SEV.CRITICAL, w = "require(8-digit assetId)" },
    { p = "require%s*%(%s*%d%d%d%d%d%d%d",     s = SEV.HIGH,     w = "require(7-digit assetId)" },
    { p = "InsertService:LoadAsset",  s = SEV.HIGH,     w = "InsertService:LoadAsset — arbitrary asset injection" },
    -- HTTP exfil / C2
    { p = "loadstring%s*%(%s*game[:%.]HttpGet", s = SEV.CRITICAL, w = "loadstring(HttpGet) — remote loader (classic backdoor)" },
    { p = "loadstring%s*%(%s*game[:%.]HttpService[:%.]GetAsync", s = SEV.CRITICAL, w = "loadstring(HttpService:GetAsync) — remote loader" },
    { p = "HttpService[:%.]GetAsync", s = SEV.MEDIUM,   w = "HttpService:GetAsync (may be C2 endpoint)" },
    { p = "HttpService[:%.]PostAsync",s = SEV.MEDIUM,   w = "HttpService:PostAsync (may be exfil)" },
    { p = "HttpService[:%.]RequestAsync", s = SEV.MEDIUM, w = "HttpService:RequestAsync" },
    { p = ":HttpGet%s*%(",            s = SEV.HIGH,     w = ":HttpGet( — not standard in game code" },
    { p = "webhook",                  s = SEV.MEDIUM,   w = "'webhook' string reference" },
    { p = "discord%.com/api",         s = SEV.HIGH,     w = "Discord webhook exfil endpoint" },
    { p = "discordapp%.com",          s = SEV.HIGH,     w = "Discord API domain" },
    -- obfuscation
    { p = "string%.char%s*%([%d,%s]+,[%d,%s]+,[%d,%s]+", s = SEV.LOW, w = "string.char sequence (name/URL obfuscation)" },
    { p = "\\x%x%x\\x%x%x\\x%x%x",  s = SEV.LOW,      w = "\\x hex-string obfuscation" },
    { p = "\\%d%d%d\\%d%d%d",         s = SEV.LOW,      w = "\\NNN decimal escape obfuscation" },
    -- kiddy backdoor lib names
    { p = "HouseKeeper",              s = SEV.MEDIUM,   w = "HouseKeeper backdoor lib reference" },
    { p = "OpFinality",               s = SEV.MEDIUM,   w = "OpFinality admin (backdoor deployment vector)" },
    { p = "Kohls Admin",              s = SEV.LOW,      w = "Kohls Admin reference" },
    { p = "Adonis",                   s = SEV.LOW,      w = "Adonis admin reference" },
    { p = "HD Admin",                 s = SEV.LOW,      w = "HD Admin reference" },
    -- global pollution
    { p = "rawset%s*%(%s*_G",         s = SEV.MEDIUM,   w = "rawset(_G,...) — global env write" },
    { p = "rawset%s*%(%s*getfenv",    s = SEV.HIGH,     w = "rawset(getfenv()...) — sandbox escape" },
    { p = "getfenv%(%)%.script",      s = SEV.MEDIUM,   w = "getfenv().script pattern (env inspection)" },
    -- persistence
    { p = "MessagingService",         s = SEV.MEDIUM,   w = "MessagingService (cross-server relay)" },
    { p = "BindToClose",              s = SEV.LOW,      w = "BindToClose (server-side)" },
    -- server-only APIs referenced from client scripts = suspicious
    { p = "DataStoreService",         s = SEV.LOW,      w = "DataStoreService reference (server-only, but ref may exist)" },
    -- serialize dropper
    { p = "HttpService:JSONDecode.-loadstring", s = SEV.CRITICAL, w = "JSONDecode → loadstring pattern (staged loader)" },
}

local BAD_REMOTE_TOKENS = {
    "execute", "exec", "eval", "loadstring", "loadstr", "cmd",
    "command", "shell", "backdoor", "trojan", "bd",
    "admin", "adm", "root", "debug", "dbg",
    "http", "webhook", "exfil", "beacon", "c2",
    "housekeeper", "opfinality",
}

-- ===============================================================
-- 3) HELPERS
-- ===============================================================
local function safe(f, ...)
    local ok, r = pcall(f, ...)
    if ok then return r end
    return nil
end

local function getPath(i)
    return safe(function() return i:GetFullName() end) or ("<" .. tostring(i) .. ">")
 end

local function isRemote(i)
    return i:IsA("RemoteEvent") or i:IsA("RemoteFunction")
        or i:IsA("UnreliableRemoteEvent")
end
local function isBindable(i)
    return i:IsA("BindableEvent") or i:IsA("BindableFunction")
end
local function isScript(i)
    return i:IsA("Script") or i:IsA("LocalScript") or i:IsA("ModuleScript")
end

local function suspiciousName(name)
    local n = string.lower(name or "")
    if n == "" or n:match("^[%s]+$") then return "empty/whitespace name" end
    for _, tok in ipairs(BAD_REMOTE_TOKENS) do
        if n:find(tok, 1, true) then return "contains '" .. tok .. "'" end
    end
    if n:match("[%z\1-\31]") then return "contains control characters" end
    if #name > 60 then return "unusually long name (" .. #name .. " chars)" end
    if name:match("^[a-fA-F0-9]+$") and #name >= 8 then return "looks hex-encoded" end
    return nil
end

local function scanSource(src, target)
    if type(src) ~= "string" or #src == 0 then return 0 end
    local hits = 0
    for _, sig in ipairs(SIG_CODE) do
        local pos = 1
        while true do
            local a, b = src:find(sig.p, pos)
            if not a then break end
            hits = hits + 1
            local ctxStart = math.max(1, a - 40)
            local ctxEnd   = math.min(#src, b + 80)
            finding(sig.s, "code_signature", target, {
                pattern = sig.p,
                match   = src:sub(a, b):sub(1, 120),
                context = src:sub(ctxStart, ctxEnd),
                offset  = a,
            }, sig.w)
            pos = b + 1
            if hits >= 10 then break end  -- cap per source
        end
    end
    return hits
end

local function getScriptSource(s)
    -- try direct .Source (Studio only)
    local ok, src = pcall(function() return s.Source end)
    if ok and type(src) == "string" and #src > 0 then return src, "Source" end
    -- try decompile()
    if caps.decompile then
        local ok2, src2 = pcall(decompile, s)
        if ok2 and type(src2) == "string" and #src2 > 0 then return src2, "decompile" end
    end
    -- try getscriptbytecode → decompile via debug.getconstants
    if caps.getscriptbytecode then
        local ok3, bc = pcall(getscriptbytecode, s)
        if ok3 and type(bc) == "string" and #bc > 0 then
            -- fallback: scan the raw bytecode string for signature substrings
            return bc, "bytecode"
        end
    end
    -- try constants dump
    if caps.debug_getconstants then
        local pieces = {}
        local ok4, consts = pcall(debug.getconstants, s)
        if ok4 and type(consts) == "table" then
            for _, c in ipairs(consts) do
                if type(c) == "string" then table.insert(pieces, c) end
            end
            if #pieces > 0 then return table.concat(pieces, "\n"), "constants" end
        end
    end
    return nil, "unavailable"
end

local function shortHash(s)
    if type(s) ~= "string" then return "nil" end
    local h = 5381
    for i = 1, math.min(#s, 65536) do
        h = (h * 33 + s:byte(i)) % 2147483647
    end
    return string.format("%08x/%d", h, #s)
end

-- ===============================================================
-- 4) PHASE 1: INSTANCE ENUMERATION (full DataModel walk)
-- ===============================================================
local function phase1_enumerate()
    print("[BDS] Phase 1: enumerating DataModel...")
    local queue = {game}
    local head  = 1
    while head <= #queue do
        local node = queue[head]; head = head + 1
        report.stats.instances = report.stats.instances + 1
        local ok, children = pcall(function() return node:GetChildren() end)
        if ok then
            for _, c in ipairs(children) do
                table.insert(queue, c)
                -- classify
                if isRemote(c) or isBindable(c) then
                    report.stats.remotes = report.stats.remotes + 1
                    local entry = {
                        path  = getPath(c),
                        class = c.ClassName,
                        name  = c.Name,
                        suspicious = suspiciousName(c.Name),
                    }
                    -- OnClientEvent / OnClientInvoke connection count
                    if caps.getconnections then
                        local sig = c:IsA("RemoteEvent") and c.OnClientEvent
                                 or c:IsA("UnreliableRemoteEvent") and c.OnClientEvent
                                 or nil
                        if sig then
                            local okc, conns = pcall(getconnections, sig)
                            if okc and type(conns) == "table" then
                                entry.clientListeners = #conns
                            end
                        end
                    end
                    -- OnClientInvoke callback (RemoteFunction inverse — server invokes client)
                    if caps.getcallbackvalue and c:IsA("RemoteFunction") then
                        local okcb, cb = pcall(getcallbackvalue, c, "OnClientInvoke")
                        if okcb and cb then
                            entry.hasOnClientInvoke = true
                            finding(SEV.MEDIUM, "remote_shape", entry.path, { cb = tostring(cb) },
                                "RemoteFunction has OnClientInvoke callback — server can invoke arbitrary logic on client")
                        end
                    end
                    if entry.suspicious then
                        finding(SEV.HIGH, "remote_name", entry.path, { name = c.Name, reason = entry.suspicious },
                            "Suspicious remote name — potential backdoor")
                    end
                    table.insert(report.remotes, entry)
                elseif isScript(c) then
                    report.stats.scripts = report.stats.scripts + 1
                    if c:IsA("ModuleScript") then report.stats.modules = report.stats.modules + 1 end
                end
            end
        end
    end
    print(("[BDS] Phase 1 done: %d instances, %d remotes, %d scripts (%d modules)"):format(
        report.stats.instances, report.stats.remotes, report.stats.scripts, report.stats.modules))
end

-- ===============================================================
-- 5) PHASE 2: HIDDEN / NIL-PARENTED INSTANCES
-- ===============================================================
local function phase2_hidden()
    print("[BDS] Phase 2: hidden / nil-parented instances...")
    if not caps.getnilinstances then
        print("[BDS]   getnilinstances unavailable — skipping")
        return
    end
    local ok, list = pcall(getnilinstances)
    if not ok or type(list) ~= "table" then return end
    for _, inst in ipairs(list) do
        report.stats.hidden = report.stats.hidden + 1
        local entry = { className = inst.ClassName, name = safe(function() return inst.Name end) or "?" }
        table.insert(report.hidden, entry)
        if isRemote(inst) or isBindable(inst) then
            finding(SEV.CRITICAL, "hidden_remote", tostring(inst), entry,
                "Nil-parented Remote/Bindable — classic backdoor hiding (invisible in Explorer, still fireable)")
        elseif isScript(inst) then
            finding(SEV.HIGH, "hidden_script", tostring(inst), entry,
                "Nil-parented Script/ModuleScript — may be dormant loader")
            local src = getScriptSource(inst)
            if src then scanSource(src, tostring(inst) .. " [nil-parented]") end
        end
    end
    print(("[BDS] Phase 2 done: %d hidden instances"):format(report.stats.hidden))
end

-- ===============================================================
-- 6) PHASE 3: SCRIPT SOURCE / BYTECODE SCAN
-- ===============================================================
local function phase3_scripts()
    print("[BDS] Phase 3: scanning script sources...")
    local pool = {}
    if caps.getscripts then
        local ok, list = pcall(getscripts)
        if ok and type(list) == "table" then
            for _, s in ipairs(list) do table.insert(pool, s) end
        end
    end
    -- fallback: walk DataModel for scripts
    if #pool == 0 then
        local queue = {game}
        local head = 1
        while head <= #queue do
            local n = queue[head]; head = head + 1
            for _, c in ipairs(safe(function() return n:GetChildren() end) or {}) do
                table.insert(queue, c)
                if isScript(c) then table.insert(pool, c) end
            end
        end
    end

    local scanned, withSource, withHits = 0, 0, 0
    for _, s in ipairs(pool) do
        scanned = scanned + 1
        local src, method = getScriptSource(s)
        if src then
            withSource = withSource + 1
            local hits = scanSource(src, getPath(s))
            local entry = {
                path = getPath(s), class = s.ClassName, srcMethod = method,
                hash = shortHash(src), hits = hits,
            }
            if hits > 0 then
                withHits = withHits + 1
                entry.sample = src:sub(1, 300)
            end
            table.insert(report.scripts, entry)
        end
    end
    print(("[BDS] Phase 3 done: scanned=%d, with source=%d, with hits=%d"):format(scanned, withSource, withHits))
end

-- ===============================================================
-- 7) PHASE 4: LOADED MODULE INSPECTION (require'd modules)
-- ===============================================================
local function phase4_modules()
    print("[BDS] Phase 4: loaded modules...")
    if not caps.getloadedmodules then
        print("[BDS]   getloadedmodules unavailable — skipping")
        return
    end
    local ok, list = pcall(getloadedmodules)
    if not ok or type(list) ~= "table" then return end
    local total, susp = 0, 0
    for _, m in ipairs(list) do
        total = total + 1
        local path = getPath(m)
        -- if parent is nil AND it's not in a whitelisted location = suspicious
        local parent = safe(function() return m.Parent end)
        if not parent then
            susp = susp + 1
            finding(SEV.HIGH, "hidden_loaded_module", path or tostring(m),
                { class = m.ClassName, name = safe(function() return m.Name end) },
                "ModuleScript loaded (require()'d) but nil-parented — post-load hiding pattern")
        end
        -- scan source
        local src, method = getScriptSource(m)
        if src then scanSource(src, path .. " [loaded module]") end
    end
    print(("[BDS] Phase 4 done: %d modules loaded, %d suspicious"):format(total, susp))
end

-- ===============================================================
-- 8) PHASE 5: GC SWEEP for hidden functions / closures with dangerous refs
-- ===============================================================
local function phase5_gc()
    print("[BDS] Phase 5: GC sweep...")
    if not caps.getgc then
        print("[BDS]   getgc unavailable — skipping")
        return
    end
    local ok, gc = pcall(getgc, true)
    if not ok or type(gc) ~= "table" then return end
    local total, danger = #gc, 0
    for i = 1, math.min(total, 250000) do
        local v = gc[i]
        if type(v) == "function" and caps.debug_getconstants then
            local okc, consts = pcall(debug.getconstants, v)
            if okc and type(consts) == "table" then
                for _, c in ipairs(consts) do
                    if type(c) == "string" then
                        if c:find("loadstring", 1, true)
                           or c:find("HttpGet", 1, true)
                           or c:find("GetAsync", 1, true)
                           or c:match("discord%.com/api")
                           or c:match("https?://[%w%.:/%-_]+") then
                            danger = danger + 1
                            if danger <= 30 then
                                finding(SEV.MEDIUM, "gc_dangerous_closure", "gc["..i.."]",
                                    { constant = c:sub(1, 200) },
                                    "Closure in GC holds dangerous string constant")
                            end
                            break
                        end
                    end
                end
            end
        end
    end
    print(("[BDS] Phase 5 done: %d gc objects, %d suspicious closures"):format(total, danger))
end

-- ===============================================================
-- 9) PHASE 6: __namecall TRAFFIC MONITOR (server-bound remote calls from OTHER scripts)
-- ===============================================================
local namecallHook = nil
local origNamecall = nil
local trafficActive = false

local function installNamecallHook()
    if not caps.hookmetamethod then return false end
    if namecallHook then return true end
    local mt = getrawmetatable(game)
    if not mt then return false end
    local orig = mt.__namecall
    origNamecall = orig
    local newFn
    newFn = function(self, ...)
        local method = getnamecallmethod and getnamecallmethod() or "?"
        if trafficActive and (method == "FireServer" or method == "InvokeServer") then
            local args = { ... }
            local ok, className = pcall(function() return self.ClassName end)
            local path = getPath(self)
            local sample = {}
            for i, a in ipairs(args) do
                local t = typeof(a)
                if t == "string" then sample[i] = t..":"..a:sub(1, 80)
                elseif t == "number" or t == "boolean" then sample[i] = t..":"..tostring(a)
                elseif t == "Instance" then sample[i] = "Instance:"..a.ClassName
                elseif t == "table" then sample[i] = "table:"..HttpService:JSONEncode(a):sub(1, 120)
                else sample[i] = t
                end
            end
            local callerScript = safe(getcallingscript) or safe(function() return getfenv(2).script end)
            table.insert(report.traffic, {
                method = method, path = path, class = className,
                args = sample, script = callerScript and getPath(callerScript) or "?",
                at = tick(),
            })
        end
        return orig(self, ...)
    end
    local ok, hooked = pcall(hookmetamethod, game, "__namecall", newFn)
    if ok then namecallHook = hooked; return true end
    return false
end

local function phase6_traffic(sec)
    sec = sec or 30
    print(("[BDS] Phase 6: __namecall traffic monitor for %ds..."):format(sec))
    if not installNamecallHook() then
        print("[BDS]   __namecall hook install failed — skipping")
        return
    end
    trafficActive = true
    task.wait(sec)
    trafficActive = false
    print(("[BDS] Phase 6 done: captured %d Fire/Invoke calls"):format(#report.traffic))
    -- classify: any remote not seen in report.remotes phase 1 = dynamically created
    local seenPaths = {}
    for _, r in ipairs(report.remotes) do seenPaths[r.path] = true end
    for _, t in ipairs(report.traffic) do
        if not seenPaths[t.path] then
            finding(SEV.HIGH, "dynamic_remote", t.path,
                { class = t.class, method = t.method, script = t.script },
                "Remote called that wasn't present at initial enumeration — dynamically created (typical of runtime backdoor drop)")
            seenPaths[t.path] = true
        end
    end
end

-- ===============================================================
-- 10) PHASE 7: REMOTE FUZZER
-- ===============================================================
local FUZZ_PAYLOADS = {
    { name = "empty",           args = {} },
    { name = "nil",              args = {nil} },
    { name = "empty_str",        args = {""} },
    { name = "admin_str",        args = {"admin"} },
    { name = "exec_str",         args = {"exec"} },
    { name = "cmd_str",          args = {"cmd"} },
    { name = "eval_str",         args = {"eval"} },
    { name = "help_str",         args = {"?"} },
    { name = "version_str",      args = {"__version"} },
    { name = "empty_table",      args = {{}} },
    { name = "cmd_table",        args = {{cmd = "version"}} },
    { name = "admin_table",      args = {{admin = true, action = "dump"}} },
    { name = "exec_table",       args = {{exec = "print('hi')"}} },
    { name = "lua_payload",      args = {"return _VERSION"} },
    { name = "lua_return_1",     args = {"return 1"} },
    { name = "long_string",      args = {string.rep("A", 512)} },
    { name = "deep_nested",      args = {{a={b={c={d={e="leak"}}}}}} },
    { name = "neg_num",          args = {-1} },
    { name = "huge_num",         args = {2^40} },
    { name = "bool_true",        args = {true} },
    { name = "bool_false",       args = {false} },
    { name = "two_args",         args = {"exec", "print('x')"} },
    { name = "instance_lp",      args = {LP} },
    { name = "instance_ws",      args = {workspace} },
}

local function fuzzRemote(rem, entry)
    if not rem:IsA("RemoteFunction") then return end  -- only RemoteFunctions safely return; FireServer is fire-and-forget
    local results = {}
    for _, pl in ipairs(FUZZ_PAYLOADS) do
        local t0 = os.clock()
        local ret = { pcall(rem.InvokeServer, rem, table.unpack(pl.args)) }
        local dur = os.clock() - t0
        local ok = ret[1]
        local repr = {}
        for i = 2, #ret do
            local v = ret[i]
            local t = typeof(v)
            if t == "string" then repr[i-1] = t..":"..v:sub(1, 200)
            elseif t == "table" then repr[i-1] = t..":"..HttpService:JSONEncode(v):sub(1, 300)
            else repr[i-1] = t..":"..tostring(v) end
        end
        table.insert(results, {
            payload = pl.name, ok = ok, ret = repr, durSec = dur,
            argCount = select("#", table.unpack(pl.args)),
        })
        -- flag oversized returns (potential data leak)
        local totalLen = 0
        for _, r in ipairs(repr) do totalLen = totalLen + #tostring(r) end
        if ok and totalLen > 500 then
            finding(SEV.HIGH, "fuzz_leak", entry.path,
                { payload = pl.name, retLen = totalLen, retSample = repr[1] },
                "RemoteFunction returned large payload for fuzz input — possible data leak / debug endpoint")
        end
        -- flag lua-payload accepted without error
        if ok and (pl.name == "lua_payload" or pl.name == "lua_return_1") then
            if #repr > 0 then
                finding(SEV.CRITICAL, "fuzz_lua_accepted", entry.path,
                    { payload = pl.name, ret = repr },
                    "RemoteFunction accepted Lua-like payload and returned data — possible loadstring backdoor")
            end
        end
        task.wait(0.15)  -- anti-spam
    end
    table.insert(report.fuzz, { path = entry.path, class = entry.class, results = results })
end

local function phase7_fuzz()
    print("[BDS] Phase 7: RemoteFunction fuzzer (this is slow)...")
    local rfs = {}
    for _, e in ipairs(report.remotes) do
        if e.class == "RemoteFunction" then table.insert(rfs, e) end
    end
    for i, e in ipairs(rfs) do
        local inst = nil
        for _, part in ipairs(string.split(e.path, ".")) do
            inst = (inst or game)
            local ok, child = pcall(function() return inst:FindFirstChild(part) end)
            if ok and child then inst = child else inst = nil break end
        end
        if inst and inst:IsA("RemoteFunction") then
            print(("[BDS]   fuzzing [%d/%d] %s"):format(i, #rfs, e.path))
            fuzzRemote(inst, e)
        end
    end
    print(("[BDS] Phase 7 done: %d RemoteFunctions fuzzed"):format(#rfs))
end

-- ===============================================================
-- 11) REPORT / OUTPUT
-- ===============================================================
local function sortFindings()
    table.sort(report.findings, function(a, b)
        if a.severity ~= b.severity then return a.severity > b.severity end
        return (a.category or "") < (b.category or "")
    end)
end

local function printSummary()
    sortFindings()
    print("\n============================================================")
    print("  SMAZ Backdoor Scanner — Report Summary")
    print("============================================================")
    print(("  PlaceId: %d  JobId: %s"):format(report.placeId, tostring(report.jobId):sub(1, 12)))
    print(("  Executor: %s"):format(report.executor))
    print(("  Stats: %d instances / %d remotes / %d scripts / %d hidden")
        :format(report.stats.instances, report.stats.remotes, report.stats.scripts, report.stats.hidden))
    local bySev = {0,0,0,0,0}
    for _, f in ipairs(report.findings) do bySev[f.severity] = bySev[f.severity] + 1 end
    print(("  Findings: CRIT=%d  HIGH=%d  MED=%d  LOW=%d  INFO=%d")
        :format(bySev[5], bySev[4], bySev[3], bySev[2], bySev[1]))
    print("------------------------------------------------------------")
    local shown = 0
    for _, f in ipairs(report.findings) do
        if shown >= 40 then break end
        if f.severity >= SEV.MEDIUM then
            shown = shown + 1
            print(("  [%s] %-24s %s"):format(f.sevName, f.category, f.target))
            print(("        why:  %s"):format(f.why))
            if f.evidence and f.evidence.match then
                print(("        hit:  %s"):format(tostring(f.evidence.match):sub(1, 100)))
            end
        end
    end
    if shown == 0 then print("  No MEDIUM+ findings. Game looks clean at this scan depth.") end
    print("============================================================\n")
end

local function dumpReport()
    sortFindings()
    local json = HttpService:JSONEncode(report)
    local fname = ("bds_report_%d_%d.json"):format(report.placeId, os.time())
    if caps.writefile then
        writefile(fname, json)
        print("[BDS] Report written to workspace/" .. fname .. " (" .. #json .. " bytes)")
    elseif caps.setclipboard then
        setclipboard(json)
        print("[BDS] Report copied to clipboard (" .. #json .. " bytes)")
    else
        print("[BDS] No writefile/setclipboard; report kept in getgenv().SMAZ_BDS.report")
    end
    return fname
end

-- ===============================================================
-- 12) PUBLIC API
-- ===============================================================
local function unload()
    trafficActive = false
    if namecallHook and origNamecall and caps.hookmetamethod then
        -- reinstate
        pcall(hookmetamethod, game, "__namecall", origNamecall)
        namecallHook = nil
    end
    print("[BDS] hooks unloaded")
end

local function runPassive()
    phase1_enumerate()
    phase2_hidden()
    phase3_scripts()
    phase4_modules()
    phase5_gc()
    printSummary()
end

local function run()
    runPassive()
    phase6_traffic(20)
    phase7_fuzz()
    printSummary()
    dumpReport()
end

getgenv().SMAZ_BDS = {
    version         = "1.0.0",
    report          = report,
    caps            = caps,
    run             = run,
    runPassive      = runPassive,
    monitorTraffic  = phase6_traffic,
    fuzzRemotes     = phase7_fuzz,
    dumpReport      = dumpReport,
    printSummary    = printSummary,
    unload          = unload,
    -- individual phase runners
    phase1_enumerate= phase1_enumerate,
    phase2_hidden   = phase2_hidden,
    phase3_scripts  = phase3_scripts,
    phase4_modules  = phase4_modules,
    phase5_gc       = phase5_gc,
    phase6_traffic  = phase6_traffic,
    phase7_fuzz     = phase7_fuzz,
}

print("[BDS] SMAZ Backdoor Scanner v1.0.0 loaded. Try getgenv().SMAZ_BDS.runPassive() first.")
return getgenv().SMAZ_BDS
