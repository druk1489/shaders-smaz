-- Control Panel v2 - unified GUI for all SMAZ modules incl. reflections

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local pgui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 5)
if not pgui then return end

local old = pgui:FindFirstChild("SMAZ_ControlPanel")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "SMAZ_ControlPanel"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 500
gui.Parent = pgui

local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.new(0, 260, 0, 540)
main.Position = UDim2.new(1, -280, 0, 60)
main.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
main.BackgroundTransparency = 0.05
main.BorderSizePixel = 0; main.Active = true; main.Draggable = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(80, 90, 120); stroke.Thickness = 1; stroke.Parent = main

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 32); titleBar.BackgroundColor3 = Color3.fromRGB(30, 34, 48); titleBar.BorderSizePixel = 0
titleBar.Parent = main
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -70, 1, 0); title.Position = UDim2.new(0, 12, 0, 0); title.BackgroundTransparency = 1
title.Text = "SMAZ v12  Control Panel"; title.TextColor3 = Color3.fromRGB(220, 225, 245)
title.Font = Enum.Font.GothamBold; title.TextSize = 13; title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = titleBar

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 28, 0, 22); minBtn.Position = UDim2.new(1, -34, 0, 5)
minBtn.BackgroundColor3 = Color3.fromRGB(50, 55, 70); minBtn.BorderSizePixel = 0; minBtn.Text = "_"
minBtn.TextColor3 = Color3.fromRGB(230, 230, 245); minBtn.Font = Enum.Font.GothamBold; minBtn.TextSize = 14
minBtn.Parent = titleBar
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 4)

local reopenBtn = Instance.new("TextButton")
reopenBtn.Size = UDim2.new(0, 90, 0, 28); reopenBtn.Position = UDim2.new(1, -110, 0, 60)
reopenBtn.BackgroundColor3 = Color3.fromRGB(35, 40, 55); reopenBtn.BorderSizePixel = 0
reopenBtn.Text = "SMAZ v12"; reopenBtn.TextColor3 = Color3.fromRGB(220, 225, 245)
reopenBtn.Font = Enum.Font.GothamBold; reopenBtn.TextSize = 12; reopenBtn.Visible = false; reopenBtn.Parent = gui
Instance.new("UICorner", reopenBtn).CornerRadius = UDim.new(0, 6)

minBtn.MouseButton1Click:Connect(function() main.Visible = false; reopenBtn.Visible = true end)
reopenBtn.MouseButton1Click:Connect(function() main.Visible = true; reopenBtn.Visible = false end)

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -12, 1, -40); scroll.Position = UDim2.new(0, 6, 0, 36)
scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4; scroll.ScrollBarImageColor3 = Color3.fromRGB(80, 90, 120)
scroll.CanvasSize = UDim2.new(0, 0, 0, 900); scroll.Parent = main
local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 8); listLayout.SortOrder = Enum.SortOrder.LayoutOrder; listLayout.Parent = scroll
listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	scroll.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 20)
end)

local function makeSection(name, order)
	local s = Instance.new("Frame"); s.Name = name; s.LayoutOrder = order
	s.Size = UDim2.new(1, -6, 0, 0); s.AutomaticSize = Enum.AutomaticSize.Y
	s.BackgroundColor3 = Color3.fromRGB(28, 30, 42); s.BorderSizePixel = 0; s.Parent = scroll
	Instance.new("UICorner", s).CornerRadius = UDim.new(0, 6)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6); pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 8); pad.PaddingRight = UDim.new(0, 8); pad.Parent = s
	local l = Instance.new("UIListLayout"); l.Padding = UDim.new(0, 4); l.SortOrder = Enum.SortOrder.LayoutOrder; l.Parent = s
	local h = Instance.new("TextLabel")
	h.Size = UDim2.new(1, 0, 0, 20); h.BackgroundTransparency = 1
	h.Text = name; h.TextColor3 = Color3.fromRGB(140, 200, 255)
	h.Font = Enum.Font.GothamBold; h.TextSize = 12; h.TextXAlignment = Enum.TextXAlignment.Left
	h.LayoutOrder = 0; h.Parent = s
	return s
end

local function makeButton(parent, label, order, onClick)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 26); b.BackgroundColor3 = Color3.fromRGB(55, 65, 90); b.BorderSizePixel = 0
	b.Text = label; b.TextColor3 = Color3.fromRGB(230, 235, 250); b.Font = Enum.Font.Gotham; b.TextSize = 12
	b.LayoutOrder = order; b.Parent = parent
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
	b.MouseButton1Click:Connect(onClick)
	return b
end

local function makeToggle(parent, label, order, getState, setState)
	local b = makeButton(parent, label, order, function() setState(not getState()) end)
	local function refresh()
		local s = getState()
		b.Text = label .. ": " .. (s and "ON" or "OFF")
		b.BackgroundColor3 = s and Color3.fromRGB(50, 110, 70) or Color3.fromRGB(90, 55, 60)
	end
	refresh(); b.MouseButton1Click:Connect(refresh)
	return b, refresh
end

local function makeLabel(parent, order)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, 18); l.BackgroundTransparency = 1; l.Text = ""
	l.TextColor3 = Color3.fromRGB(160, 165, 190); l.Font = Enum.Font.Gotham; l.TextSize = 11
	l.TextXAlignment = Enum.TextXAlignment.Left; l.LayoutOrder = order; l.Parent = parent
	return l
end

local function makeStepper(parent, order, labelText, get, set, step, minV, maxV)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 26); row.BackgroundTransparency = 1; row.LayoutOrder = order; row.Parent = parent
	local minus = Instance.new("TextButton")
	minus.Size = UDim2.new(0, 26, 1, 0); minus.Position = UDim2.new(0, 0, 0, 0)
	minus.BackgroundColor3 = Color3.fromRGB(55, 65, 90); minus.BorderSizePixel = 0
	minus.Text = "-"; minus.TextColor3 = Color3.fromRGB(230, 235, 250); minus.Font = Enum.Font.GothamBold; minus.TextSize = 14
	minus.Parent = row; Instance.new("UICorner", minus).CornerRadius = UDim.new(0, 5)
	local lab = Instance.new("TextLabel")
	lab.Size = UDim2.new(1, -60, 1, 0); lab.Position = UDim2.new(0, 30, 0, 0); lab.BackgroundTransparency = 1
	lab.TextColor3 = Color3.fromRGB(220, 225, 245); lab.Font = Enum.Font.Gotham; lab.TextSize = 12
	lab.Text = labelText .. ": " .. tostring(get()); lab.Parent = row
	local plus = minus:Clone(); plus.Position = UDim2.new(1, -26, 0, 0); plus.Text = "+"; plus.Parent = row
	local function refresh() lab.Text = labelText .. ": " .. tostring(get()) end
	minus.MouseButton1Click:Connect(function() set(math.max(minV or -math.huge, get() - step)); refresh() end)
	plus.MouseButton1Click:Connect(function() set(math.min(maxV or math.huge, get() + step)); refresh() end)
	return refresh
end

local refreshers = {}

local function buildRain()
	local API = getgenv and getgenv().SMAZ_RAIN; if not API then return end
	local sec = makeSection("RAIN", 1)
	local _, r1 = makeToggle(sec, "All rain", 1, API.isEnabled, API.setEnabled)
	local _, r2 = makeToggle(sec, "3D drops", 2, API.isRain3D, API.setRain3D)
	local _, r3 = makeToggle(sec, "Screen drops", 3, API.isScreenDrops, API.setScreenDrops)
	table.insert(refreshers, function() r1(); r2(); r3() end)
end

local function buildTornado()
	local API = getgenv and getgenv().SMAZ_TORNADO; if not API then return end
	local sec = makeSection("TORNADO", 2)
	local info = makeLabel(sec, 1)
	makeButton(sec, "Spawn near me", 2, function() API.spawnNear() end)
	makeButton(sec, "Spawn random", 3, function() API.spawnRandom() end)
	makeButton(sec, "Kill all", 4, function() API.killAll() end)
	local _, tr1 = makeToggle(sec, "Auto-spawn", 5, API.isAutoSpawn, API.setAutoSpawn)
	local efBtn = makeButton(sec, "EF: " .. API.getEF() .. "  [cycle]", 6, function()
		API.setEF((API.getEF() + 1) % 6)
	end)
	table.insert(refreshers, function()
		tr1()
		info.Text = string.format("Active: %d / %d", API.count(), API.max())
		efBtn.Text = "EF: " .. API.getEF() .. "  [cycle]"
	end)
end

local function buildLightning()
	local API = getgenv and getgenv().SMAZ_LIGHTNING; if not API then return end
	local sec = makeSection("LIGHTNING", 3)
	makeButton(sec, "Strike now", 1, function() API.strike() end)
	local _, l1 = makeToggle(sec, "Auto strikes", 2, API.isAuto, API.setAuto)
	table.insert(refreshers, function() l1() end)
end

local function buildReflections()
	local API = getgenv and getgenv().SMAZ_REFL; if not API then return end
	local sec = makeSection("REFLECTIONS", 4)
	local info = makeLabel(sec, 1)
	local _, r1 = makeToggle(sec, "Reflections", 2, API.isEnabled, API.setEnabled)
	local _, r2 = makeToggle(sec, "Include character", 3, API.isCloneCharacter, API.setCloneCharacter)
	makeButton(sec, "Rebuild clones", 4, function() API.rebuild() end)
	local radR = makeStepper(sec, 5, "Radius", API.getRadius, API.setRadius, 5, 8, 120)
	local transR = makeStepper(sec, 6, "Base alpha (x100)",
		function() return math.floor(API.getBaseTransparency() * 100) end,
		function(v) API.setBaseTransparency(v / 100) end,
		5, 0, 90)
	table.insert(refreshers, function()
		r1(); r2(); radR(); transR()
		info.Text = "Clones: " .. API.count()
	end)
end

buildRain(); buildTornado(); buildLightning(); buildReflections()

task.spawn(function()
	while gui and gui.Parent do
		for _, fn in ipairs(refreshers) do pcall(fn) end
		task.wait(0.5)
	end
end)

print("[Control Panel v2] Loaded with " .. #refreshers .. " sections")
