--!nocheck
-- SMAZ Deobfuscator v3  (druk1489/shaders-smaz)
-- Loader: loadstring(game:HttpGet("https://raw.githubusercontent.com/druk1489/shaders-smaz/main/deobfuscator_v3.lua"))()
--
-- NEW in v3:
--   [NEW] Log All  — hooks EVERY function in the loaded script, logs args + returns + call depth
--                    scans GC before AND during execution to catch dynamically-created closures
--                    filters by chunk source so we only trace target script, not the whole game
--   [NEW] Trace tree — indented call log showing recursion depth and call graph
--   [KEPT] All v2: Static, Dynamic, Beautify, Namecall, Fn Trace, MoonSec, Full Pipeline
--
-- Hotkey: RightShift toggles UI

if getgenv().__DEOB_V3_UNLOAD then pcall(getgenv().__DEOB_V3_UNLOAD) end
if getgenv().__DEOB_V2_UNLOAD then pcall(getgenv().__DEOB_V2_UNLOAD) end
if getgenv().__DEOB_V1_UNLOAD then pcall(getgenv().__DEOB_V1_UNLOAD) end

local UIS = game:GetService("UserInputService")
local Players = game:GetService("Players")
local LP = Players.LocalPlayer

local ENV = getgenv()
local CFG = {
    workDir        = "smaz_deob",
    dynamicTimeout = 6,
    maxScanDepth   = 5,
    uiWidth        = 820,
    uiHeight       = 500,
    namecallDepth  = 200,
    namecallLimit  = 20000,
    opcodeLimit    = 100000,
    traceTimeout   = 15,
    logAllTimeout  = 20,
    logAllLimit    = 50000,
    logAllArgLen   = 60,
    logAllArgs     = 8,
    rescanInterval = 0.2,
    chunkName      = "@SMAZ_TARGET",
}

local FS = {}
do
    local function ensure(p) if not isfolder(p) then makefolder(p) end end
    function FS.init()
        ensure(CFG.workDir); ensure(CFG.workDir.."/input"); ensure(CFG.workDir.."/output")
        ensure(CFG.workDir.."/captures"); ensure(CFG.workDir.."/traces")
    end
    function FS.save(sub, name, data)
        ensure(CFG.workDir.."/"..sub)
        local p = CFG.workDir.."/"..sub.."/"..name
        writefile(p, data)
        return p
    end
end
FS.init()

local SIG = {}
do
    local sigs = {
        {name="MoonSecV3", weight=100, pat={"MoonSecV3", "__moonsec_v3"}},
        {name="MoonSecV2", weight=90,  pat={"MoonSecV2", "Protected_by_MoonSec", "%.%.:::MoonSec:::%.%.", "_msec"}},
        {name="MoonSecV1", weight=80,  pat={"MoonSec", "local _MOONSEC"}},
        {name="Ferib",     weight=70,  pat={"LuaObfuscator", "LOL!", "getfenv or getgenv"}},
        {name="PSU",       weight=60,  pat={"PSU!", "psu_", "ProtectedByPSU"}},
        {name="Iron",      weight=50,  pat={"IronBrew", "_ironbrew"}},
        {name="Prometheus",weight=40,  pat={"prometheus", "Prometheus_v"}},
        {name="LuaEscape", weight=30,  pat={"loadstring%([\"']\\%d%d"}},
        {name="HexEscape", weight=25,  pat={"loadstring%([\"']\\x%x%x"}},
    }
    function SIG.detect(src)
        local hits = {}
        for _, s in ipairs(sigs) do
            for _, p in ipairs(s.pat) do
                if src:find(p) then table.insert(hits, {name=s.name, weight=s.weight, pat=p}); break end
            end
        end
        table.sort(hits, function(a,b) return a.weight > b.weight end)
        return hits
    end
    function SIG.report(hits)
        if #hits == 0 then return "No known obfuscator detected." end
        local lines = {"Detected:"}
        for _, h in ipairs(hits) do table.insert(lines, string.format("  %-14s  (%s)", h.name, h.pat)) end
        return table.concat(lines, "\n")
    end
end

local STATIC = {}
do
    function STATIC.decodeDecimalEscapes(src)
        local n = 0
        local out = src:gsub("\\(%d%d?%d?)", function(d)
            local c = tonumber(d); if c and c>=32 and c<127 then n=n+1; return string.char(c) end
            return "\\"..d
        end)
        return out, n
    end
    function STATIC.decodeHexEscapes(src)
        local n = 0
        local out = src:gsub("\\x(%x%x)", function(h)
            local c = tonumber(h,16); if c and c>=32 and c<127 then n=n+1; return string.char(c) end
            return "\\x"..h
        end)
        return out, n
    end
    function STATIC.unwrapLoadstring(src)
        local m = src:match('^%s*loadstring%("(.*)"%)%(%)%s*$')
        if m then return m, 1 end; return src, 0
    end
    function STATIC.foldArith(src)
        local c = 0
        for _ = 1, 8 do
            local n = 0
            src = src:gsub("%((%-?%d+[xX]?[%da-fA-F]*)%s*([%+%-%*/%%])%s*(%-?%d+[xX]?[%da-fA-F]*)%)", function(a,op,b)
                local av,bv = tonumber(a),tonumber(b); if not av or not bv then return end
                local r; if op=="+" then r=av+bv elseif op=="-" then r=av-bv elseif op=="*" then r=av*bv
                elseif op=="/" then if bv==0 then return end; r=av/bv
                elseif op=="%" then if bv==0 then return end; r=av%bv end
                if r==math.floor(r) then r=math.floor(r) end
                n=n+1; return tostring(r)
            end)
            if n==0 then break end; c=c+n
        end
        return src, c
    end
    function STATIC.foldStringChar(src)
        local n=0
        local out = src:gsub("string%.char%(([%d,%s]+)%)", function(nums)
            local chars = {}
            for x in nums:gmatch("%d+") do local c=tonumber(x); if c<32 or c>126 then return end; table.insert(chars, string.char(c)) end
            n=n+1; return string.format("%q", table.concat(chars))
        end)
        return out, n
    end
    function STATIC.foldStringConcat(src)
        local c=0
        for _=1,4 do
            local n=0
            src = src:gsub("'([^']*)'%s*%.%.%s*'([^']*)'", function(a,b) n=n+1; return "'"..a..b.."'" end)
            src = src:gsub('"([^"]*)"%s*%.%.%s*"([^"]*)"', function(a,b) n=n+1; return '"'..a..b..'"' end)
            if n==0 then break end; c=c+n
        end
        return src, c
    end
    function STATIC.killLoopWrappers(src)
        local c=0
        for _=1,3 do
            local n=0
            src = src:gsub("while%s+true%s+do%s+(.-)%s+break%s+end", function(inner)
                if not inner:find("while%s+true%s+do") then n=n+1; return inner end
            end)
            if n==0 then break end; c=c+n
        end
        return src, c
    end
    function STATIC.run(src)
        local report = {"[STATIC] Passes:"}
        local function step(name, fn) local out,n=fn(src); src=out; table.insert(report, string.format("  %-22s %5d", name, n)) end
        step("unwrapLoadstring", STATIC.unwrapLoadstring)
        step("decodeDecimalEscapes", STATIC.decodeDecimalEscapes)
        step("decodeHexEscapes", STATIC.decodeHexEscapes)
        step("foldStringChar", STATIC.foldStringChar)
        step("foldStringConcat", STATIC.foldStringConcat)
        step("foldArith", STATIC.foldArith)
        step("killLoopWrappers", STATIC.killLoopWrappers)
        step("foldStringChar2", STATIC.foldStringChar)
        step("foldStringConcat2", STATIC.foldStringConcat)
        return src, table.concat(report, "\n")
    end
end

local function beautify(src)
    src = src:gsub(";%s*", ";\n"):gsub("(%s)end(%s)", "%1end%2\n"):gsub("do%s+(%S)", "do\n%1"):gsub("then%s+(%S)", "then\n%1")
    local out, depth = {}, 0
    for line in src:gmatch("[^\n]+") do
        local t = line:match("^%s*(.-)%s*$")
        if t == "" then table.insert(out, "")
        else
            local starts = t:match("^end") or t:match("^else") or t:match("^elseif") or t:match("^until") or t:match("^%)")
            if starts then depth = math.max(0, depth - 1) end
            table.insert(out, string.rep("    ", depth) .. t)
            local o = 0
            for _ in t:gmatch("%f[%w]function%f[%W]") do o = o + 1 end
            for _ in t:gmatch("%f[%w]do%f[%W]") do o = o + 1 end
            for _ in t:gmatch("%f[%w]then%f[%W]") do o = o + 1 end
            for _ in t:gmatch("%f[%w]repeat%f[%W]") do o = o + 1 end
            for _ in t:gmatch("%f[%w]end%f[%W]") do o = o - 1 end
            for _ in t:gmatch("%f[%w]until%f[%W]") do o = o - 1 end
            depth = math.max(0, depth + o)
        end
    end
    return table.concat(out, "\n")
end

local function serVal(v, maxLen)
    maxLen = maxLen or CFG.logAllArgLen
    local t = type(v)
    if t == "string" then
        if #v > maxLen then return string.format("%q..(%dB)", v:sub(1, maxLen), #v) end
        return string.format("%q", v)
    elseif t == "number" or t == "boolean" or t == "nil" then return tostring(v)
    elseif t == "table" then
        local ok, s = pcall(tostring, v); return ok and s:sub(1, maxLen) or "<table>"
    elseif t == "userdata" then
        local ok, s = pcall(tostring, v); return "ud<"..(ok and s:sub(1,40) or "?")..">"
    elseif t == "function" then
        local ok, info = pcall(debug.getinfo, v, "S")
        if ok and info then return "fn<"..(info.short_src or "?")..":"..(info.linedefined or 0)..">" end
        return "fn"
    end
    return "<"..t..">"
end

local function serArgs(args, maxN, maxLen)
    maxN = maxN or CFG.logAllArgs
    local parts = {}
    for i = 1, math.min(#args, maxN) do parts[i] = serVal(args[i], maxLen) end
    if #args > maxN then parts[#parts+1] = "...("..(#args - maxN).." more)" end
    return table.concat(parts, ", ")
end

local NC = { trace = {}, active = false }
do
    function NC.start()
        if NC.active then return "namecall already running" end
        NC.trace = {}; NC.active = true
        local oldNC
        oldNC = hookmetamethod(game, "__namecall", function(self, ...)
            if not NC.active then return oldNC(self, ...) end
            local method = getnamecallmethod()
            if #NC.trace < CFG.namecallLimit then
                local args = {...}
                local ok, s = pcall(function() return self:GetFullName() end)
                table.insert(NC.trace, {t = tick(), self = (ok and tostring(s) or tostring(self)):sub(1,80),
                    method = tostring(method), args = serArgs(args, CFG.namecallDepth, 60)})
            end
            return oldNC(self, ...)
        end)
        return "namecall tracer started"
    end
    function NC.stop() NC.active = false; return "namecall stopped, entries: "..#NC.trace end
    function NC.dump(name)
        name = name or "namecall_"..os.time()..".log"
        local lines = {"# Namecall trace  entries="..#NC.trace}
        local t0 = NC.trace[1] and NC.trace[1].t or 0
        for i, e in ipairs(NC.trace) do
            table.insert(lines, string.format("[%05d  +%.3fs]  %s :%s (%s)", i, e.t - t0, e.self, e.method, e.args))
        end
        return FS.save("traces", name, table.concat(lines, "\n"))
    end
end

local FN = { trace = {}, active = false, restores = {} }
do
    local function log(kind, args, ret)
        if #FN.trace >= CFG.namecallLimit then return end
        local a = serArgs(args or {}, 6, 80)
        local r = ret and (tostring(ret):sub(1,60) .. (type(ret)=="string" and (" ["..#ret.."B]") or "")) or ""
        table.insert(FN.trace, {t = tick(), kind = kind, args = a, ret = r})
    end
    function FN.start()
        if FN.active then return "fn tracer already running" end
        FN.trace = {}; FN.active = true
        do
            local orig = game.HttpGet
            local function wrap(self, url, ...)
                local body = orig(self, url, ...); log("HttpGet", {url}, body)
                if type(body)=="string" and #body>200 then
                    pcall(function() local u = tostring(url):sub(1,60):gsub("[^%w]","_"); FS.save("captures", string.format("http_%s_%dB.lua", u, #body), body) end)
                end
                return body
            end
            local ok, oldFn = pcall(hookfunction, orig, wrap)
            if ok then table.insert(FN.restores, function() pcall(hookfunction, orig, oldFn) end) end
        end
        do
            local old = loadstring
            getgenv().loadstring = function(src, cn)
                if type(src)=="string" and #src>100 then
                    pcall(function() FS.save("captures", string.format("loadstring_%dB.lua", #src), src) end)
                end
                log("loadstring", {src}, nil)
                return old(src, cn)
            end
            table.insert(FN.restores, function() getgenv().loadstring = old end)
        end
        if writefile then
            local old = writefile
            getgenv().writefile = function(p, d) log("writefile", {p, d}, nil); return old(p, d) end
            table.insert(FN.restores, function() getgenv().writefile = old end)
        end
        if readfile then
            local old = readfile
            getgenv().readfile = function(p) local r = old(p); log("readfile", {p}, r); return r end
            table.insert(FN.restores, function() getgenv().readfile = old end)
        end
        local req = (syn and syn.request) or http_request or (http and http.request) or request
        if req then
            local wrap = function(opts)
                local r = req(opts)
                log("request", {opts and opts.Url or "?", opts and opts.Method or "GET"}, r and r.Body)
                return r
            end
            getgenv().request = wrap
            if syn then pcall(function() syn.request = wrap end) end
            table.insert(FN.restores, function() getgenv().request = req end)
        end
        return "fn tracer started"
    end
    function FN.stop()
        FN.active = false
        for _, r in ipairs(FN.restores) do pcall(r) end
        FN.restores = {}
        return "fn stopped, entries: "..#FN.trace
    end
    function FN.dump(name)
        name = name or "fntrace_"..os.time()..".log"
        local lines = {"# Function trace  entries="..#FN.trace}
        local t0 = FN.trace[1] and FN.trace[1].t or 0
        for i, e in ipairs(FN.trace) do
            table.insert(lines, string.format("[%05d  +%.3fs]  %-12s (%s) -> %s", i, e.t - t0, e.kind, e.args, e.ret))
        end
        return FS.save("traces", name, table.concat(lines, "\n"))
    end
end

-- LOG ALL: hook every function in the target script
local LA = {
    trace = {}, active = false, hooked = {}, fnMeta = {}, fnByPtr = {},
    depth = 0, nextId = 1, watcherThread = nil, startTime = 0,
}
do
    local function fnInfo(fn)
        local ok, info = pcall(debug.getinfo, fn, "Sn")
        if not ok or not info then return { source = "?", line = 0, name = "?" } end
        return { source = info.short_src or info.source or "?", line = info.linedefined or 0, name = info.name or "?" }
    end
    local function isTarget(fn)
        if type(fn) ~= "function" then return false end
        local ok, info = pcall(debug.getinfo, fn, "S")
        if not ok or not info then return false end
        if info.what == "C" then return false end
        local src = info.source or ""
        if src:find(CFG.chunkName, 1, true) then return true end
        return false
    end
    local function record(kind, fnId, payload)
        if #LA.trace >= CFG.logAllLimit then return end
        table.insert(LA.trace, { t = tick() - LA.startTime, d = LA.depth, k = kind, f = fnId, p = payload })
    end
    local function hookOne(fn)
        if LA.hooked[fn] then return false end
        if not isTarget(fn) then return false end
        local info = fnInfo(fn)
        local id = LA.nextId; LA.nextId = id + 1
        LA.fnMeta[id] = info
        LA.fnByPtr[fn] = id
        local wrapper = function(...)
            if not LA.active then
                local orig = LA.hooked[fn]
                return orig and orig(...) or fn(...)
            end
            local args = {...}
            record("call", id, serArgs(args, CFG.logAllArgs, CFG.logAllArgLen))
            LA.depth = LA.depth + 1
            local orig = LA.hooked[fn]
            local packed = { pcall(orig or fn, ...) }
            LA.depth = math.max(0, LA.depth - 1)
            local ok = packed[1]
            if ok then
                local rets = {}
                for i = 2, #packed do rets[i-1] = packed[i] end
                record("ret", id, serArgs(rets, CFG.logAllArgs, CFG.logAllArgLen))
                return unpack(rets)
            else
                record("err", id, tostring(packed[2]):sub(1, 200))
                error(packed[2], 2)
            end
        end
        local ok, oldFn = pcall(hookfunction, fn, wrapper)
        if ok then LA.hooked[fn] = oldFn; return true
        else LA.fnMeta[id] = nil; LA.fnByPtr[fn] = nil; LA.nextId = id; return false end
    end
    function LA.scanAndHook()
        if not getgc then return 0 end
        local newHooks = 0
        for _, v in pairs(getgc(true) or {}) do
            if type(v) == "function" and not LA.hooked[v] then
                if hookOne(v) then newHooks = newHooks + 1 end
            end
        end
        return newHooks
    end
    function LA.start()
        if LA.active then return "log-all already running" end
        LA.trace = {}; LA.hooked = {}; LA.fnMeta = {}; LA.fnByPtr = {}
        LA.depth = 0; LA.nextId = 1; LA.startTime = tick(); LA.active = true
        LA.watcherThread = task.spawn(function()
            while LA.active do
                pcall(LA.scanAndHook)
                task.wait(CFG.rescanInterval)
            end
        end)
        return "log-all armed (chunkName="..CFG.chunkName..")"
    end
    function LA.stop()
        LA.active = false; LA.watcherThread = nil
        local restored = 0
        for fn, oldFn in pairs(LA.hooked) do pcall(hookfunction, fn, oldFn); restored = restored + 1 end
        return string.format("log-all stopped: %d hooks removed, %d entries", restored, #LA.trace)
    end
    function LA.dump(name, tree)
        name = name or "logall_"..os.time()..".log"
        local lines = {
            "# Log-All trace  entries="..#LA.trace.."  functions="..(LA.nextId-1),
            "# Format: [idx  +time  d=depth]  KIND  fn#id  payload", "",
            "## Function table",
        }
        local keys = {}; for k in pairs(LA.fnMeta) do keys[#keys+1] = k end; table.sort(keys)
        for _, id in ipairs(keys) do
            local m = LA.fnMeta[id]
            table.insert(lines, string.format("  fn#%-4d  %s:%d  %s", id, m.source, m.line, m.name))
        end
        table.insert(lines, ""); table.insert(lines, "## Trace")
        for i, e in ipairs(LA.trace) do
            local indent = tree and string.rep("  ", math.min(e.d, 30)) or ""
            local marker = e.k == "call" and "->" or (e.k == "ret" and "<-" or "!!")
            table.insert(lines, string.format("[%05d  +%.4fs  d=%02d]  %s%s fn#%-4d  %s",
                i, e.t, e.d, indent, marker, e.f, e.p or ""))
        end
        return FS.save("traces", name, table.concat(lines, "\n"))
    end
    function LA.runAndLog(src, name, timeout)
        timeout = timeout or CFG.logAllTimeout
        LA.start()
        local chunk, cerr = loadstring(src, CFG.chunkName)
        if not chunk then LA.stop(); return false, "loadstring failed: "..tostring(cerr) end
        LA.scanAndHook()
        local co = coroutine.create(chunk)
        task.spawn(function()
            local resOk, err = coroutine.resume(co)
            if not resOk then
                pcall(function() FS.save("traces", (name or "unknown").."_logall_error.txt", tostring(err)) end)
            end
        end)
        local t0 = tick()
        while tick() - t0 < timeout and LA.active do task.wait(0.1) end
        LA.stop()
        local path = LA.dump((name or "unknown").."_logall.log", true)
        local flat = LA.dump((name or "unknown").."_logall_flat.log", false)
        return true, string.format("hooked=%d  entries=%d  saved:\n  %s\n  %s", LA.nextId-1, #LA.trace, path, flat)
    end
end

local function dynamicDeob(src, name)
    FN.start()
    local before = #FN.trace
    local ok, err = pcall(function() loadstring(src, name or "deob_dyn")() end)
    task.wait(CFG.dynamicTimeout)
    local now = #FN.trace
    FN.stop()
    return string.format("[DYNAMIC] ok=%s  err=%s  captures=%d", tostring(ok), tostring(err or "nil"):sub(1,80), now - before)
end

local function moonsecUnwrap(src, name)
    local report = {"[MOONSEC] start"}
    local hits = SIG.detect(src)
    table.insert(report, SIG.report(hits))
    local out, rep = STATIC.run(src)
    table.insert(report, rep)
    NC.start(); FN.start()
    pcall(function() loadstring(src, CFG.chunkName)() end)
    task.wait(CFG.traceTimeout - 2)
    NC.stop(); FN.stop()
    NC.dump((name or "unknown").."_namecall.log")
    FN.dump((name or "unknown").."_fntrace.log")
    FS.save("output", (name or "unknown")..".moonsec_static.lua", out)
    table.insert(report, "[MOONSEC] Wrote: .moonsec_static.lua + _namecall.log + _fntrace.log")
    return out, table.concat(report, "\n")
end

local function scanLua(dir, depth)
    depth = depth or 0
    if depth > CFG.maxScanDepth then return {} end
    local found = {}
    if not isfolder(dir) then return found end
    for _, path in ipairs(listfiles(dir)) do
        if isfolder(path) then
            for _, sub in ipairs(scanLua(path, depth+1)) do table.insert(found, sub) end
        elseif path:match("%.lua$") or path:match("%.txt$") then
            table.insert(found, path)
        end
    end
    return found
end

local UI = {}
do
    local function mk(class, props, parent)
        local o = Instance.new(class); for k,v in pairs(props) do o[k]=v end
        if parent then o.Parent = parent end; return o
    end
    local screen = mk("ScreenGui", {Name="SMAZ_DEOB_V3_UI", ResetOnSpawn=false, ZIndexBehavior=Enum.ZIndexBehavior.Sibling, DisplayOrder=999})
    pcall(function() screen.Parent = gethui and gethui() or game:GetService("CoreGui") end)
    if screen.Parent == nil then screen.Parent = LP:WaitForChild("PlayerGui") end

    local frame = mk("Frame", {Size=UDim2.new(0,CFG.uiWidth,0,CFG.uiHeight), Position=UDim2.new(0.5,-CFG.uiWidth/2,0.5,-CFG.uiHeight/2), BackgroundColor3=Color3.fromRGB(20,22,26), BorderSizePixel=0, Active=true, Draggable=true}, screen)
    mk("UICorner", {CornerRadius=UDim.new(0,8)}, frame)
    mk("UIStroke", {Color=Color3.fromRGB(80,90,110), Thickness=1, Transparency=0.5}, frame)
    mk("TextLabel", {Size=UDim2.new(1,-20,0,28), Position=UDim2.new(0,10,0,6), BackgroundTransparency=1,
        Text="SMAZ Deobfuscator v3  —  RightShift toggle  —  Log All = hook every function",
        Font=Enum.Font.Code, TextSize=14, TextColor3=Color3.fromRGB(220,220,230), TextXAlignment=Enum.TextXAlignment.Left}, frame)

    local btnRow = mk("Frame", {Size=UDim2.new(1,-20,0,32), Position=UDim2.new(0,10,0,38), BackgroundTransparency=1}, frame)
    mk("UIListLayout", {FillDirection=Enum.FillDirection.Horizontal, Padding=UDim.new(0,5)}, btnRow)
    local function addBtn(label, cb, w, color)
        local b = mk("TextButton", {Size=UDim2.new(0,w or 82,1,0), BackgroundColor3=color or Color3.fromRGB(45,50,60), BorderSizePixel=0, Text=label, TextColor3=Color3.fromRGB(220,220,230), Font=Enum.Font.Code, TextSize=12}, btnRow)
        mk("UICorner", {CornerRadius=UDim.new(0,4)}, b)
        b.MouseButton1Click:Connect(cb)
    end

    local left = mk("Frame", {Size=UDim2.new(0.32,-6,1,-140), Position=UDim2.new(0,10,0,78), BackgroundColor3=Color3.fromRGB(28,30,36), BorderSizePixel=0}, frame)
    mk("UICorner", {CornerRadius=UDim.new(0,4)}, left)
    local right = mk("ScrollingFrame", {Size=UDim2.new(0.68,-4,1,-140), Position=UDim2.new(0.32,6,0,78), BackgroundColor3=Color3.fromRGB(28,30,36), BorderSizePixel=0, CanvasSize=UDim2.new(0,0,0,800), ScrollBarThickness=6}, frame)
    mk("UICorner", {CornerRadius=UDim.new(0,4)}, right)
    local logBox = mk("TextLabel", {Size=UDim2.new(1,-12,1,-12), Position=UDim2.new(0,6,0,6), BackgroundTransparency=1, Font=Enum.Font.Code, TextSize=12, TextColor3=Color3.fromRGB(200,210,215),
        Text="[ready v3]  Files: workspace/"..CFG.workDir.."/input/\n\nLog All  — hooks EVERY function in target script,\nlogs args/returns/depth. Best on already-deobfuscated code.\n\nOn VM obfuscators, run Static first, then Log All on .static.lua.",
        TextXAlignment=Enum.TextXAlignment.Left, TextYAlignment=Enum.TextYAlignment.Top, TextWrapped=true}, right)
    local function log(s) logBox.Text = ("[%s] %s\n"):format(os.date("%H:%M:%S"), s) .. logBox.Text:sub(1, 8000) end

    local fileList = mk("ScrollingFrame", {Size=UDim2.new(1,-12,1,-12), Position=UDim2.new(0,6,0,6), BackgroundTransparency=1, BorderSizePixel=0, CanvasSize=UDim2.new(0,0,0,0), ScrollBarThickness=4}, left)
    mk("UIListLayout", {Padding=UDim.new(0,2)}, fileList)
    local selected = nil
    local function refresh()
        for _, c in ipairs(fileList:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
        local files = scanLua(CFG.workDir.."/input")
        for _, f in ipairs(scanLua(CFG.workDir.."/output")) do table.insert(files, f) end
        for _, f in ipairs(files) do
            local btn = mk("TextButton", {Size=UDim2.new(1,-8,0,22), BackgroundColor3=Color3.fromRGB(40,44,52), BorderSizePixel=0, Text=" "..f:match("[^/]+$"):sub(1,42), TextColor3=Color3.fromRGB(210,215,220), Font=Enum.Font.Code, TextSize=11, TextXAlignment=Enum.TextXAlignment.Left}, fileList)
            btn.MouseButton1Click:Connect(function() selected = f; log("Selected: "..f) end)
        end
        fileList.CanvasSize = UDim2.new(0,0,0,#files*24+4)
        log("Refreshed: "..#files.." files")
    end
    local function readSelected()
        if not selected then log("! No file selected") return nil end
        local ok, data = pcall(readfile, selected)
        if not ok then log("! read failed: "..tostring(data)) return nil end
        return data, selected:match("[^/]+$"):gsub("%.[^.]+$", "")
    end

    addBtn("Refresh", refresh, 70)
    addBtn("Detect", function() local d = readSelected(); if d then log(SIG.report(SIG.detect(d))) end end, 65)
    addBtn("Static", function()
        local d, n = readSelected(); if not d then return end
        local out, rep = STATIC.run(d); FS.save("output", n..".static.lua", out)
        log(rep.."\nSaved: output/"..n..".static.lua"); refresh()
    end, 65)
    addBtn("Beautify", function()
        local d, n = readSelected(); if not d then return end
        local out = beautify(d); FS.save("output", n..".pretty.lua", out)
        log("Beautified: "..#d.."B -> "..#out.."B"); refresh()
    end, 75)
    addBtn("Namecall", function()
        local d, n = readSelected(); if not d then return end
        log(NC.start())
        task.spawn(function() pcall(loadstring, d) end)
        task.wait(CFG.traceTimeout)
        log(NC.stop()); log("Saved: "..NC.dump(n.."_namecall.log"))
    end, 80)
    addBtn("Fn Trace", function()
        local d, n = readSelected(); if not d then return end
        log(FN.start())
        task.spawn(function() pcall(loadstring, d) end)
        task.wait(CFG.traceTimeout)
        log(FN.stop()); log("Saved: "..FN.dump(n.."_fntrace.log"))
    end, 80)
    addBtn("LOG ALL", function()
        local d, n = readSelected(); if not d then return end
        log("[LOG ALL] start "..n.."  timeout="..CFG.logAllTimeout.."s  chunkName="..CFG.chunkName)
        task.spawn(function()
            local ok, msg = LA.runAndLog(d, n, CFG.logAllTimeout)
            log("[LOG ALL] "..(ok and ("done: "..msg) or ("FAILED: "..msg)))
            refresh()
        end)
    end, 90, Color3.fromRGB(80, 50, 90))
    addBtn("MoonSec", function()
        local d, n = readSelected(); if not d then return end
        log("[MoonSec] start "..n)
        task.spawn(function() local _, rep = moonsecUnwrap(d, n); log(rep); refresh() end)
    end, 80)

    local btnRow2 = mk("Frame", {Size=UDim2.new(1,-20,0,32), Position=UDim2.new(0,10,1,-50), BackgroundTransparency=1}, frame)
    mk("UIListLayout", {FillDirection=Enum.FillDirection.Horizontal, Padding=UDim.new(0,5)}, btnRow2)
    local function addBtn2(label, cb, w)
        local b = mk("TextButton", {Size=UDim2.new(0,w or 82,1,0), BackgroundColor3=Color3.fromRGB(55,40,60), BorderSizePixel=0, Text=label, TextColor3=Color3.fromRGB(220,220,230), Font=Enum.Font.Code, TextSize=12}, btnRow2)
        mk("UICorner", {CornerRadius=UDim.new(0,4)}, b)
        b.MouseButton1Click:Connect(cb)
    end
    addBtn2("Log All (60s)", function()
        local d, n = readSelected(); if not d then return end
        log("[LOG ALL 60s] start "..n)
        task.spawn(function() local ok, msg = LA.runAndLog(d, n.."_60s", 60); log("[LOG ALL 60s] "..(ok and msg or msg)); refresh() end)
    end, 100)
    addBtn2("Max Trace", function()
        local d, n = readSelected(); if not d then return end
        log("[MAX] start "..n.." — Log All + Namecall + Fn all together")
        task.spawn(function()
            NC.start(); FN.start()
            local ok, msg = LA.runAndLog(d, n.."_max", CFG.logAllTimeout)
            NC.stop(); FN.stop()
            NC.dump(n.."_max_namecall.log"); FN.dump(n.."_max_fntrace.log")
            log("[MAX] "..(ok and msg or msg))
            log("Also: _max_namecall.log, _max_fntrace.log"); refresh()
        end)
    end, 90)
    addBtn2("Full Pipeline", function()
        local d, n = readSelected(); if not d then return end
        log("[Full] start "..n)
        task.spawn(function()
            local h = SIG.detect(d); log(SIG.report(h))
            local st, rep = STATIC.run(d); FS.save("output", n..".static.lua", st); log(rep)
            local pretty = beautify(st); FS.save("output", n..".final.lua", pretty)
            log("Saved: output/"..n..".static.lua + .final.lua")
            log("Running Log All on static version...")
            local ok, msg = LA.runAndLog(st, n.."_full", CFG.logAllTimeout)
            log("[Full] "..(ok and msg or msg)); refresh()
        end)
    end, 110)
    addBtn2("Help", function()
        log("=== v3 ===  Log All hooks every fn in your script.")
        log("  Filters by chunk '"..CFG.chunkName.."' so game funcs aren't touched.")
        log("  Re-scans GC every "..CFG.rescanInterval.."s for dynamic closures.")
        log("  Tree + flat views saved to traces/")
        log("Max Trace: log-all + namecall + fn together.")
        log("Files: workspace/"..CFG.workDir.."/{input,output,traces,captures}/")
    end, 60)
    addBtn2("Unload", function()
        pcall(function() screen:Destroy() end)
        FN.stop(); NC.stop(); LA.stop()
        ENV.__DEOB_V3_UNLOAD = nil; ENV.SMAZ_DEOB = nil
    end, 70)

    local visible = true
    UIS.InputBegan:Connect(function(inp, gpe)
        if gpe then return end
        if inp.KeyCode == Enum.KeyCode.RightShift then visible = not visible; frame.Visible = visible end
    end)
    UI.log = log; UI.refresh = refresh; UI.screen = screen
    refresh()
end

ENV.SMAZ_DEOB = {
    version = "3.0.0",
    detectSig = SIG.detect, signatureReport = SIG.report,
    staticDeob = STATIC.run, beautify = beautify,
    dynamicDeob = dynamicDeob, moonsecUnwrap = moonsecUnwrap,
    namecallStart = NC.start, namecallStop = NC.stop, namecallDump = NC.dump,
    fnStart = FN.start, fnStop = FN.stop, fnDump = FN.dump,
    logAllStart = LA.start, logAllStop = LA.stop, logAllDump = LA.dump,
    logAllRun = LA.runAndLog, logAllScan = LA.scanAndHook,
    scanLua = scanLua, CFG = CFG,
}
ENV.__DEOB_V3_UNLOAD = function()
    pcall(function() UI.screen:Destroy() end)
    FN.stop(); NC.stop(); LA.stop()
    ENV.__DEOB_V3_UNLOAD = nil; ENV.SMAZ_DEOB = nil
end

print("[SMAZ Deobfuscator v3] loaded. RightShift = toggle UI.")
return ENV.SMAZ_DEOB
