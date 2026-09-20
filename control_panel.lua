-- SMAZ Studio Control Panel v5
-- Профессиональный редактор шейдеров SMAZ (как в Blender):
-- * полное редактирование настроек Roblox (Lighting + все виды пост-эффектов);
-- * второй режим блюра — по дистанции (может делегироваться Atmosphere или работать автономно);
-- * зерно (grain), виньетка, глубина резкости с автофокусом, режим живой камеры;
-- * управление модулями SMAZ (молнии/торнадо/дождь/отражения) и пресетами.

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local pgui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 5)
if not pgui then return end
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local old = pgui:FindFirstChild("SMAZ_ControlPanel")
if old then old:Destroy() end

local genv = getgenv or function() return _G end
local G = genv()
local ATMOS = G.SMAZ_ATMOS
local RN = G.SMAZ_RAIN
local TN = G.SMAZ_TORNADO
local LG = G.SMAZ_LIGHTNING
local RF = G.SMAZ_REFL
local PR = G.SMAZ_PRESETS

local uiFx = {
	grain = { on = false, amt = 0.5 },
	vig   = { on = false, amt = 0.35, color = Color3.new(0, 0, 0) },
	dof   = { auto = false },
}
local wCyc    = { on = false, every = 15 }
local camFov  = { manual = 70 }
local camBreath = { on = false, amp = 1.5, speed = 0.8 }

local ACCENT  = Color3.fromRGB(90, 130, 255)
local DANGER  = Color3.fromRGB(235, 80, 90)
local OK      = Color3.fromRGB(60, 170, 110)
local BACK    = Color3.fromRGB(16, 18, 26)
local CARD    = Color3.fromRGB(24, 27, 38)
local LINE    = Color3.fromRGB(45, 50, 68)
local TXT     = Color3.fromRGB(226, 230, 244)
local SUB     = Color3.fromRGB(150, 156, 180)

-- =========================================================
-- КОРЕНЬ
-- =========================================================
local gui = Instance.new("ScreenGui")
gui.Name = "SMAZ_ControlPanel"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 500
gui.Parent = pgui

local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.new(0, 340, 0, 560)
main.Position = UDim2.new(1, -360, 0, 60)
main.BackgroundColor3 = BACK
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.ClipsDescendants = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)
local stroke = Instance.new("UIStroke"); stroke.Color = LINE; stroke.Thickness = 1; stroke.Parent = main

-- =========================================================
-- ЗАГОЛОВОК
-- =========================================================
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 42)
header.BackgroundColor3 = Color3.fromRGB(22, 25, 36)
header.BorderSizePixel = 0
header.Parent = main
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 12)
local headerLine = Instance.new("Frame")
headerLine.Size = UDim2.new(1, 0, 0, 1)
headerLine.Position = UDim2.new(0, 0, 1, -1)
headerLine.BackgroundColor3 = LINE
headerLine.BorderSizePixel = 0
headerLine.Parent = header

local logo = Instance.new("TextLabel")
logo.Size = UDim2.new(0, 26, 0, 26)
logo.Position = UDim2.new(0, 10, 0, 8)
logo.BackgroundColor3 = ACCENT
logo.Text = "SMAZ"
logo.TextColor3 = Color3.fromRGB(10, 14, 24)
logo.Font = Enum.Font.GothamBlack
logo.TextSize = 12
logo.Parent = header
Instance.new("UICorner", logo).CornerRadius = UDim.new(0, 7)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(0, 220, 1, 0)
title.Position = UDim2.new(0, 44, 0, 0)
title.BackgroundTransparency = 1
title.Text = "SMAZ  STUDIO"
title.TextColor3 = TXT
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header
local subT = Instance.new("TextLabel")
subT.Size = UDim2.new(0, 220, 0, 16)
subT.Position = UDim2.new(0, 44, 0, 22)
subT.BackgroundTransparency = 1
subT.Text = "editor  v5  /  shaders" .. (ATMOS and " / atmos" or " / standalone")
subT.TextColor3 = SUB
subT.Font = Enum.Font.Gotham
subT.TextSize = 10
subT.TextXAlignment = Enum.TextXAlignment.Left
subT.Parent = header

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 30, 0, 26)
minBtn.Position = UDim2.new(1, -72, 0, 8)
minBtn.BackgroundColor3 = CARD
minBtn.BorderSizePixel = 0
minBtn.Text = "—"
minBtn.TextColor3 = TXT
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 14
minBtn.Parent = header
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 7)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 30, 0, 26)
closeBtn.Position = UDim2.new(1, -36, 0, 8)
closeBtn.BackgroundColor3 = DANGER
closeBtn.BorderSizePixel = 0
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 13
closeBtn.Parent = header
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 7)

local reopenBtn = Instance.new("TextButton")
reopenBtn.Size = UDim2.new(0, 120, 0, 30)
reopenBtn.Position = UDim2.new(1, -140, 0, 10)
reopenBtn.BackgroundColor3 = BACK
reopenBtn.BorderSizePixel = 0
reopenBtn.Text = "SMAZ Studio"
reopenBtn.TextColor3 = TXT
reopenBtn.Font = Enum.Font.GothamBold
reopenBtn.TextSize = 12
reopenBtn.Visible = false
reopenBtn.Parent = gui
Instance.new("UICorner", reopenBtn).CornerRadius = UDim.new(0, 8)
local rstroke = Instance.new("UIStroke"); rstroke.Color = ACCENT; rstroke.Thickness = 1; rstroke.Parent = reopenBtn

minBtn.MouseButton1Click:Connect(function() main.Visible = false; reopenBtn.Visible = true end)
closeBtn.MouseButton1Click:Connect(function() gui:Destroy() end)
reopenBtn.MouseButton1Click:Connect(function() main.Visible = true; reopenBtn.Visible = false end)

UIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.RightControl then
		main.Visible = not main.Visible
		reopenBtn.Visible = not main.Visible
	end
end)

-- =========================================================
-- САЙДБАР + КОНТЕНТ
-- =========================================================
local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, 96, 1, -50)
sidebar.Position = UDim2.new(0, 0, 0, 50)
sidebar.BackgroundColor3 = Color3.fromRGB(13, 15, 22)
sidebar.BorderSizePixel = 0
sidebar.Parent = main

local content = Instance.new("ScrollingFrame")
content.Size = UDim2.new(1, -96, 1, -50)
content.Position = UDim2.new(0, 96, 0, 50)
content.BackgroundColor3 = Color3.fromRGB(16, 18, 26)
content.BorderSizePixel = 0
content.ScrollBarThickness = 4
content.ScrollBarImageColor3 = ACCENT
content.AutomaticCanvasSize = Enum.AutomaticSize.Y
content.Parent = main
local contentList = Instance.new("UIListLayout")
contentList.Padding = UDim.new(0, 6)
contentList.SortOrder = Enum.SortOrder.LayoutOrder
contentList.Parent = content
local contentPad = Instance.new("UIPadding")
contentPad.PaddingTop = UDim.new(0, 8)
contentPad.PaddingBottom = UDim.new(0, 10)
contentPad.PaddingLeft = UDim.new(0, 8)
contentPad.PaddingRight = UDim.new(0, 8)
contentPad.Parent = content

local sections = {}   -- name -> {frame=, refreshers={}}
local navButtons = {}
local activeSection = nil

local function makeSection(name, order)
	local card = Instance.new("Frame")
	card.Name = name
	card.Size = UDim2.new(1, 0, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = CARD
	card.BorderSizePixel = 0
	card.LayoutOrder = order
	card.Visible = false
	card.Parent = content
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = card
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 4)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = card
	local h = Instance.new("TextLabel")
	h.Size = UDim2.new(1, 0, 0, 24)
	h.BackgroundTransparency = 1
	h.Text = name
	h.TextColor3 = ACCENT
	h.Font = Enum.Font.GothamBold
	h.TextSize = 12
	h.TextXAlignment = Enum.TextXAlignment.Left
	h.LayoutOrder = 0
	h.Parent = card
	local rec = {frame = card, refreshers = {}}
	sections[name] = rec
	return rec
end

local function showSection(name)
	for n, rec in pairs(sections) do
		rec.frame.Visible = (n == name)
	end
	for _, b in ipairs(navButtons) do
		b.BackgroundColor3 = (b.Name == name) and Color3.fromRGB(38, 44, 66) or Color3.fromRGB(18, 21, 30)
	end
	activeSection = name
end

local function makeNav(name, order)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = UDim2.new(1, -10, 0, 30)
	b.Position = UDim2.new(0, 5, 0, 12 + (order - 1) * 34)
	b.BackgroundColor3 = Color3.fromRGB(18, 21, 30)
	b.BorderSizePixel = 0
	b.Text = name
	b.TextColor3 = TXT
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 11
	b.Parent = sidebar
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
	b.MouseButton1Click:Connect(function() showSection(name) end)
	table.insert(navButtons, b)
	return b
end

-- =========================================================
-- ВИДЖЕТЫ
-- =========================================================
local function setBtnBase(b, color)
	b:SetAttribute("SMAZBase", color)
end

local function makeButton(rec, order, label, onClick, accent)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 28)
	local base = accent or Color3.fromRGB(52, 62, 92)
	b.BackgroundColor3 = base
	setBtnBase(b, base)
	b.BorderSizePixel = 0
	b.Text = label
	b.TextColor3 = Color3.fromRGB(245, 247, 252)
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 12
	b.LayoutOrder = order
	b.Parent = rec.frame
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
	b.MouseButton1Click:Connect(function() pcall(onClick) end)
	b.MouseEnter:Connect(function()
		local c = b:GetAttribute("SMAZBase") or Color3.fromRGB(52, 62, 92)
		TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = c:Lerp(Color3.new(1, 1, 1), 0.15)}):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = b:GetAttribute("SMAZBase") or Color3.fromRGB(52, 62, 92)}):Play()
	end)
	return b
end

local function makeToggle(rec, order, label, getState, setState)
	local function refresh()
		local st = false
		pcall(function() st = (getState() and true) or false end)
		b.BackgroundColor3 = st and OK or DANGER
		setBtnBase(b, st and OK or DANGER)
		b.Text = label .. "      " .. (st and "ON" or "OFF")
	end
	local b = makeButton(rec, order, "", function()
		local st = false
		pcall(function() st = (getState() and true) or false end)
		pcall(setState, not st)
		refresh()
	end)
	refresh()
	table.insert(rec.refreshers, refresh)
	return b, refresh
end

local function makeCycle(rec, order, label, options, getVal, setVal)
	local function refresh()
		local cur = getVal()
		b.Text = label .. " :  " .. tostring(cur) .. "   [▸]"
	end
	local b = makeButton(rec, order, "", function()
		local cur = getVal()
		local idx = nil
		for i, v in ipairs(options) do
			if tostring(v) == tostring(cur) then idx = i end
		end
		idx = ((idx or 0) % #options) + 1
		pcall(setVal, options[idx])
		refresh()
	end)
	refresh()
	table.insert(rec.refreshers, refresh)
	return b, refresh
end

local function parentFrame(p)
	return p.frame or p
end

local function makeSlider(rec, order, label, getVal, setVal, minV, maxV, fmt)
	fmt = fmt or "%.2f"
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 30)
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	row.Parent = parentFrame(rec)

	local lab = Instance.new("TextLabel")
	lab.Size = UDim2.new(0, 104, 1, 0)
	lab.BackgroundTransparency = 1
	lab.Text = label
	lab.TextColor3 = SUB
	lab.Font = Enum.Font.Gotham
	lab.TextSize = 11
	lab.TextXAlignment = Enum.TextXAlignment.Left
	lab.TextWrapped = true
	lab.Parent = row

	local val = Instance.new("TextLabel")
	val.Size = UDim2.new(0, 44, 1, 0)
	val.Position = UDim2.new(1, -44, 0, 0)
	val.BackgroundTransparency = 1
	val.Text = ""
	val.TextColor3 = TXT
	val.Font = Enum.Font.GothamMedium
	val.TextSize = 11
	val.TextXAlignment = Enum.TextXAlignment.Right
	val.Parent = row

	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, -156, 0, 6)
	track.Position = UDim2.new(0, 108, 0, 12)
	track.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
	track.BorderSizePixel = 0
	track.Parent = row
	Instance.new("UICorner", track).CornerRadius = UDim.new(0, 3)

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = ACCENT
	fill.BorderSizePixel = 0
	fill.Parent = track
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 3)

	local handle = Instance.new("TextButton")
	handle.Size = UDim2.new(0, 14, 0, 14)
	handle.BackgroundColor3 = Color3.fromRGB(235, 238, 250)
	handle.BorderSizePixel = 0
	handle.Text = ""
	handle.Parent = track
	Instance.new("UICorner", handle).CornerRadius = UDim.new(0, 7)

	local dragging = false
	local function update(x)
		local abs = track.AbsolutePosition
		local frac = math.clamp((x - abs.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
		setVal(minV + (maxV - minV) * frac)
		refresh()
	end
	local function refresh()
		local v = tonumber(getVal()) or minV
		local frac = math.clamp((v - minV) / math.max(0.0001, maxV - minV), 0, 1)
		fill.Size = UDim2.new(frac, 0, 1, 0)
		handle.Position = UDim2.new(frac, -7, 0.5, -7)
		val.Text = string.format(fmt, v)
	end
	handle.InputBegan:Connect(function(input, gp)
		if gp then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			local x = UIS:GetMouseLocation().X
			update(x)
		end
	end)
	UIS.InputEnded:Connect(function(input, gp)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
	end)
	UIS.InputChanged:Connect(function(input, gp)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			update(input.Position.X)
		end
	end)
	refresh()
	if rec.refreshers then table.insert(rec.refreshers, refresh) end
	return refresh
end

local function makeColorRow(rec, order, label, getColor, setColor)
	local group = Instance.new("Frame")
	group.Size = UDim2.new(1, 0, 0, 0)
	group.AutomaticSize = Enum.AutomaticSize.Y
	group.BackgroundTransparency = 1
	group.LayoutOrder = order
	group.Parent = parentFrame(rec)
	local gl = Instance.new("UIListLayout")
	gl.Padding = UDim.new(0, 0)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = group

	local chipRow = Instance.new("Frame")
	chipRow.Size = UDim2.new(1, 0, 0, 20)
	chipRow.BackgroundTransparency = 1
	chipRow.LayoutOrder = 1
	chipRow.Parent = group

	local chip = Instance.new("Frame")
	chip.Size = UDim2.new(0, 44, 0, 18)
	chip.Position = UDim2.new(0, 0, 0, 1)
	chip.BackgroundColor3 = Color3.new(1, 0, 0)
	chip.BorderSizePixel = 0
	chip.Parent = chipRow
	Instance.new("UICorner", chip).CornerRadius = UDim.new(0, 5)

	local lab = Instance.new("TextLabel")
	lab.Size = UDim2.new(0, 200, 0, 18)
	lab.Position = UDim2.new(0, 50, 0, 1)
	lab.BackgroundTransparency = 1
	lab.Text = label
	lab.TextColor3 = SUB
	lab.Font = Enum.Font.Gotham
	lab.TextSize = 11
	lab.TextXAlignment = Enum.TextXAlignment.Left
	lab.Parent = chipRow

	local r = makeSlider(group, 2, label .. ": R", function() return (getColor() or Color3.new()).R end,
		function(v) setColor(Color3.new(v, (getColor() or Color3.new()).G, (getColor() or Color3.new()).B)) end, 0, 1, "%.3f")
	local g = makeSlider(group, 3, label .. ": G", function() return (getColor() or Color3.new()).G end,
		function(v) setColor(Color3.new((getColor() or Color3.new()).R, v, (getColor() or Color3.new()).B)) end, 0, 1, "%.3f")
	local b = makeSlider(group, 4, label .. ": B", function() return (getColor() or Color3.new()).B end,
		function(v) setColor(Color3.new((getColor() or Color3.new()).R, (getColor() or Color3.new()).G, v)) end, 0, 1, "%.3f")
	local function refresh()
		local c = getColor() or Color3.new()
		chip.BackgroundColor3 = c
		r(); g(); b()
	end
	table.insert(rec.refreshers, refresh)
	refresh()
	return refresh
end

local function makeHeader(rec, order, text)
	local h = Instance.new("Frame")
	h.Size = UDim2.new(1, 0, 0, 22)
	h.BackgroundTransparency = 1
	h.LayoutOrder = order
	h.Parent = parentFrame(rec)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 1, 0)
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = Color3.fromRGB(120, 150, 230)
	l.Font = Enum.Font.GothamBold
	l.TextSize = 11
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = h
	local line = Instance.new("Frame")
	line.Size = UDim2.new(1, 0, 0, 1)
	line.Position = UDim2.new(0, 0, 1, -1)
	line.BackgroundColor3 = Color3.fromRGB(70, 80, 110)
	line.BorderSizePixel = 0
	line.Parent = h
	return h
end

local function makeInfo(rec, order, text)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.BackgroundColor3 = Color3.fromRGB(20, 23, 33)
	l.BorderSizePixel = 0
	l.Text = text
	l.TextColor3 = SUB
	l.Font = Enum.Font.Gotham
	l.TextSize = 10
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.LayoutOrder = order
	l.Parent = rec.frame
	Instance.new("UICorner", l).CornerRadius = UDim.new(0, 6)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, 8); p.PaddingRight = UDim.new(0, 8); p.PaddingTop = UDim.new(0, 4); p.PaddingBottom = UDim.new(0, 4)
	p.Parent = l
	return l
end

-- =========================================================
-- ДОСТУП К Lighting / ЭФФЕКТАМ (безопасно)
-- =========================================================
local function getL(key)
	local ok, v = pcall(function() return Lighting[key] end)
	return ok and v or nil
end
local function setL(key, v)
	pcall(function() Lighting[key] = v end)
end

local function getTech()
	local ok, v = pcall(function() return tostring(Lighting.Technology) end)
	return ok and v or "Legacy"
end
local function setTech(v)
	pcall(function() Lighting.Technology = Enum.Technology[v] end)
end

local function getOrCreate(name, className)
	local e = Lighting:FindFirstChild(name)
	if e and e:IsA(className) then return e end
	if e then pcall(function() e:Destroy() end) end
	return Instance.new(className, Lighting)
end

--==========================================================
-- РАЗДЕЛ: СВЕТ
--==========================================================
local LHT = makeSection("СВЕТ", 1)
makeNav("СВЕТ", 1)
local ord = 1
local function nxt() local v = ord; ord = ord + 1; return v end

makeHeader(LHT, nxt(), "ОСВЕЩЕНИЕ / ВРЕМЯ")
if ATMOS then
	makeSlider(LHT, nxt(), "Яркость (макс.)", function() return ATMOS.get("maxBrightness") or 2.5 end,
		function(v) ATMOS.set("maxBrightness", v) end, 0.3, 10, "%.2f")
	makeToggle(LHT, nxt(), "Цикл день/ночь", function() return ATMOS.get("dayNight") ~= false end,
		function(v) ATMOS.set("dayNight", v) end)
	makeSlider(LHT, nxt(), "Время суток", function() return ATMOS.get("timeOfDay") or 12 end,
		function(v) ATMOS.set("dayNight", false); ATMOS.set("timeOfDay", v) end, 0, 24, "%.1f")
else
	makeSlider(LHT, nxt(), "Яркость", function() return getL("Brightness") or 1 end,
		function(v) setL("Brightness", v) end, 0, 10, "%.2f")
	makeSlider(LHT, nxt(), "Время суток", function() return getL("ClockTime") or 12 end,
		function(v) setL("ClockTime", v) end, 0, 24, "%.1f")
end

makeHeader(LHT, nxt(), "ЭКСПОЗИЦИЯ")
makeSlider(LHT, nxt(), "Экспозиция (EV)", function() return getL("ExposureCompensation") or 0 end,
	function(v) setL("ExposureCompensation", v) end, -5, 5, "%.2f")

makeHeader(LHT, nxt(), "ТЕНИ")
makeToggle(LHT, nxt(), "Глобальные тени", function() return getL("GlobalShadows") end,
	function(v) setL("GlobalShadows", v) end)
makeSlider(LHT, nxt(), "Мягкость теней", function() return getL("ShadowSoftness") or 0 end,
	function(v) setL("ShadowSoftness", v) end, 0, 1, "%.2f")
makeSlider(LHT, nxt(), "Интенсивность тени", function() return getL("ShadowIntensity") or 0 end,
	function(v) setL("ShadowIntensity", v) end, 0, 1, "%.2f")

makeHeader(LHT, nxt(), "ОКРУЖЕНИЕ / ТЕХНОЛОГИЯ")
makeSlider(LHT, nxt(), "Спекуляр", function() return getL("SpecularScale") or 1 end,
	function(v) setL("SpecularScale", v) end, 0, 1, "%.2f")
makeSlider(LHT, nxt(), "Диффузия окруж.", function() return getL("EnvironmentDiffuseScale") or 1 end,
	function(v) setL("EnvironmentDiffuseScale", v) end, 0, 1, "%.2f")
makeSlider(LHT, nxt(), "Спекуляр окруж.", function() return getL("EnvironmentSpecularScale") or 1 end,
	function(v) setL("EnvironmentSpecularScale", v) end, 0, 1, "%.2f")
makeSlider(LHT, nxt(), "Широта (GeoL)", function() return getL("GeographicLatitude") or 0 end,
	function(v) setL("GeographicLatitude", v) end, -90, 90, "%.0f")
makeCycle(LHT, nxt(), "Технология", {"Legacy","Voxel","ShadowMap","Compatibility","Future","Video"}, getTech, setTech)

makeHeader(LHT, nxt(), "ТУМАН")
makeToggle(LHT, nxt(), "Туман", function() return getL("FogEnabled") end,
	function(v) setL("FogEnabled", v) end)
makeSlider(LHT, nxt(), "Fog Start", function() return getL("FogStart") or 0 end,
	function(v) setL("FogStart", v) end, 0, 100000, "%.0f")
makeSlider(LHT, nxt(), "Fog End", function() return getL("FogEnd") or 1024 end,
	function(v) setL("FogEnd", v) end, 0, 100000, "%.0f")
makeColorRow(LHT, nxt(), "Цвет тумана", function() return getL("FogColor") or Color3.new(0.75,0.78,0.8) end,
	function(c) setL("FogColor", c) end)
makeToggle(LHT, nxt(), "Туман на прозрачных материалах", function() return getL("FogTransparencyMaterials") == true end,
	function(v) setL("FogTransparencyMaterials", v) end)

makeHeader(LHT, nxt(), "ОКРУЖАЮЩИЙ СВЕТ (AMBIENT)")
makeColorRow(LHT, nxt(), "Ambient", function() return getL("Ambient") or Color3.new(0.1,0.1,0.1) end,
	function(c) setL("Ambient", c) end)
makeColorRow(LHT, nxt(), "OutdoorAmbient", function() return getL("OutdoorAmbient") or Color3.new(0,0,0) end,
	function(c) setL("OutdoorAmbient", c) end)
makeColorRow(LHT, nxt(), "AmbientSky", function() return getL("AmbientSkyColor") or Color3.new(0.4,0.4,0.4) end,
	function(c) setL("AmbientSkyColor", c) end)
makeColorRow(LHT, nxt(), "IndoorAmbient", function() return getL("IndoorAmbient") or Color3.new(0,0,0) end,
	function(c) setL("IndoorAmbient", c) end)

makeHeader(LHT, nxt(), "АТМОСФЕРА (ОБЪЕКТ ROBLOX)")
local function atmosphereObj()
	return Lighting:FindFirstChildOfClass("Atmosphere")
end
makeSlider(LHT, nxt(), "Плотность", function()
	local a = atmosphereObj(); local ok, v = pcall(function() return ATMOS and ATMOS.get("atmDensity") or (a and a.Density or 0.3) end)
	return ok and v or 0.3
end, function(v)
	if ATMOS then ATMOS.set("atmDensity", v) else local a = atmosphereObj(); if a then pcall(function() a.Density = v end) end end
end, 0, 1, "%.2f")
makeSlider(LHT, nxt(), "Дымка (Haze)", function()
	local a = atmosphereObj(); local ok, v = pcall(function() return ATMOS and ATMOS.get("atmHaze") or (a and a.Haze or 1.4) end)
	return ok and v or 1.4
end, function(v)
	if ATMOS then ATMOS.set("atmHaze", v) else local a = atmosphereObj(); if a then pcall(function() a.Haze = v end) end end
end, 0, 4, "%.2f")
makeSlider(LHT, nxt(), "Offset", function() local a = atmosphereObj(); local ok, v = pcall(function() return a and a.Offset or 0 end) return ok and v or 0 end,
	function(v) local a = atmosphereObj(); if a then pcall(function() a.Offset = v end) end end, -1, 1, "%.2f")
makeSlider(LHT, nxt(), "Glare", function() local a = atmosphereObj(); local ok, v = pcall(function() return a and a.Glare or 0 end) return ok and v or 0 end,
	function(v) local a = atmosphereObj(); if a then pcall(function() a.Glare = v end) end end, 0, 1, "%.2f")
makeSlider(LHT, nxt(), "Distortion", function() local a = atmosphereObj(); local ok, v = pcall(function() return a and a.DistortionScale or 0 end) return ok and v or 0 end,
	function(v) local a = atmosphereObj(); if a then pcall(function() a.DistortionScale = v end) end end, 0, 10, "%.2f")
makeInfo(LHT, nxt(), "Atmosphere (объект Roblox): Density/Haze — через слой Atmosphere если он загружен, остальное — напрямую в объект.")

--==========================================================
-- РАЗДЕЛ: ПОСТ FX (использовать Effect-объекты Roblox)
--==========================================================
local FX = makeSection("ПОСТ FX", 2)
makeNav("ПОСТ FX", 2)

local ord = 0
local function nxt() ord = ord + 1; return ord end

makeHeader(FX, nxt(), "BLOOM / СВЕЧЕНИЕ")
local bloomFx = getOrCreate("__PanelBloom", "BloomEffect")
makeToggle(FX, nxt(), "Bloom", function()
	if ATMOS then return ATMOS.get("bloom") ~= false end
	return bloomFx.Enabled == true
end, function(v)
	if ATMOS then ATMOS.set("bloom", v) else pcall(function() bloomFx.Enabled = v end) end
end)
makeSlider(FX, nxt(), "Интенсивность", function()
	if ATMOS and ATMOS.get("bloomIntensity") and ATMOS.get("bloomIntensity") > 0 then return ATMOS.get("bloomIntensity") end
	local ok, v = pcall(function() return bloomFx.Intensity end); return ok and v or 1
end, function(v)
	if ATMOS then ATMOS.set("bloomIntensity", v) end
	pcall(function() bloomFx.Intensity = v end)
end, 0, 5, "%.2f")
makeSlider(FX, nxt(), "Размер", function() local ok, v = pcall(function() return bloomFx.Size end) return ok and v or 20 end,
	function(v) pcall(function() bloomFx.Size = v end) end, 0, 100, "%.0f")
makeSlider(FX, nxt(), "Порог (Threshold)", function() local ok, v = pcall(function() return bloomFx.Threshold end) return ok and v or 1 end,
	function(v) pcall(function() bloomFx.Threshold = v end) end, 0, 3, "%.2f")

makeHeader(FX, nxt(), "BLUR / РАЗМЫТИЕ")
local myBlurFx = nil
local function panelBlurFx()
	if ATMOS then return nil end
	myBlurFx = myBlurFx or getOrCreate("__PanelBlur", "BlurEffect")
	return myBlurFx
end
local sBlur = {
	on     = ATMOS and ATMOS.get("blur") == true or false,
	mode   = ATMOS and ATMOS.getBlurMode() or "global",
	size   = (ATMOS and ATMOS.get("blurAmt")) or 12,
	maxDist= (ATMOS and ATMOS.get("blurMaxDist")) or 250,
}
makeToggle(FX, nxt(), "Blur", function()
	if ATMOS then return ATMOS.get("blur") == true end
	return sBlur.on
end, function(v)
	sBlur.on = v
	if ATMOS then ATMOS.setBlur(v)
	else
		local fx = panelBlurFx()
		if fx then pcall(function() fx.Enabled = v end) end
	end
end)
makeSlider(FX, nxt(), "Сила (Size)", function()
	if ATMOS then return ATMOS.get("blurAmt") or sBlur.size end
	return sBlur.size
end, function(v)
	sBlur.size = v
	if ATMOS then ATMOS.set("blurAmt", v) end
	if not ATMOS then
		local fx = panelBlurFx()
		if fx and sBlur.on and sBlur.mode == "global" then pcall(function() fx.Size = v end) end
	end
end, 0, 60, "%.0f")
makeCycle(FX, nxt(), "Режим блюра", {"global", "distance"}, function()
	if ATMOS then return ATMOS.getBlurMode() or "global" end
	return sBlur.mode
end, function(v)
	sBlur.mode = v
	if ATMOS then ATMOS.setBlurMode(v) end
end)
makeSlider(FX, nxt(), "Макс. дистанция", function()
	if ATMOS then return ATMOS.get("blurMaxDist") or sBlur.maxDist end
	return sBlur.maxDist
end, function(v)
	sBlur.maxDist = v
	if ATMOS then ATMOS.set("blurMaxDist", v) end
end, 20, 1000, "%.0f")

-- Автономный distance-блюр (без Atmosphere)
if not ATMOS then
	task.spawn(function()
		RunService.RenderStepped:Connect(function()
			local fx = panelBlurFx()
			if not fx or not fx.Enabled then return end
			pcall(function() fx.Enabled = sBlur.on end)
			if sBlur.mode ~= "distance" then
				pcall(function() fx.Size = sBlur.size end)
				return
			end
			local cam = workspace.CurrentCamera
			local prm = RaycastParams.new()
			prm.FilterType = Enum.RaycastFilterType.Exclude
			prm.FilterDescendantsInstances = { cam }
			local hit = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * sBlur.maxDist, prm)
			local d = hit and hit.Distance or sBlur.maxDist
			pcall(function() fx.Size = math.clamp(d / math.max(1, sBlur.maxDist), 0, 1) * sBlur.size end)
		end)
	end)
end

makeHeader(FX, nxt(), "ЗЕРНО / ШУМ (GRAIN)")
makeToggle(FX, nxt(), "Зерно", function() return uiFx.grain.on end, function(v) uiFx.grain.on = v end)
makeSlider(FX, nxt(), "Интенсивность", function() return uiFx.grain.amt end,
	function(v) uiFx.grain.amt = v end, 0, 1, "%.2f")

makeHeader(FX, nxt(), "ВИНЬЕТКА")
makeToggle(FX, nxt(), "Виньетка", function() return uiFx.vig.on end, function(v) uiFx.vig.on = v end)
makeSlider(FX, nxt(), "Сила", function() return uiFx.vig.amt end,
	function(v) uiFx.vig.amt = v end, 0, 1, "%.2f")
makeColorRow(FX, nxt(), "Цвет", function() return uiFx.vig.color end,
	function(c) uiFx.vig.color = c end)

makeHeader(FX, nxt(), "ЦВЕТОКОРРЕКЦИЯ")
local ccFx = getOrCreate("__PanelCC", "ColorCorrectionEffect")
makeToggle(FX, nxt(), "ColorCorrection", function() return ccFx.Enabled end,
	function(v) pcall(function() ccFx.Enabled = v end) end)
makeSlider(FX, nxt(), "Яркость", function() local ok, v = pcall(function() return ccFx.Brightness end) return ok and v or 0 end,
	function(v) pcall(function() ccFx.Brightness = v end) end, -1, 1, "%.2f")
makeSlider(FX, nxt(), "Контраст", function() local ok, v = pcall(function() return ccFx.Contrast end) return ok and v or 0 end,
	function(v) pcall(function() ccFx.Contrast = v end) end, -1, 1, "%.2f")
makeSlider(FX, nxt(), "Насыщенность", function() local ok, v = pcall(function() return ccFx.Saturation end) return ok and v or 0 end,
	function(v) pcall(function() ccFx.Saturation = v end) end, -2, 2, "%.2f")
makeColorRow(FX, nxt(), "Тонировка (Tint)", function() local ok, v = pcall(function() return ccFx.TintColor end) return ok and v or Color3.new(1,1,1) end,
	function(c) pcall(function() ccFx.TintColor = c end) end)

makeHeader(FX, nxt(), "СОЛНЕЧНЫЕ ЛУЧИ (SunRays)")
local sunFx = getOrCreate("__PanelSunRays", "SunRaysEffect")
makeToggle(FX, nxt(), "SunRays", function()
	if ATMOS then return ATMOS.get("rays") ~= false end
	return sunFx.Enabled
end, function(v)
	if ATMOS then ATMOS.set("rays", v) else pcall(function() sunFx.Enabled = v end) end
end)
makeSlider(FX, nxt(), "Интенсивность", function()
	if ATMOS then
		local ri = ATMOS.get("raysIntensity") or 0
		return ri > 0 and ri or 0.4
	end
	local ok, v = pcall(function() return sunFx.Intensity end); return ok and v or 0.2
end, function(v)
	pcall(function() sunFx.Intensity = v end)
	if ATMOS then ATMOS.set("raysIntensity", v) end
end, 0, 2, "%.2f")
makeSlider(FX, nxt(), "Spread", function()
	if ATMOS then
		local rs = ATMOS.get("raysSpread") or 0
		return rs > 0 and rs or 0.9
	end
	local ok, v = pcall(function() return sunFx.Spread end); return ok and v or 1
end, function(v)
	pcall(function() sunFx.Spread = v end)
	if ATMOS then ATMOS.set("raysSpread", v) end
end, 0, 3, "%.2f")

makeHeader(FX, nxt(), "ГЛУБИНА РЕЗКОСТИ (DoF)")
local dofFx = getOrCreate("__PanelDoF", "DepthOfFieldEffect")
makeToggle(FX, nxt(), "DepthOfField", function() return dofFx.Enabled end, function(v) pcall(function() dofFx.Enabled = v end) end)
makeSlider(FX, nxt(), "Фокус (FocusDistance)", function() local ok, v = pcall(function() return dofFx.FocusDistance end) return ok and v or 512 end,
	function(v) pcall(function() dofFx.FocusDistance = v end) end, 0, 10000, "%.0f")
makeSlider(FX, nxt(), "Зона фокуса", function() local ok, v = pcall(function() return dofFx.InFocusRadius end) return ok and v or 256 end,
	function(v) pcall(function() dofFx.InFocusRadius = v end) end, 0, 3000, "%.0f")
makeSlider(FX, nxt(), "Дальний блюр", function() local ok, v = pcall(function() return dofFx.FarIntensity end) return ok and v or 0.3 end,
	function(v) pcall(function() dofFx.FarIntensity = v end) end, 0, 1, "%.2f")
makeSlider(FX, nxt(), "Ближний блюр", function() local ok, v = pcall(function() return dofFx.NearIntensity end) return ok and v or 0 end,
	function(v) pcall(function() dofFx.NearIntensity = v end) end, 0, 1, "%.2f")
makeToggle(FX, nxt(), "Автофокус (по прицелу)", function() return uiFx.dof.auto end, function(v) uiFx.dof.auto = v end)

--==========================================================
-- РАЗДЕЛ: КАМЕРА
--==========================================================
local CA = makeSection("КАМЕРА", 3)
makeNav("КАМЕРА", 3)
local ord = 1
local function nxt() local v = ord; ord = ord + 1; return v end
local camBase = workspace.CurrentCamera
local camBaseFov = pcall(function() return camBase and camBase.FieldOfView or 70 end) and camBase and camBase.FieldOfView or 70
camFov.manual = camBaseFov

makeHeader(CA, nxt(), "ПРОЕКЦИЯ")
makeSlider(CA, nxt(), "FOV (обзор)", function()
	local c = workspace.CurrentCamera
	local ok, v = pcall(function() return c and c.FieldOfView or camFov.manual end)
	return ok and v or camFov.manual
end, function(v)
	camFov.manual = v
	local c = workspace.CurrentCamera
	if c and not camBreath.on then pcall(function() c.FieldOfView = v end) end
end, 30, 120, "%.0f")
makeButton(CA, nxt(), "Сброс FOV (" .. math.floor(camBaseFov) .. "°)", function()
	camFov.manual = camBaseFov
	local c = workspace.CurrentCamera
	if c and not camBreath.on then pcall(function() c.FieldOfView = camBaseFov end) end
end)
makeHeader(CA, nxt(), "ПОВЕДЕНИЕ / ЖИВОСТЬ")
makeToggle(CA, nxt(), "Дышащая перспектива", function() return camBreath.on end, function(v)
	camBreath.on = v
	if not v then
		local c = workspace.CurrentCamera
		if c then pcall(function() c.FieldOfView = camFov.manual end) end
	end
end)
makeSlider(CA, nxt(), "Амплитуда", function() return camBreath.amp end,
	function(v) camBreath.amp = v end, 0, 8, "%.2f")
makeSlider(CA, nxt(), "Скорость", function() return camBreath.speed end,
	function(v) camBreath.speed = v end, 0.1, 5, "%.2f")
makeInfo(CA, nxt(), "FOV и «дыхание» применяются к общей камере. Фрикам атмосферы имеет свою камеру.")

--==========================================================
-- РАЗДЕЛ: АТМОСФЕРА (слой SMAZ_ATMOS)
--==========================================================
local A = makeSection("АТМОС", 4)
makeNav("АТМОС", 4)
if ATMOS then
	makeToggle(A, 1, "Облака", function() return ATMOS.get("clouds") ~= false end, function(v) ATMOS.set("clouds", v) end)
	makeSlider(A, 2, "Покрытие облаков", function() return ATMOS.get("cloudCover") or 0.6 end,
		function(v) ATMOS.set("cloudCover", v) end, 0, 1, "%.2f")
	makeSlider(A, 3, "Плотность облаков", function() return ATMOS.get("cloudDensity") or 0.55 end,
		function(v) ATMOS.set("cloudDensity", v) end, 0, 1, "%.2f")
	makeSlider(A, 4, "Скорость облаков", function() return ATMOS.get("cloudSpeed") or 0.5 end,
		function(v) ATMOS.set("cloudSpeed", v) end, 0, 2, "%.2f")
	makeSlider(A, 5, "Цвет облаков", function() return ATMOS.get("cloudColor") or 0.9 end,
		function(v) ATMOS.set("cloudColor", v) end, 0, 1, "%.2f")
	makeToggle(A, 6, "Анимация облаков", function() return ATMOS.get("cloudAnimate") ~= false end, function(v) ATMOS.set("cloudAnimate", v) end)
	makeSlider(A, 7, "Размер солнца", function() return ATMOS.get("sunSize") or 350 end,
		function(v) ATMOS.set("sunSize", v) end, 80, 900, "%.0f")
	makeSlider(A, 8, "Яркость солнца", function() return ATMOS.get("sunBright") or 2 end,
		function(v) ATMOS.set("sunBright", v) end, 0, 6, "%.2f")
	makeSlider(A, 9, "Размер луны", function() return ATMOS.get("moonSize") or 450 end,
		function(v) ATMOS.set("moonSize", v) end, 80, 900, "%.0f")
	makeSlider(A, 10, "Яркость луны", function() return ATMOS.get("moonBright") or 1 end,
		function(v) ATMOS.set("moonBright", v) end, 0, 6, "%.2f")
	makeToggle(A, 11, "Резкость (CC)", function() return ATMOS.get("sharpen") == true end,
		function(v) ATMOS.set("sharpen", v) end)
	makeSlider(A, 12, "Сила резкости", function() return ATMOS.get("sharpenAmt") or 0.2 end,
		function(v) ATMOS.set("sharpenAmt", v) end, 0, 1, "%.2f")
	makeToggle(A, 13, "Фрикам (Shift+P)", function() return ATMOS.isFreecam() end,
		function(v) ATMOS.setFreecam(v) end)
	makeSlider(A, 14, "Скорость фрикама", function() return ATMOS.get("freeCamSpeed") or 140 end,
		function(v) ATMOS.set("freeCamSpeed", v) end, 10, 500, "%.0f")
	makeSlider(A, 15, "Чувств. фрикама", function() return ATMOS.get("sens") or 1 end,
		function(v) ATMOS.set("sens", v) end, 0.1, 4, "%.2f")
	makeHeader(A, 16, "ЦИКЛ ДЕНЬ/НОЧЬ")
	makeSlider(A, 17, "Длит. цикла (сек)", function() return ATMOS.get("dayLength") or 240 end,
		function(v) ATMOS.set("dayLength", v) end, 60, 3600, "%.0f")
	makeSlider(A, 18, "Диапазон солнца", function() return ATMOS.get("sunRange") or 60 end,
		function(v) ATMOS.set("sunRange", v) end, 10, 200, "%.0f")
else
	makeInfo(A, 1, "Слой Atmosphere не найден. Пустой клиент: панель работает в автономном режиме.")
end

--==========================================================
-- РАЗДЕЛ: ПОГОДА
--==========================================================
local W = makeSection("ПОГОДА", 5)
makeNav("ПОГОДА", 5)
if ATMOS then
	makeButton(W, 1, "☀  Ясно", function() ATMOS.weather.set("none") end)
	makeButton(W, 2, "🌧  Дождь", function() ATMOS.weather.set("rain") end)
	makeButton(W, 3, "❄  Снег", function() ATMOS.weather.set("snow") end)
	makeButton(W, 4, "🌨  Град", function() ATMOS.weather.set("hail") end)
	makeSlider(W, 5, "Интенсивность", function() return ATMOS.get("weatherIntensity") or 0.6 end,
		function(v) ATMOS.weather.setIntensity(v) end, 0, 1, "%.2f")
	makeInfo(W, 6, "Сейчас: " .. tostring(ATMOS.get("weather") or "none"))
	makeHeader(W, 7, "АВТО-ЦИКЛ ПОГОДЫ")
	makeToggle(W, 8, "Авто-цикл", function() return wCyc.on end, function(v) wCyc.on = v end)
	makeSlider(W, 9, "Интервал (сек)", function() return wCyc.every end,
		function(v) wCyc.every = math.max(3, v) end, 3, 120, "%.0f")
else
	makeInfo(W, 1, "Погода управляется через слой Atmosphere.")
end

--==========================================================
-- РАЗДЕЛ: ЭФФЕКТЫ (модули SMAZ)
--==========================================================
local M = makeSection("ЭФФЕКТЫ", 6)
makeNav("ЭФФЕКТЫ", 6)

local order = 1
local function nextOrder() local o = order; order = order + 1; return o end

if LG then
	makeInfo(M, nextOrder(), "МОЛНИИ")
	makeButton(M, nextOrder(), "⚡ Ударить сейчас", function() pcall(LG.strike) end, ACCENT)
	makeToggle(M, nextOrder(), "Авто-молнии", LG.isAuto, function(v) pcall(LG.setAuto, v) end)
else
	makeInfo(M, nextOrder(), "Молнии недоступны")
end

if TN then
	makeInfo(M, nextOrder(), "ТОРНАДО")
	makeButton(M, nextOrder(), "🌪 Создать рядом", function() pcall(TN.spawnNear) end, ACCENT)
	makeButton(M, nextOrder(), "🌪 Случайно", function() pcall(TN.spawnRandom) end)
	makeButton(M, nextOrder(), "✕ Убить все", function() pcall(TN.killAll) end, DANGER)
	do
		local efBtn = makeButton(M, nextOrder(), "Сила EF: " .. tostring(pcall(function() return TN.getEF() end) and TN.getEF() or 0) .. "  [цикл]", function()
			pcall(function() TN.setEF((TN.getEF() + 1) % 6) end)
		end)
		local _, tr = makeToggle(M, nextOrder(), "Авто-спавн", TN.isAutoSpawn, function(v) pcall(TN.setAutoSpawn, v) end)
		table.insert(M.refreshers, function()
			local ok, n = pcall(TN.count)
			efBtn.Text = "Сила EF: " .. tostring(pcall(function() return TN.getEF() end) and TN.getEF() or 0) .. "  [цикл]"
		end)
	end
else
	makeInfo(M, nextOrder(), "Торнадо недоступно")
end

if RN then
	makeInfo(M, nextOrder(), "ДОЖДЬ (модуль)")
	makeToggle(M, nextOrder(), "Дождь", RN.isEnabled, function(v) pcall(RN.setEnabled, v) end)
	makeToggle(M, nextOrder(), "3D капли", RN.isRain3D, function(v) pcall(RN.setRain3D, v) end)
	makeToggle(M, nextOrder(), "Капли на экране", RN.isScreenDrops, function(v) pcall(RN.setScreenDrops, v) end)
else
	makeInfo(M, nextOrder(), "Дождь (модуль) недоступен")
end

if RF then
	makeInfo(M, nextOrder(), "ОТРАЖЕНИЯ")
	makeToggle(M, nextOrder(), "Отражения", RF.isEnabled, function(v) pcall(RF.setEnabled, v) end)
	makeToggle(M, nextOrder(), "Клонировать персонажа", RF.isCloneCharacter, function(v) pcall(RF.setCloneCharacter, v) end)
	makeButton(M, nextOrder(), "Пересобрать клоны", function() pcall(RF.rebuild) end)
	makeSlider(M, nextOrder(), "Радиус", RF.getRadius, function(v) pcall(RF.setRadius, v) end, 8, 120, "%.0f")
	makeSlider(M, nextOrder(), "Прозрачность (x100)", function()
		local ok, v = pcall(function() return RF.getBaseTransparency() end)
		return ok and v and math.floor(v * 100) or 0
	end, function(v) pcall(RF.setBaseTransparency, v / 100) end, 0, 90, "%.0f")
else
	makeInfo(M, nextOrder(), "Отражения недоступны")
end

--==========================================================
-- РАЗДЕЛ: ПРЕСЕТЫ
--==========================================================
local P = makeSection("ПРЕСЕТЫ", 7)
makeNav("ПРЕСЕТЫ", 7)
if PR then
	local list = pcall(function() return PR.list() end) and PR.list() or {}
	local o = 1
	for i, name in ipairs(list) do
		do
			local pretty = pcall(function() return PR.pretty(name) end) and PR.pretty(name) or name
			makeButton(P, o, pretty, function()
				pcall(function() PR.apply(name) end)
			end, (i % 2 == 0) and Color3.fromRGB(52, 62, 92) or Color3.fromRGB(60, 50, 90))
		end
		o = o + 1
	end
	makeButton(P, o, "⏮ Сброс к нейтральному", function() pcall(function() PR.reset() end) end, DANGER)
	makeButton(P, o + 1, "Современный рендер", function() pcall(function() PR.futureLighting() end) end, ACCENT)
else
	makeInfo(P, 1, "Пресеты недоступны")
end

--==========================================================
-- РАЗДЕЛ: ИНФО
--==========================================================
local I = makeSection("ИНФО", 8)
makeNav("ИНФО", 8)
makeInfo(I, 1, "ОСНОВНЫЕ ХОТКЕИ")
makeInfo(I, 2, "Shift+P — фрикам (атмосфера)")
makeInfo(I, 3, "X — скрыть GUI атмосферы")
makeInfo(I, 4, "RightShift — панель атмосферы")
makeInfo(I, 5, "RightControl — показать/скрыть панель")
makeInfo(I, 6, "Все слайдеры и тумблеры пишут в Lighting и Пост-эффекты напрямую. Поля адаптируются под слой Atmosphere, если он загружен.")
makeInfo(I, 7, "Режим блюра: global — равномерный, distance — зависит от дистанции до препятствия по лучу камеры.")
makeInfo(I, 8, "Вкладки: СВЕТ, ПОСТ FX, КАМЕРА, АТМОС (если слой загружен), ПОГОДА, ЭФФЕКТЫ, ПРЕСЕТЫ.")

--==========================================================
-- ДВИЖОК UI-ЭФФЕКТОВ: зерно, виньетка, автофокус DoF,
-- «дыхание» камеры, авто-цикл погоды
--==========================================================
local grainGui = Instance.new("ScreenGui")
grainGui.Name = "SMAZ_Grain"
grainGui.ResetOnSpawn = false
grainGui.IgnoreGuiInset = true
grainGui.DisplayOrder = 902
grainGui.Parent = pgui
local grainHolder = Instance.new("Frame")
grainHolder.Size = UDim2.new(1, 0, 1, 0)
grainHolder.BackgroundTransparency = 1
grainHolder.BorderSizePixel = 0
grainHolder.Parent = grainGui
local grainDots = {}
local GRAIN_GRID = 8
for _ = 1, GRAIN_GRID * GRAIN_GRID do
	local d = Instance.new("TextLabel")
	d.BackgroundTransparency = 1
	d.BorderSizePixel = 0
	d.Size = UDim2.new(0, 3, 0, 3)
	d.AnchorPoint = Vector2.new(0.5, 0.5)
	d.Text = "+"
	d.Font = Enum.Font.GothamBold
	d.TextSize = 7
	d.TextColor3 = Color3.new(1, 1, 1)
	d.TextTransparency = 1
	d.Parent = grainHolder
	table.insert(grainDots, d)
end
grainGui.Enabled = false

local vigGui = Instance.new("ScreenGui")
vigGui.Name = "SMAZ_Vignette"
vigGui.ResetOnSpawn = false
vigGui.IgnoreGuiInset = true
vigGui.DisplayOrder = 901
vigGui.Parent = pgui
local vigStrips = {}
local function vigStrip(size, pos, anchor, rotation, outerAtStart)
	local f = Instance.new("Frame")
	f.Size = size
	f.Position = pos
	f.AnchorPoint = anchor
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Parent = vigGui
	local g = Instance.new("UIGradient")
	g.Rotation = rotation
	g.Parent = f
	table.insert(vigStrips, { frame = f, grad = g, outerAtStart = outerAtStart })
end
vigStrip(UDim2.new(1, 0, 0, 0.5), UDim2.new(0, 0, 0, 0), Vector2.new(0, 0), 0, true)
vigStrip(UDim2.new(1, 0, 0, 0.5), UDim2.new(0, 0, 1, 0), Vector2.new(0, 1), 0, false)
vigStrip(UDim2.new(0, 0.5, 1, 0), UDim2.new(0, 0, 0, 0), Vector2.new(0, 0), 90, true)
vigStrip(UDim2.new(0, 0.5, 1, 0), UDim2.new(1, 0, 0, 0), Vector2.new(1, 0), 90, false)

local function vigApply()
	if uiFx.vig.on and uiFx.vig.amt > 0 then
		vigGui.Enabled = true
		local outer = math.clamp(1 - uiFx.vig.amt, 0, 1)
		for _, s in ipairs(vigStrips) do
			s.frame.BackgroundColor3 = uiFx.vig.color
			if s.outerAtStart then
				s.grad.Transparency = NumberSequence.new(outer, 1)
			else
				s.grad.Transparency = NumberSequence.new(1, outer)
			end
		end
	else
		vigGui.Enabled = false
	end
end
vigApply()

local weatherSeq = { "none", "rain", "snow", "hail" }
local function weatherCycle()
	local cur = ATMOS and ATMOS.get("weather") or "none"
	local idx = 1
	for i, w in ipairs(weatherSeq) do
		if w == cur then idx = i end
	end
	local nx = weatherSeq[(idx % #weatherSeq) + 1]
	if ATMOS then pcall(function() ATMOS.weather.set(nx) end) end
end

RunService.RenderStepped:Connect(function()
	if uiFx.grain.on and uiFx.grain.amt > 0 then
		grainGui.Enabled = true
		local i = 1
		for y = 1, GRAIN_GRID do
			for x = 1, GRAIN_GRID do
				local d = grainDots[i]
				i = i + 1
				d.Position = UDim2.new((x - 0.5) / GRAIN_GRID, math.random(-math.floor((GRAIN_GRID - x) * 1.6), math.floor(x * 1.6)), (y - 0.5) / GRAIN_GRID, math.random(-math.floor((GRAIN_GRID - y) * 1.6), math.floor(y * 1.6)))
				d.TextTransparency = 1 - math.random() * math.clamp(uiFx.grain.amt, 0, 1) * 0.9
			end
		end
	else
		grainGui.Enabled = false
	end
	vigApply()
	if uiFx.dof.auto then
		local cam = workspace.CurrentCamera
		if dofFx and dofFx.Enabled and cam then
			local prm = RaycastParams.new()
			prm.FilterType = Enum.RaycastFilterType.Exclude
			prm.FilterDescendantsInstances = { cam }
			local hit = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * 600, prm)
			pcall(function() dofFx.FocusDistance = hit and hit.Distance or 600 end)
		end
	end
	if camBreath.on then
		local cam = workspace.CurrentCamera
		if cam then
			pcall(function() cam.FieldOfView = camFov.manual + camBreath.amp * math.sin(tick() * camBreath.speed) end)
		end
	end
end)

task.spawn(function()
	local acc = 0
	while gui and gui.Parent do
		task.wait(1)
		if wCyc.on and ATMOS then
			acc = acc + 1
			if acc >= wCyc.every then
				acc = 0
				pcall(weatherCycle)
			end
		else
			acc = 0
		end
	end
end)

--==========================================================
-- ПЕРВЫЙ РАЗДЕЛ + ОБНОВЛЕНИЕ
--==========================================================
showSection("СВЕТ")

task.spawn(function()
	while gui and gui.Parent do
		for name, rec in pairs(sections) do
			if rec.frame.Visible then
				for _, fn in ipairs(rec.refreshers) do
					pcall(fn)
				end
			end
		end
		task.wait(0.4)
	end
end)

print("[SMAZ Studio v5] Panel loaded" .. (ATMOS and " (atmos API)" or " (standalone)"))