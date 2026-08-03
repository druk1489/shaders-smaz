--!nocheck
-- SMAZ Deobfuscator v2  (druk1489/shaders-smaz)
-- Loader: loadstring(game:HttpGet("https://raw.githubusercontent.com/druk1489/shaders-smaz/main/deobfuscator_v2.lua"))()
--
-- Changes vs v1:
--   [NEW] Namecall tracer     — hookmetamethod __namecall, logs every Roblox API call
--   [NEW] Function tracer     — hookfunction on I/O funcs (HttpGet/writefile/loadstring/request)
--   [NEW] VM opcode tracer    — auto-detects MoonSec/PSU/Ferib dispatch tables, hooks handlers
--   [NEW] MoonSec unwrap      — combined static+dynamic+opcode trace pass for MoonSecV2
--   [KEPT] Static deob, Dynamic deob, Beautify, Full pipeline, Unload (v1 behavior)
--
-- Hotkey: RightShift toggles UI

if getgenv().__DEOB_V2_UNLOAD then
    pcall(getgenv().__DEOB_V2_UNLOAD)
end
if getgenv().__DEOB_V1_UNLOAD then
    pcall(getgenv().__DEOB_V1_UNLOAD)
end

local RS   = game:GetService("RunService")
local UIS  = game:GetService("UserInputService")
local HS   = game:GetService("HttpService")
local Players = game:GetService("Players")
local LP   = Players.LocalPlayer

local ENV = getgenv()
local CFG = {
    workDir        = "smaz_deob",
    maxFileSize    = 16 * 1024 * 1024,
    dynamicTimeout = 6,
    maxScanDepth   = 5,
    uiWidth        = 780,
    uiHeight       = 480,
    namecallDepth  = 200,
    namecallLimit  = 20000,
    opcodeLimit    = 100000,
    traceTimeout   = 15,
}

local FS = {}
do
    local function ensure(path)
        if not isfolder(path) then makefolder(path) end
    end
    function FS.init()
        ensure(CFG.workDir)
        ensure(CFG.workDir.."/input")
        ensure(CFG.workDir.."/output")
        ensure(CFG.workDir.."/captures")
        ensure(CFG.workDir.."/traces")
    end
    function FS.save(sub, name, data)
        ensure(CFG.workDir.."/"..sub)
        local p = CFG.workDir.."/"..sub.."/"..name
        writefile(p, data)
        return p
    end
    function FS.read(sub, name)
        local p = CFG.workDir.."/"..sub.."/"..name
        if isfile(p) then return readfile(p) end
        return nil
    end
    function FS.list(sub)
        local p = CFG.workDir.."/"..sub
        if not isfolder(p) then return {} end
        return listfiles(p)
    end
end
FS.init()

local SIG = {}
do
    local sigs = {
        {name="MoonSecV3", weight=100, pat={"MoonSecV3", "__moonsec_v3"}},
        {name="MoonSecV2", weight=90, pat={"MoonSecV2", "Protected_by_MoonSec", "%.%.:::MoonSec:::%.%.", "_msec"}},
        {name="MoonSecV1", weight=80, pat={"MoonSec", "local _MOONSEC"}},
        {name="Ferib", weight=70, pat={"LuaObfuscator", "return v%d+%(v%d+%(%),{},v%d+%)%(", "LOL!", "getfenv or getgenv"}},
        {name="PSU", weight=60, pat={"PSU!", "psu_", "ProtectedByPSU"}},
        {name="Iron", weight=50, pat={"IronBrew", "_ironbrew"}},
        {name="Prometheus", weight=40, pat={"prometheus", "Prometheus_v"}},
        {name="LuaEscape", weight=30, pat={"loadstring%([\"']\\%d%d"}},
        {name="HexEscape", weight=25, pat={"loadstring%([\"']\\x%x%x"}},
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
        local lines = {"Detected obfuscators:"}
        for _, h in ipairs(hits) do
            table.insert(lines, string.format("  %-14s  (matched: %s)", h.name, h.pat))
        end
        return table.concat(lines, "\n")
    end
end

local STATIC = {}
do
    function STATIC.decodeDecimalEscapes(src)
        local n = 0
        local out = src:gsub("\\(%d%d?%d?)", function(d)
            local c = tonumber(d)
            if c and c >= 32 and c < 127 then n = n + 1; return string.char(c) end
            return "\\"..d
        end)
        return out, n
    end
    function STATIC.decodeHexEscapes(src)
        local n = 0
        local out = src:gsub("\\x(%x%x)", function(h)
            local c = tonumber(h, 16)
            if c and c >= 32 and c < 127 then n = n + 1; return string.char(c) end
            return "\\x"..h
        end)
        return out, n
    end
    function STATIC.unwrapLoadstring(src)
        local m = src:match('^%s*loadstring%("(.*)"%)%(%)%s*$')
        if m then return m, 1 end
        return src, 0
    end
    function STATIC.foldArith(src)
        local changed = 0
        for _ = 1, 8 do
            local n = 0
            src = src:gsub("%((%-?%d+[xX]?[%da-fA-F]*)%s*([%+%-%*/%%])%s*(%-?%d+[xX]?[%da-fA-F]*)%)", function(a, op, b)
                local av = tonumber(a); local bv = tonumber(b)
                if not av or not bv then return end
                local r
                if op == "+" then r = av + bv
                elseif op == "-" then r = av - bv
                elseif op == "*" then r = av * bv
                elseif op == "/" then if bv == 0 then return end r = av / bv
                elseif op == "%" then if bv == 0 then return end r = av % bv end
                if r == math.floor(r) then r = math.floor(r) end
                n = n + 1
                return tostring(r)
            end)
            if n == 0 then break end
            changed = changed + n
        end
        return src, changed
    end
    function STATIC.foldStringChar(src)
        local n = 0
        local out = src:gsub("string%.char%(([%d,%s]+)%)", function(nums)
            local chars = {}
            for x in nums:gmatch("%d+") do
                local c = tonumber(x)
                if c < 32 or c > 126 then return end
                table.insert(chars, string.char(c))
            end
            n = n + 1
            return string.format("%q", table.concat(chars))
        end)
        return out, n
    end
    function STATIC.foldStringConcat(src)
        local changed = 0
        for _ = 1, 4 do
            local n = 0
            src = src:gsub("'([^']*)'%s*%.%.%s*'([^']*)'", function(a, b) n = n + 1; return "'"..a..b.."'" end)
            src = src:gsub('"([^"]*)"%s*%.%.%s*"([^"]*)"', function(a, b) n = n + 1; return '"'..a..b..'"' end)
            if n == 0 then break end
            changed = changed + n
        end
        return src, changed
    end
    function STATIC.killLoopWrappers(src)
        local changed = 0
        for _ = 1, 3 do
            local n = 0
            src = src:gsub("while%s+true%s+do%s+(.-)%s+break%s+end", function(inner)
                if not inner:find("while%s+true%s+do") then n = n + 1; return inner end
            end)
            if n == 0 then break end
            changed = changed + n
        end
        return src, changed
    end
    function STATIC.run(src)
        local report = {"[STATIC] Passes:"}
        local function step(name, fn)
            local out, n = fn(src); src = out
            table.insert(report, string.format("  %-22s %5d changes", name, n))
        end
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
    src = src:gsub(";%s*", ";\n")
    src = src:gsub("(%s)end(%s)", "%1end%2\n")
    src = src:gsub("do%s+(%S)", "do\n%1")
    src = src:gsub("then%s+(%S)", "then\n%1")
    local out, depth = {}, 0
    for line in src:gmatch("[^\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed == "" then table.insert(out, "")
        else
            local starts = trimmed:match("^end") or trimmed:match("^else") or trimmed:match("^elseif") or trimmed:match("^until") or trimmed:match("^%)")
            if starts then depth = math.max(0, depth - 1) end
            table.insert(out, string.rep("    ", depth) .. trimmed)
            local opens = 0
            for _ in trimmed:gmatch("%f[%w]function%f[%W]") do opens = opens + 1 end
            for _ in trimmed:gmatch("%f[%w]do%f[%W]") do opens = opens + 1 end
            for _ in trimmed:gmatch("%f[%w]then%f[%W]") do opens = opens + 1 end
            for _ in trimmed:gmatch("%f[%w]repeat%f[%W]") do opens = opens + 1 end
            for _ in trimmed:gmatch("%f[%w]end%f[%W]") do opens = opens - 1 end
            for _ in trimmed:gmatch("%f[%w]until%f[%W]") do opens = opens - 1 end
            depth = math.max(0, depth + opens)
        end
    end
    return table.concat(out, "\n")
end

local NC = { trace = {}, active = false }
do
    local function serialize(v)
        local t = type(v)
        if t == "string" then
            if #v > 80 then return string.format("%q..(%dB)", v:sub(1,80), #v) end
            return string.format("%q", v)
        elseif t == "number" or t == "boolean" or t == "nil" then return tostring(v)
        elseif t == "userdata" or t == "table" then
            local ok, s = pcall(tostring, v)
            return ok and s:sub(1,60) or "<?>"
        elseif t == "function" then return "<fn>" end
        return "<"..t..">"
    end
    function NC.start()
        if NC.active then return "namecall tracer already running" end
        NC.trace = {}; NC.active = true
        local oldNC
        oldNC = hookmetamethod(game, "__namecall", function(self, ...)
            if not NC.active then return oldNC(self, ...) end
            local method = getnamecallmethod()
            if #NC.trace < CFG.namecallLimit then
                local args = {...}; local parts = {}
                for i = 1, math.min(#args, CFG.namecallDepth) do parts[i] = serialize(args[i]) end
                local ok, sName = pcall(function() return self:GetFullName() end)
                table.insert(NC.trace, {
                    t = tick(),
                    self = (ok and tostring(sName) or tostring(self)):sub(1,80),
                    method = tostring(method),
                    args = table.concat(parts, ", "),
                })
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
        local argStr = ""
        for i, a in ipairs(args or {}) do argStr = argStr .. (i>1 and ", " or "") .. tostring(a):sub(1, 100) end
        local retStr = ""
        if ret then retStr = tostring(ret):sub(1, 60) .. (type(ret)=="string" and (" ["..#ret.."B]") or "") end
        table.insert(FN.trace, {t = tick(), kind = kind, args = argStr, ret = retStr})
    end
    function FN.start()
        if FN.active then return "function tracer already running" end
        FN.trace = {}; FN.active = true
        do
            local orig = game.HttpGet
            local function wrap(self, url, ...)
                local body = orig(self, url, ...)
                log("HttpGet", {url}, body)
                if type(body) == "string" and #body > 200 then
                    pcall(function()
                        local u = tostring(url):sub(1, 60):gsub("[^%w]", "_")
                        FS.save("captures", string.format("http_%s_%dB.lua", u, #body), body)
                    end)
                end
                return body
            end
            local ok, oldFn = pcall(hookfunction, orig, wrap)
            if ok then table.insert(FN.restores, function() pcall(hookfunction, orig, oldFn) end) end
        end
        do
            local old = loadstring
            getgenv().loadstring = function(src, chunkName)
                if type(src) == "string" and #src > 100 then
                    pcall(function() FS.save("captures", string.format("loadstring_%dB.lua", #src), src) end)
                end
                log("loadstring", {src}, nil)
                return old(src, chunkName)
            end
            table.insert(FN.restores, function() getgenv().loadstring = old end)
        end
        if writefile then
            local old = writefile
            getgenv().writefile = function(path, data) log("writefile", {path, data}, nil); return old(path, data) end
            table.insert(FN.restores, function() getgenv().writefile = old end)
        end
        if readfile then
            local old = readfile
            getgenv().readfile = function(path) local r = old(path); log("readfile", {path}, r); return r end
            table.insert(FN.restores, function() getgenv().readfile = old end)
        end
        local req = (syn and syn.request) or http_request or (http and http.request) or request
        if req then
            local wrap = function(opts)
                local r = req(opts)
                log("request", {opts and opts.Url or "?", opts and opts.Method or "GET"}, r and r.Body)
                if r and type(r.Body) == "string" and #r.Body > 200 then
                    pcall(function()
                        local u = tostring(opts.Url):sub(1,60):gsub("[^%w]", "_")
                        FS.save("captures", string.format("req_%s_%dB.lua", u, #r.Body), r.Body)
                    end)
                end
                return r
            end
            getgenv().request = wrap
            if syn then pcall(function() syn.request = wrap end) end
            if http then pcall(function() http.request = wrap end) end
            table.insert(FN.restores, function()
                getgenv().request = req
                if syn then pcall(function() syn.request = req end) end
            end)
        end
        return "function tracer started (HttpGet, loadstring, writefile, readfile, request)"
    end
    function FN.stop()
        FN.active = false
        for _, r in ipairs(FN.restores) do pcall(r) end
        FN.restores = {}
        return "function tracer stopped, entries: "..#FN.trace
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

local VM = { trace = {}, active = false, handlers = {} }
do
    function VM.findDispatch()
        local candidates = {}
        if not getgc then return candidates end
        for _, v in pairs(getgc(true) or {}) do
            if type(v) == "table" then
                pcall(function()
                    local nFn, nTotal, maxK = 0, 0, 0
                    for k, val in pairs(v) do
                        nTotal = nTotal + 1
                        if type(k) == "number" then
                            if k > maxK then maxK = k end
                            if type(val) == "function" then nFn = nFn + 1 end
                        end
                    end
                    if maxK >= 20 and maxK <= 80 and nFn >= maxK * 0.8 and nTotal <= maxK + 5 then
                        table.insert(candidates, {tbl=v, size=maxK, fnCount=nFn})
                    end
                end)
            end
        end
        return candidates
    end
    function VM.hookDispatch(tbl)
        VM.trace = {}; VM.handlers = {}
        local hooked = 0
        for k, fn in pairs(tbl) do
            if type(k) == "number" and type(fn) == "function" then
                local ok, old = pcall(hookfunction, fn, function(...)
                    if VM.active and #VM.trace < CFG.opcodeLimit then
                        local args = {...}; local parts = {}
                        for i = 1, math.min(#args, 6) do
                            local a = args[i]; local t = type(a)
                            if t == "number" then parts[i] = tostring(a)
                            elseif t == "string" then parts[i] = string.format("%q", a:sub(1,30))
                            else parts[i] = t end
                        end
                        table.insert(VM.trace, string.format("OP[%d](%s)", k, table.concat(parts, ",")))
                    end
                    return fn(...)
                end)
                if ok then VM.handlers[k] = old; hooked = hooked + 1 end
            end
        end
        VM.active = true
        return "hooked "..hooked.." opcodes"
    end
    function VM.stop() VM.active = false; return "VM tracer paused, entries: "..#VM.trace end
    function VM.dump(name)
        name = name or "vmtrace_"..os.time()..".log"
        local out = "# VM opcode trace  entries="..#VM.trace.."\n"..table.concat(VM.trace, "\n")
        return FS.save("traces", name, out)
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
    local report = {"[MOONSEC UNWRAP] Pipeline start"}
    local hits = SIG.detect(src)
    table.insert(report, SIG.report(hits))
    local out, rep = STATIC.run(src)
    table.insert(report, rep)
    local blob = out:match("[\"'](%.:*[a-zA-Z]+::*%.*!?[^\"']*)")
    if blob and #blob > 500 then
        FS.save("output", (name or "unknown")..".moonsec_blob.txt", blob)
        table.insert(report, string.format("[MOONSEC] Extracted VM blob: %dB", #blob))
    end
    NC.start(); FN.start()
    pcall(function() loadstring(src)() end)
    task.wait(2)
    local cand = VM.findDispatch()
    table.insert(report, string.format("[MOONSEC] Found %d dispatch candidates", #cand))
    if cand[1] then
        table.insert(report, "[MOONSEC] "..VM.hookDispatch(cand[1].tbl))
        task.wait(CFG.traceTimeout - 2)
        VM.stop()
        VM.dump((name or "unknown").."_vmtrace.log")
    end
    NC.stop(); FN.stop()
    NC.dump((name or "unknown").."_namecall.log")
    FN.dump((name or "unknown").."_fntrace.log")
    FS.save("output", (name or "unknown")..".moonsec_static.lua", out)
    table.insert(report, "[MOONSEC] Wrote: .moonsec_static.lua + _vmtrace.log + _namecall.log + _fntrace.log")
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
        local o = Instance.new(class)
        for k, v in pairs(props) do o[k] = v end
        if parent then o.Parent = parent end
        return o
    end
    local screen = mk("ScreenGui", {Name = "SMAZ_DEOB_V2_UI", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999})
    pcall(function() screen.Parent = gethui and gethui() or game:GetService("CoreGui") end)
    if screen.Parent == nil then screen.Parent = LP:WaitForChild("PlayerGui") end

    local frame = mk("Frame", {Size = UDim2.new(0, CFG.uiWidth, 0, CFG.uiHeight), Position = UDim2.new(0.5, -CFG.uiWidth/2, 0.5, -CFG.uiHeight/2), BackgroundColor3 = Color3.fromRGB(20, 22, 26), BorderSizePixel = 0, Active = true, Draggable = true}, screen)
    mk("UICorner", {CornerRadius = UDim.new(0, 8)}, frame)
    mk("UIStroke", {Color = Color3.fromRGB(80, 90, 110), Thickness = 1, Transparency = 0.5}, frame)
    mk("TextLabel", {Size = UDim2.new(1, -20, 0, 28), Position = UDim2.new(0, 10, 0, 6), BackgroundTransparency = 1, Text = "SMAZ Deobfuscator v2  —  RightShift to toggle", Font = Enum.Font.Code, TextSize = 15, TextColor3 = Color3.fromRGB(220, 220, 230), TextXAlignment = Enum.TextXAlignment.Left}, frame)

    local btnRow = mk("Frame", {Size = UDim2.new(1, -20, 0, 32), Position = UDim2.new(0, 10, 0, 38), BackgroundTransparency = 1}, frame)
    mk("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6)}, btnRow)
    local function addBtn(label, cb)
        local b = mk("TextButton", {Size = UDim2.new(0, 90, 1, 0), BackgroundColor3 = Color3.fromRGB(45, 50, 60), BorderSizePixel = 0, Text = label, TextColor3 = Color3.fromRGB(220, 220, 230), Font = Enum.Font.Code, TextSize = 12}, btnRow)
        mk("UICorner", {CornerRadius = UDim.new(0, 4)}, b)
        b.MouseButton1Click:Connect(cb)
        return b
    end

    local left = mk("Frame", {Size = UDim2.new(0.35, -6, 1, -140), Position = UDim2.new(0, 10, 0, 78), BackgroundColor3 = Color3.fromRGB(28, 30, 36), BorderSizePixel = 0}, frame)
    mk("UICorner", {CornerRadius = UDim.new(0, 4)}, left)
    local right = mk("ScrollingFrame", {Size = UDim2.new(0.65, -4, 1, -140), Position = UDim2.new(0.35, 6, 0, 78), BackgroundColor3 = Color3.fromRGB(28, 30, 36), BorderSizePixel = 0, CanvasSize = UDim2.new(0, 0, 0, 800), ScrollBarThickness = 6}, frame)
    mk("UICorner", {CornerRadius = UDim.new(0, 4)}, right)
    local logBox = mk("TextLabel", {Size = UDim2.new(1, -12, 1, -12), Position = UDim2.new(0, 6, 0, 6), BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = 12, TextColor3 = Color3.fromRGB(200, 210, 215), Text = "[ready]  Files: workspace/"..CFG.workDir.."/input/  \nPress Refresh.", TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true}, right)
    local function log(s) logBox.Text = ("[%s] %s\n"):format(os.date("%H:%M:%S"), s) .. logBox.Text:sub(1, 6000) end

    local fileList = mk("ScrollingFrame", {Size = UDim2.new(1, -12, 1, -12), Position = UDim2.new(0, 6, 0, 6), BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(0, 0, 0, 0), ScrollBarThickness = 4}, left)
    mk("UIListLayout", {Padding = UDim.new(0, 2)}, fileList)
    local selected = nil
    local function refresh()
        for _, c in ipairs(fileList:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
        local files = scanLua(CFG.workDir.."/input")
        for _, out in ipairs(scanLua(CFG.workDir.."/output")) do table.insert(files, out) end
        for _, f in ipairs(files) do
            local btn = mk("TextButton", {Size = UDim2.new(1, -8, 0, 22), BackgroundColor3 = Color3.fromRGB(40, 44, 52), BorderSizePixel = 0, Text = " " .. f:match("[^/]+$"):sub(1, 40), TextColor3 = Color3.fromRGB(210, 215, 220), Font = Enum.Font.Code, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left}, fileList)
            btn.MouseButton1Click:Connect(function() selected = f; log("Selected: " .. f) end)
        end
        fileList.CanvasSize = UDim2.new(0, 0, 0, #files * 24 + 4)
        log("Refreshed: " .. #files .. " files")
    end
    local function readSelected()
        if not selected then log("! No file selected") return nil end
        local ok, data = pcall(readfile, selected)
        if not ok then log("! read failed: " .. tostring(data)) return nil end
        return data, selected:match("[^/]+$"):gsub("%.[^.]+$", "")
    end

    addBtn("Refresh", refresh)
    addBtn("Detect", function() local d = readSelected(); if d then log(SIG.report(SIG.detect(d))) end end)
    addBtn("Static", function()
        local d, n = readSelected(); if not d then return end
        local out, rep = STATIC.run(d)
        FS.save("output", n..".static.lua", out)
        log(rep.."\nSaved: output/"..n..".static.lua")
    end)
    addBtn("Dynamic", function()
        local d, n = readSelected(); if not d then return end
        local rep = dynamicDeob(d, n); FN.dump(n.."_fntrace.log")
        log(rep.."\nSaved: traces/"..n.."_fntrace.log")
    end)
    addBtn("Beautify", function()
        local d, n = readSelected(); if not d then return end
        local out = beautify(d); FS.save("output", n..".pretty.lua", out)
        log("Beautified: "..#d.."B -> "..#out.."B")
    end)
    addBtn("Namecall", function()
        local d, n = readSelected(); if not d then return end
        log(NC.start())
        task.spawn(function() pcall(loadstring, d) end)
        task.wait(CFG.traceTimeout)
        log(NC.stop())
        log("Saved: "..NC.dump(n.."_namecall.log"))
    end)
    addBtn("Fn Trace", function()
        local d, n = readSelected(); if not d then return end
        log(FN.start())
        task.spawn(function() pcall(loadstring, d) end)
        task.wait(CFG.traceTimeout)
        log(FN.stop())
        log("Saved: "..FN.dump(n.."_fntrace.log"))
    end)

    local btnRow2 = mk("Frame", {Size = UDim2.new(1, -20, 0, 32), Position = UDim2.new(0, 10, 1, -50), BackgroundTransparency = 1}, frame)
    mk("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6)}, btnRow2)
    local function addBtn2(label, cb, w)
        local b = mk("TextButton", {Size = UDim2.new(0, w or 90, 1, 0), BackgroundColor3 = Color3.fromRGB(55, 40, 60), BorderSizePixel = 0, Text = label, TextColor3 = Color3.fromRGB(220, 220, 230), Font = Enum.Font.Code, TextSize = 12}, btnRow2)
        mk("UICorner", {CornerRadius = UDim.new(0, 4)}, b)
        b.MouseButton1Click:Connect(cb)
    end
    addBtn2("MoonSec", function()
        local d, n = readSelected(); if not d then return end
        log("[MoonSec] start "..n.." (~"..CFG.traceTimeout.."s)")
        task.spawn(function() local _, rep = moonsecUnwrap(d, n); log(rep) end)
    end, 100)
    addBtn2("Full Pipeline", function()
        local d, n = readSelected(); if not d then return end
        log("[Full] start "..n)
        task.spawn(function()
            local h = SIG.detect(d); log(SIG.report(h))
            local st, rep = STATIC.run(d)
            FS.save("output", n..".static.lua", st)
            log(rep)
            local pretty = beautify(st); FS.save("output", n..".final.lua", pretty)
            log("Saved: output/"..n..".static.lua + .final.lua")
            local hasVM = false
            for _, hh in ipairs(h) do if hh.name:find("MoonSec") or hh.name == "PSU" or hh.name == "Iron" then hasVM = true; break end end
            if hasVM then
                log("VM detected — running MoonSec unwrap")
                local _, r2 = moonsecUnwrap(d, n); log(r2)
            end
        end)
    end, 110)
    addBtn2("Help", function()
        log("Files: workspace/"..CFG.workDir.."/  (input/ output/ traces/ captures/)")
        log("Buttons row 1: Refresh, Detect, Static, Dynamic, Beautify, Namecall, Fn Trace")
        log("Buttons row 2: MoonSec, Full Pipeline, Help, Unload")
    end, 60)
    addBtn2("Unload", function()
        pcall(function() screen:Destroy() end)
        FN.stop(); NC.stop(); VM.stop()
        ENV.__DEOB_V2_UNLOAD = nil; ENV.SMAZ_DEOB = nil
    end, 80)

    local visible = true
    UIS.InputBegan:Connect(function(inp, gpe)
        if gpe then return end
        if inp.KeyCode == Enum.KeyCode.RightShift then visible = not visible; frame.Visible = visible end
    end)
    UI.log = log; UI.refresh = refresh; UI.screen = screen
    refresh()
end

ENV.SMAZ_DEOB = {
    version = "2.0.0",
    detectSig = SIG.detect, signatureReport = SIG.report,
    staticDeob = STATIC.run, beautify = beautify,
    dynamicDeob = dynamicDeob, moonsecUnwrap = moonsecUnwrap,
    namecallStart = NC.start, namecallStop = NC.stop, namecallDump = NC.dump,
    fnStart = FN.start, fnStop = FN.stop, fnDump = FN.dump,
    vmFindDispatch = VM.findDispatch, vmHook = VM.hookDispatch, vmStop = VM.stop, vmDump = VM.dump,
    scanLua = scanLua, CFG = CFG,
}
ENV.__DEOB_V2_UNLOAD = function()
    pcall(function() UI.screen:Destroy() end)
    FN.stop(); NC.stop(); VM.stop()
    ENV.__DEOB_V2_UNLOAD = nil; ENV.SMAZ_DEOB = nil
end

print("[SMAZ Deobfuscator v2] loaded. RightShift = toggle UI.")
return ENV.SMAZ_DEOB
