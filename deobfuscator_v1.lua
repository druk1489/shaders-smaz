-- SMAZ Moonsec/Universal Deobfuscator v1
-- druk1489 / shaders-smaz
-- Target: Madium / Xeno / Wave / Solara / any executor with full UNC/sUNC
-- Usage: loadstring(game:HttpGet("https://raw.githubusercontent.com/druk1489/shaders-smaz/main/deobfuscator_v1.lua"))()
-- Then open the UI, pick a .lua file from workspace/, choose action.

if getgenv().__DEOB_V1_UNLOAD then pcall(getgenv().__DEOB_V1_UNLOAD) end

local Players     = game:GetService("Players")
local CoreGui     = game:GetService("CoreGui")
local RunService  = game:GetService("RunService")
local UIS         = game:GetService("UserInputService")
local TS          = game:GetService("TweenService")
local LP          = Players.LocalPlayer

-- ==========================================================
-- CFG
-- ==========================================================
local CFG = {
	workDir            = "smaz_deob",
	maxFileSize        = 16 * 1024 * 1024,
	dynamicTimeout     = 6,
	maxScanDepth       = 5,
	prettyMaxLineHint  = 120,
	uiWidth            = 780,
	uiHeight           = 460,
}

local SMAZ_DEOB = { CFG = CFG, __version = "1.0", __loaded = true }
getgenv().SMAZ_DEOB = SMAZ_DEOB

-- ==========================================================
-- FS HELPERS  (UNC: listfiles, isfile, isfolder, readfile, writefile, makefolder)
-- ==========================================================
local function ensureDir(p) if not isfolder(p) then makefolder(p) end end
ensureDir(CFG.workDir)
ensureDir(CFG.workDir.."/output")
ensureDir(CFG.workDir.."/captures")

local function safeName(s)
	s = tostring(s or "unnamed")
	s = s:gsub("[^%w%._%-]", "_")
	if #s > 80 then s = s:sub(1, 80) end
	return s
end

local function scanLua(dir, depth, out)
	depth = depth or 0
	out   = out or {}
	if depth > CFG.maxScanDepth then return out end
	local ok, list = pcall(listfiles, dir)
	if not ok or not list then return out end
	for _, path in ipairs(list) do
		local isDir = false
		pcall(function() isDir = isfolder(path) end)
		if isDir then
			scanLua(path, depth + 1, out)
		else
			local low = path:lower()
			if low:sub(-4) == ".lua" or low:sub(-5) == ".luau" or low:sub(-4) == ".txt" then
				local ok2, sz = pcall(function() return #readfile(path) end)
				if ok2 and sz and sz <= CFG.maxFileSize then
					table.insert(out, { path = path, size = sz })
				end
			end
		end
	end
	table.sort(out, function(a, b) return a.path < b.path end)
	return out
end

-- ==========================================================
-- SIGNATURE DETECT
-- ==========================================================
local function detectSig(src)
	local sigs = {}
	local head = src:sub(1, math.min(#src, 8192))
	local low  = head:lower()
	if low:find("moonsec", 1, true)  then table.insert(sigs, "Moonsec") end
	if low:find("psu",     1, true)  then table.insert(sigs, "PSU") end
	if low:find("luraph",  1, true)  then table.insert(sigs, "Luraph") end
	if low:find("ironbrew",1, true)  then table.insert(sigs, "Ironbrew") end
	if low:find("prometheus",1,true) then table.insert(sigs, "Prometheus") end
	if src:find("return%s*%(?%s*function%s*%(") and src:find("string%.byte") and src:find("bit32") then
		table.insert(sigs, "V3-style VM interpreter")
	end
	if src:find("string%.char") and src:find("\\%d%d") then
		table.insert(sigs, "byte-encoded strings")
	end
	if head:sub(1, 40):find("%-%-%[%[") then
		table.insert(sigs, "block-comment header")
	end
	return (#sigs == 0) and "plain / unknown" or table.concat(sigs, ", ")
end

-- ==========================================================
-- STATIC PASSES
-- ==========================================================

-- Pass A: unescape \ddd and \xNN escapes
local function passUnescape(src)
	local n = 0
	local out = src:gsub('\\(%d%d?%d?)', function(d)
		local b = tonumber(d)
		if b and b < 256 then n = n + 1; return string.char(b) end
		return "\\" .. d
	end)
	out = out:gsub('\\x(%x%x)', function(h) n = n + 1; return string.char(tonumber(h, 16)) end)
	return out, n
end

-- Pass B: evaluate string-table constants like `local T = { "a", "b", ... }`
local function passStringTable(src)
	local subs = 0
	local out  = src
	for name, body in src:gmatch("local%s+([%w_]+)%s*=%s*(%b{})") do
		if #name <= 4 then
			local fn = loadstring("return " .. body)
			if fn then
				local sb = { string = string, table = table, math = math, bit32 = bit32,
					tonumber = tonumber, tostring = tostring, select = select, type = type }
				setfenv(fn, sb)
				local ok, tbl = pcall(fn)
				if ok and type(tbl) == "table" then
					local nstr = 0
					for _, v in pairs(tbl) do if type(v) == "string" then nstr = nstr + 1 end end
					if nstr >= 5 then
						local pat = name:gsub("%W", "%%%1") .. "%s*%[%s*(%-?%d+)%s*%]"
						out = out:gsub(pat, function(k)
							local v = tbl[tonumber(k)]
							if type(v) == "string" then subs = subs + 1; return string.format("%q", v) end
						end)
					end
				end
			end
		end
	end
	return out, subs
end

-- Pass C: evaluate small decoder function calls `D("encoded")` -> literal string
local function passDecoderCalls(src)
	local subs = 0
	local out  = src
	for name, argBlock, bodyBlock in src:gmatch("local%s+function%s+([%w_]+)%s*(%b())%s*(.-)%s*end") do
		if #name <= 4 and bodyBlock:find("string%.char") and not bodyBlock:find("function", 1, true) then
			local fnCode = "local function " .. name .. argBlock .. " " .. bodyBlock .. " end return " .. name
			local fn = loadstring(fnCode)
			if fn then
				local sb = { string = string, table = table, math = math, bit32 = bit32,
					tonumber = tonumber, tostring = tostring, select = select, type = type,
					pcall = pcall, ipairs = ipairs, pairs = pairs }
				setfenv(fn, sb)
				local ok, decoder = pcall(fn)
				if ok and type(decoder) == "function" then
					out = out:gsub(name .. "%s*%(%s*(\"[^\"]-\")%s*%)", function(argLit)
						local aFn = loadstring("return " .. argLit)
						if aFn then
							local ok2, argVal = pcall(aFn)
							if ok2 then
								local ok3, dec = pcall(decoder, argVal)
								if ok3 and type(dec) == "string" then
									subs = subs + 1
									return string.format("%q", dec)
								end
							end
						end
					end)
				end
			end
		end
	end
	return out, subs
end

-- Pass D: inline single-use short local strings
local function passFoldLocals(src)
	local subs = 0
	local out  = src
	for name, val in src:gmatch('local ([%w_]+)%s*=%s*("[^"\n]-")\n') do
		if #name <= 3 then
			local usePat = "([^%w_])" .. name .. "([^%w_])"
			local count = 0
			for _ in out:gmatch(usePat) do count = count + 1 end
			if count == 1 then
				out = out:gsub("local " .. name .. "%s*=%s*" .. val:gsub("%W", "%%%1") .. "\n?", "", 1)
				out = out:gsub(usePat, "%1" .. val .. "%2")
				subs = subs + 1
			end
		end
	end
	return out, subs
end

local function staticDeob(src, log)
	log = log or function() end
	local orig = #src
	log("[STATIC] input=" .. orig .. "B  sig=" .. detectSig(src))
	local s = src
	local r
	s, r = passUnescape(s);      log("[STATIC] unescape:      " .. r .. " escapes")
	s, r = passStringTable(s);   log("[STATIC] stringTable:   " .. r .. " subs")
	s, r = passDecoderCalls(s);  log("[STATIC] decoderCalls:  " .. r .. " subs")
	s, r = passFoldLocals(s);    log("[STATIC] foldLocals:    " .. r .. " subs")
	log("[STATIC] output=" .. #s .. "B  delta=" .. (#s - orig))
	return s
end

-- ==========================================================
-- BEAUTIFIER (compact -> readable, indent tracking)
-- ==========================================================
local function beautify(src)
	-- Protect strings & comments
	local placeholders = {}
	local function protect(pat)
		src = src:gsub(pat, function(m)
			table.insert(placeholders, m)
			return "\0P" .. #placeholders .. "\0"
		end)
	end
	protect("%-%-%[(=-)%[.-%]%1%]")   -- long comments
	protect("%-%-[^\n]*")             -- line comments
	protect('"[^"\n]-"')              -- "..." strings
	protect("'[^'\n]-'")              -- '...' strings
	protect("%[(=-)%[.-%]%1%]")       -- long strings

	-- Insert newlines after common statement terminators
	src = src:gsub(";%s*", ";\n")
	src = src:gsub("([%w_%)])%s+(local)%s", "%1\n%2 ")
	src = src:gsub("([%w_%)])%s+(if)%s",   "%1\n%2 ")
	src = src:gsub("([%w_%)])%s+(for)%s",  "%1\n%2 ")
	src = src:gsub("([%w_%)])%s+(while)%s","%1\n%2 ")
	src = src:gsub("([%w_%)])%s+(return)%s","%1\n%2 ")
	src = src:gsub("([%w_%)])%s+(function)%s","%1\n%2 ")
	src = src:gsub("([%w_%)])%s+(end)([^%w_])","%1\n%2%3")
	src = src:gsub("([%w_%)])%s+(elseif)%s","%1\n%2 ")
	src = src:gsub("([%w_%)])%s+(else)([^%w_])","%1\n%2%3")
	src = src:gsub("([%w_%)])%s+(until)%s","%1\n%2 ")
	src = src:gsub("(then)%s+(%w)", "%1\n%2")
	src = src:gsub("(do)%s+(%w)",   "%1\n%2")
	src = src:gsub("(repeat)%s+(%w)", "%1\n%2")

	-- Indent based on keyword stack
	local lines = {}
	for line in (src .. "\n"):gmatch("([^\n]*)\n") do
		table.insert(lines, line)
	end

	local out    = {}
	local indent = 0
	for _, raw in ipairs(lines) do
		local ln = raw:match("^%s*(.-)%s*$") or ""
		if ln == "" then
			table.insert(out, "")
		else
			local firstWord = ln:match("^(%w+)") or ""
			if firstWord == "end" or firstWord == "until"
				or firstWord == "elseif" or firstWord == "else"
				or firstWord == "}" or ln:sub(1,1) == "}" then
				indent = math.max(0, indent - 1)
			end

			table.insert(out, string.rep("    ", indent) .. ln)

			local opens, closes = 0, 0
			for w in ln:gmatch("([%a_][%w_]*)") do
				if w == "function" or w == "if" or w == "for"
					or w == "while" or w == "do" or w == "repeat" then
					opens = opens + 1
				elseif w == "end" or w == "until" then
					closes = closes + 1
				end
			end
			-- "if X then <stuff> end" counted twice (if + end); balance out only when both present
			if opens > 0 and closes > 0 then
				local m = math.min(opens, closes)
				opens  = opens  - m
				closes = closes - m
			end
			indent = indent + opens - closes
			if indent < 0 then indent = 0 end
			if firstWord == "elseif" or firstWord == "else" then
				indent = indent + 1
			end
		end
	end

	local result = table.concat(out, "\n")

	-- Restore protected chunks
	result = result:gsub("\0P(%d+)\0", function(i) return placeholders[tonumber(i)] end)
	return result
end

-- ==========================================================
-- DYNAMIC DEOB (hook-based capture)
-- ==========================================================
local function dynamicDeob(src, log, onDone)
	log = log or function() end
	local captures = {}
	local hooked   = {}

	local function cap(kind, text, meta)
		if type(text) ~= "string" then return end
		if #text < 8 then return end
		table.insert(captures, { kind = kind, text = text, meta = meta or "", len = #text })
		log(string.format("[HOOK] %-14s +%dB  %s", kind, #text, tostring(meta or "")))
	end

	-- Hook loadstring / loadfile / load  (this is where the anpacker gold usually lands)
	local orig_loadstring = loadstring
	local orig_load       = load
	local orig_loadfile   = loadfile

	getgenv().loadstring = function(chunk, name, ...)
		cap("loadstring", tostring(chunk), name or "?")
		return orig_loadstring(chunk, name, ...)
	end
	getgenv().load = function(chunk, name, ...)
		if type(chunk) == "string" then cap("load", chunk, name or "?") end
		return orig_load(chunk, name, ...)
	end
	if orig_loadfile then
		getgenv().loadfile = function(p, ...)
			if type(p) == "string" and isfile and isfile(p) then
				local ok, txt = pcall(readfile, p)
				if ok then cap("loadfile", txt, p) end
			end
			return orig_loadfile(p, ...)
		end
	end
	table.insert(hooked, function()
		getgenv().loadstring = orig_loadstring
		getgenv().load       = orig_load
		if orig_loadfile then getgenv().loadfile = orig_loadfile end
	end)

	-- Hook HttpGet / HttpGetAsync / request
	local orig_HttpGet
	if hookfunction then
		orig_HttpGet = hookfunction(game.HttpGet, function(self, url, ...)
			local res = orig_HttpGet(self, url, ...)
			if type(res) == "string" then cap("HttpGet", res, url) end
			return res
		end)
		table.insert(hooked, function() hookfunction(game.HttpGet, orig_HttpGet) end)
	else
		log("[WARN] hookfunction not available -- HttpGet not intercepted")
	end

	-- Run target in pcall
	log("[DYN] running target (" .. #src .. "B)...")
	local fn, err = orig_loadstring(src)
	if not fn then
		log("[DYN] compile error: " .. tostring(err))
	else
		local ok, runErr = pcall(fn)
		if not ok then log("[DYN] runtime error (expected): " .. tostring(runErr)) end
	end

	-- Wait briefly for async captures
	task.wait(CFG.dynamicTimeout)

	-- Restore hooks
	for _, un in ipairs(hooked) do pcall(un) end

	log("[DYN] captured chunks: " .. #captures)
	if onDone then onDone(captures) end
	return captures
end

-- ==========================================================
-- UI
-- ==========================================================
local function newUI()
	local old = CoreGui:FindFirstChild("SMAZ_DEOB_UI")
	if old then old:Destroy() end

	local gui = Instance.new("ScreenGui")
	gui.Name             = "SMAZ_DEOB_UI"
	gui.ResetOnSpawn     = false
	gui.IgnoreGuiInset   = true
	gui.ZIndexBehavior   = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder     = 900
	pcall(function() gui.Parent = CoreGui end)
	if not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end

	local main = Instance.new("Frame", gui)
	main.Name = "Main"
	main.Size = UDim2.fromOffset(CFG.uiWidth, CFG.uiHeight)
	main.Position = UDim2.fromScale(0.5, 0.5)
	main.AnchorPoint = Vector2.new(0.5, 0.5)
	main.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
	main.BorderSizePixel = 0
	main.Active = true
	main.Draggable = true
	Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)
	local stroke = Instance.new("UIStroke", main)
	stroke.Color = Color3.fromRGB(60, 68, 84); stroke.Thickness = 1

	-- Title bar
	local title = Instance.new("TextLabel", main)
	title.Size = UDim2.new(1, -80, 0, 28)
	title.Position = UDim2.new(0, 10, 0, 4)
	title.BackgroundTransparency = 1
	title.Text = "SMAZ Deobfuscator v1.0  ::  Moonsec/Universal"
	title.Font = Enum.Font.GothamBold
	title.TextSize = 14
	title.TextColor3 = Color3.fromRGB(220, 225, 235)
	title.TextXAlignment = Enum.TextXAlignment.Left

	local closeBtn = Instance.new("TextButton", main)
	closeBtn.Size = UDim2.fromOffset(28, 24)
	closeBtn.Position = UDim2.new(1, -34, 0, 6)
	closeBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
	closeBtn.BorderSizePixel = 0
	closeBtn.Text = "X"
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 14
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 4)

	-- Left: file list
	local leftPanel = Instance.new("Frame", main)
	leftPanel.Size = UDim2.new(0, 300, 1, -80)
	leftPanel.Position = UDim2.new(0, 8, 0, 40)
	leftPanel.BackgroundColor3 = Color3.fromRGB(28, 32, 40)
	leftPanel.BorderSizePixel = 0
	Instance.new("UICorner", leftPanel).CornerRadius = UDim.new(0, 6)

	local leftHdr = Instance.new("TextLabel", leftPanel)
	leftHdr.Size = UDim2.new(1, 0, 0, 22)
	leftHdr.BackgroundTransparency = 1
	leftHdr.Text = "  Lua files in workspace/"
	leftHdr.Font = Enum.Font.GothamSemibold
	leftHdr.TextSize = 12
	leftHdr.TextColor3 = Color3.fromRGB(160, 170, 190)
	leftHdr.TextXAlignment = Enum.TextXAlignment.Left

	local fileList = Instance.new("ScrollingFrame", leftPanel)
	fileList.Size = UDim2.new(1, -8, 1, -30)
	fileList.Position = UDim2.new(0, 4, 0, 26)
	fileList.BackgroundTransparency = 1
	fileList.BorderSizePixel = 0
	fileList.ScrollBarThickness = 4
	fileList.CanvasSize = UDim2.new(0, 0, 0, 0)
	fileList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	local listLayout = Instance.new("UIListLayout", fileList)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 2)

	-- Right: output
	local rightPanel = Instance.new("Frame", main)
	rightPanel.Size = UDim2.new(1, -324, 1, -80)
	rightPanel.Position = UDim2.new(0, 316, 0, 40)
	rightPanel.BackgroundColor3 = Color3.fromRGB(28, 32, 40)
	rightPanel.BorderSizePixel = 0
	Instance.new("UICorner", rightPanel).CornerRadius = UDim.new(0, 6)

	local rightHdr = Instance.new("TextLabel", rightPanel)
	rightHdr.Size = UDim2.new(1, 0, 0, 22)
	rightHdr.BackgroundTransparency = 1
	rightHdr.Text = "  Log / preview"
	rightHdr.Font = Enum.Font.GothamSemibold
	rightHdr.TextSize = 12
	rightHdr.TextColor3 = Color3.fromRGB(160, 170, 190)
	rightHdr.TextXAlignment = Enum.TextXAlignment.Left

	local outScroll = Instance.new("ScrollingFrame", rightPanel)
	outScroll.Size = UDim2.new(1, -8, 1, -30)
	outScroll.Position = UDim2.new(0, 4, 0, 26)
	outScroll.BackgroundTransparency = 1
	outScroll.BorderSizePixel = 0
	outScroll.ScrollBarThickness = 4
	outScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	outScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

	local outText = Instance.new("TextLabel", outScroll)
	outText.Size = UDim2.new(1, -4, 0, 0)
	outText.AutomaticSize = Enum.AutomaticSize.Y
	outText.BackgroundTransparency = 1
	outText.Font = Enum.Font.Code
	outText.TextSize = 11
	outText.TextColor3 = Color3.fromRGB(200, 210, 220)
	outText.TextXAlignment = Enum.TextXAlignment.Left
	outText.TextYAlignment = Enum.TextYAlignment.Top
	outText.TextWrapped = true
	outText.Text = "Pick a file on the left, then press a button below.\nOutputs saved to workspace/" .. CFG.workDir .. "/output/"

	-- Bottom: action buttons
	local bar = Instance.new("Frame", main)
	bar.Size = UDim2.new(1, -16, 0, 34)
	bar.Position = UDim2.new(0, 8, 1, -38)
	bar.BackgroundTransparency = 1

	local function mkBtn(x, w, txt, col)
		local b = Instance.new("TextButton", bar)
		b.Size = UDim2.new(0, w, 1, 0)
		b.Position = UDim2.new(0, x, 0, 0)
		b.BackgroundColor3 = col
		b.BorderSizePixel = 0
		b.Text = txt
		b.Font = Enum.Font.GothamSemibold
		b.TextSize = 12
		b.TextColor3 = Color3.new(1, 1, 1)
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
		return b
	end

	local btnRefresh  = mkBtn(0,   90, "Refresh",       Color3.fromRGB(70, 90, 130))
	local btnStatic   = mkBtn(96,  110, "Static deob",   Color3.fromRGB(70, 130, 90))
	local btnDynamic  = mkBtn(212, 130, "Dynamic deob",  Color3.fromRGB(130, 90, 70))
	local btnBeautify = mkBtn(348, 90,  "Beautify",      Color3.fromRGB(90, 90, 130))
	local btnAll      = mkBtn(444, 130, "Full pipeline", Color3.fromRGB(150, 60, 130))
	local btnUnload   = mkBtn(580, 90,  "Unload",        Color3.fromRGB(120, 60, 60))

	-- State
	local selected = nil
	local buttons  = {}

	local function appendLog(...)
		local parts = { ... }
		for i, v in ipairs(parts) do parts[i] = tostring(v) end
		local line = table.concat(parts, " ")
		outText.Text = outText.Text .. "\n" .. line
	end

	local function clearLog(t)
		outText.Text = t or ""
	end

	local function refreshList()
		for _, b in ipairs(buttons) do b:Destroy() end
		table.clear(buttons)
		local files = scanLua("")
		for i, e in ipairs(files) do
			local b = Instance.new("TextButton", fileList)
			b.Size = UDim2.new(1, -4, 0, 22)
			b.BackgroundColor3 = Color3.fromRGB(36, 40, 50)
			b.BorderSizePixel = 0
			b.Font = Enum.Font.Code
			b.TextSize = 11
			b.TextColor3 = Color3.fromRGB(200, 210, 220)
			b.TextXAlignment = Enum.TextXAlignment.Left
			b.Text = string.format("  %s  (%d B)", e.path, e.size)
			b.LayoutOrder = i
			Instance.new("UICorner", b).CornerRadius = UDim.new(0, 3)
			b.MouseButton1Click:Connect(function()
				selected = e
				for _, x in ipairs(buttons) do x.BackgroundColor3 = Color3.fromRGB(36, 40, 50) end
				b.BackgroundColor3 = Color3.fromRGB(70, 110, 140)
				clearLog("Selected: " .. e.path .. "  (" .. e.size .. " bytes)\n")
				local ok, src = pcall(readfile, e.path)
				if ok then
					appendLog("Signature: " .. detectSig(src))
					appendLog("Head: " .. src:sub(1, 200):gsub("\n", " "))
				end
			end)
			table.insert(buttons, b)
		end
		clearLog("Found " .. #files .. " lua files in workspace/. Click one to select.")
	end

	local function withSelected(fn)
		if not selected then clearLog("No file selected."); return end
		local ok, src = pcall(readfile, selected.path)
		if not ok then clearLog("readfile failed: " .. tostring(src)); return end
		fn(selected, src)
	end

	local function outPath(kind)
		local base = safeName((selected.path:match("([^/\\]+)$")) or selected.path)
		return CFG.workDir .. "/output/" .. base:gsub("%.lua$", ""):gsub("%.txt$", "") .. "." .. kind .. ".lua"
	end

	btnRefresh.MouseButton1Click:Connect(refreshList)

	btnStatic.MouseButton1Click:Connect(function()
		withSelected(function(sel, src)
			clearLog("[STATIC] " .. sel.path)
			local out = staticDeob(src, appendLog)
			local p = outPath("static")
			writefile(p, out)
			appendLog("Saved -> " .. p)
		end)
	end)

	btnDynamic.MouseButton1Click:Connect(function()
		withSelected(function(sel, src)
			clearLog("[DYNAMIC] " .. sel.path .. "  timeout=" .. CFG.dynamicTimeout .. "s")
			task.spawn(function()
				local captures = dynamicDeob(src, appendLog)
				if #captures == 0 then
					appendLog("[DYN] no captures. Target may not use loadstring/HttpGet.")
					return
				end
				table.sort(captures, function(a, b) return a.len > b.len end)
				local base = safeName((sel.path:match("([^/\\]+)$")) or sel.path)
				local dir  = CFG.workDir .. "/captures/" .. base:gsub("%..-$", "")
				ensureDir(dir)
				for i, c in ipairs(captures) do
					local fn = string.format("%s/%02d_%s_%dB.lua", dir, i, c.kind, c.len)
					writefile(fn, "-- kind=" .. c.kind .. "  meta=" .. tostring(c.meta) .. "\n\n" .. c.text)
				end
				appendLog("[DYN] wrote " .. #captures .. " chunks to " .. dir)
			end)
		end)
	end)

	btnBeautify.MouseButton1Click:Connect(function()
		withSelected(function(sel, src)
			clearLog("[BEAUTIFY] " .. sel.path)
			local out = beautify(src)
			local p = outPath("pretty")
			writefile(p, out)
			appendLog("Saved -> " .. p .. "  (" .. #out .. "B)")
		end)
	end)

	btnAll.MouseButton1Click:Connect(function()
		withSelected(function(sel, src)
			clearLog("[PIPELINE] " .. sel.path)
			task.spawn(function()
				local s = staticDeob(src, appendLog)
				appendLog("---")
				appendLog("[PIPELINE] running dynamic pass...")
				local captures = dynamicDeob(s, appendLog)
				local picked = s
				if #captures > 0 then
					table.sort(captures, function(a, b) return a.len > b.len end)
					picked = captures[1].text
					appendLog("[PIPELINE] using largest dynamic capture (" .. #picked .. "B)")
				else
					appendLog("[PIPELINE] no dynamic captures, using static output")
				end
				appendLog("---")
				appendLog("[PIPELINE] beautifying...")
				local final = beautify(picked)
				local p = outPath("final")
				writefile(p, final)
				appendLog("[PIPELINE] final -> " .. p .. "  (" .. #final .. "B)")
			end)
		end)
	end)

	btnUnload.MouseButton1Click:Connect(function()
		if getgenv().__DEOB_V1_UNLOAD then getgenv().__DEOB_V1_UNLOAD() end
	end)

	closeBtn.MouseButton1Click:Connect(function()
		main.Visible = not main.Visible
	end)

	-- RightShift toggle
	local inputConn = UIS.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.KeyCode == Enum.KeyCode.RightShift then
			main.Visible = not main.Visible
		end
	end)

	getgenv().__DEOB_V1_UNLOAD = function()
		pcall(function() inputConn:Disconnect() end)
		pcall(function() gui:Destroy() end)
		getgenv().__DEOB_V1_UNLOAD = nil
		getgenv().SMAZ_DEOB = nil
	end

	refreshList()
	return gui
end

newUI()

-- ==========================================================
-- PUBLIC API (getgenv().SMAZ_DEOB.*)
-- ==========================================================
SMAZ_DEOB.detectSig   = detectSig
SMAZ_DEOB.staticDeob  = staticDeob
SMAZ_DEOB.dynamicDeob = dynamicDeob
SMAZ_DEOB.beautify    = beautify
SMAZ_DEOB.scanLua     = scanLua

print("[SMAZ_DEOB] v1.0 loaded. RightShift = toggle UI.")
