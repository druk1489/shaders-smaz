-- Control Panel v1 - unified GUI for all SMAZ modules
-- Reads getgenv().SMAZ_RAIN / SMAZ_TORNADO / SMAZ_LIGHTNING and shows controls only for loaded ones.

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local pgui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 5)
if not pgui then return end

local old = pgui:FindFirstChild("SMAZ_ControlPanel")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "SMAZ_ControlPanel"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 500
gui.Parent = pgui

local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.new(0, 260, 0, 470)
main.Position = UDim2.new(1, -280, 0, 60)
main.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
main.BackgroundTransparency = 0.05
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(80, 90, 120); stroke.Thickness = 1; stroke.Parent = main

-- Title bar
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 32)
titleBar.BackgroundColor3 = Color3.fromRGB(30, 34, 48)
titleBar.BorderSizePixel = 0
titleBar.Parent = main
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -70, 1, 0)
title.Position = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1
title.Text = "SMAZ v12  Control Panel"
title.TextColor3 = Color3.fromRGB(220, 225, 245)
title.Font = Enum.Font.GothamBold
title.TextSize = 13
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = titleBar

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 28, 0, 22)
minBtn.Position = UDim2.new(1, -34, 0, 5)
minBtn.BackgroundColor3 = Color3.fromRGB(50, 55, 70)
minBtn.BorderSizePixel = 0; minBtn.Text = "_"
minBtn.TextColor3 = Color3.fromRGB(230, 230, 245)
minBtn.Font = Enum.Font.GothamBold; minBtn.TextSize = 14
minBtn.Parent = titleBar
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 4)

-- Reopen tab (small button when minimized)
local reopenBtn = Instance.new("TextButton")
reopenBtn.Size = UDim2.new(0, 90, 0, 28)
reopenBtn.Position = UDim2.new(1, -110, 0, 60)
reopenBtn.BackgroundColor3 = Color3.fromRGB(35, 40, 55)
reopenBtn.BorderSizePixel = 0
reopenBtn.Text = "SMAZ v12 \xe2\x96\xb2"
reopenBtn.TextColor3 = Color3.fromRGB(220, 225, 245)
reopenBtn.Font = Enum.Font.GothamBold; reopenBtn.TextSize = 12
reopenBtn.Visible = false
reopenBtn.Parent = gui
Instance.new("UICorner", reopenBtn).CornerRadius = UDim.new(0, 6)

minBtn.MouseButton1Click:Connect(function()
	main.Visible = false; reopenBtn.Visible = true
end)
reopenBtn.MouseButton1Click:Connect(function()
	main.Visible = true; reopenBtn.Visible = false
end)

-- Scroll frame for sections
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -12, 1, -40)
scroll.Position = UDim2.new(0, 6, 0, 36)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.ScrollBarImageColor3 = Color3.fromRGB(80, 90, 120)
scroll.CanvasSize = UDim2.new(0, 0, 0, 800)
scroll.Parent = main
local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 8)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = scroll

local function updateCanvas()
	scroll.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 20)
end
listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas)

local function makeSection(name, order)
	local section = Instance.new("Frame")
	section.Name = name; section.LayoutOrder = order
	section.Size = UDim2.new(1, -6, 0, 0)
	section.AutomaticSize = Enum.AutomaticSize.Y
	section.BackgroundColor3 = Color3.fromRGB(28, 30, 42)
	section.BorderSizePixel = 0
	section.Parent = scroll
	Instance.new("UICorner", section).CornerRadius = UDim.new(0, 6)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6); padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8); padding.PaddingRight = UDim.new(0, 8); padding.Parent = section
	local l = Instance.new("UIListLayout"); l.Padding = UDim.new(0, 4); l.SortOrder = Enum.SortOrder.LayoutOrder; l.Parent = section
	local h = Instance.new("TextLabel")
	h.Size = UDim2.new(1, 0, 0, 20); h.BackgroundTransparency = 1
	h.Text = name; h.TextColor3 = Color3.fromRGB(140, 200, 255)
	h.Font = Enum.Font.GothamBold; h.TextSize = 12; h.TextXAlignment = Enum.TextXAlignment.Left
	h.LayoutOrder = 0; h.Parent = section
	return section
end

local function makeButton(parent, label, layoutOrder, onClick)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 26)
	b.BackgroundColor3 = Color3.fromRGB(55, 65, 90)
	b.BorderSizePixel = 0
	b.Text = label
	b.TextColor3 = Color3.fromRGB(230, 235, 250)
	b.Font = Enum.Font.Gotham; b.TextSize = 12
	b.LayoutOrder = layoutOrder
	b.Parent = parent
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
	b.MouseButton1Click:Connect(onClick)
	return b
end

local function makeToggle(parent, label, layoutOrder, getState, setState)
	local b = makeButton(parent, label, layoutOrder, function() setState(not getState()) end)
	local function refresh()
		local s = getState()
		b.Text = label .. ": " .. (s and "ON" or "OFF")
		b.BackgroundColor3 = s and Color3.fromRGB(50, 110, 70) or Color3.fromRGB(90, 55, 60)
	end
	refresh()
	b.MouseButton1Click:Connect(refresh)
	return b, refresh
end

local function makeLabel(parent, layoutOrder)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, 18)
	l.BackgroundTransparency = 1
	l.Text = ""
	l.TextColor3 = Color3.fromRGB(160, 165, 190)
	l.Font = Enum.Font.Gotham; l.TextSize = 11
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.LayoutOrder = layoutOrder
	l.Parent = parent
	return l
end

local refreshers = {}

-- ===== RAIN section =====
local function buildRain()
	local SMAZ_RAIN = getgenv and getgenv().SMAZ_RAIN
	if not SMAZ_RAIN then return end
	local sec = makeSection("RAIN", 1)
	local _, r1 = makeToggle(sec, "All rain", 1, SMAZ_RAIN.isEnabled, SMAZ_RAIN.setEnabled)
	local _, r2 = makeToggle(sec, "3D drops", 2, SMAZ_RAIN.isRain3D, SMAZ_RAIN.setRain3D)
	local _, r3 = makeToggle(sec, "Screen drops", 3, SMAZ_RAIN.isScreenDrops, SMAZ_RAIN.setScreenDrops)
	table.insert(refreshers, function() r1(); r2(); r3() end)
end

-- ===== TORNADO section =====
local function buildTornado()
	local SMAZ_TORNADO = getgenv and getgenv().SMAZ_TORNADO
	if not SMAZ_TORNADO then return end
	local sec = makeSection("TORNADO", 2)
	local info = makeLabel(sec, 1)
	makeButton(sec, "Spawn near me", 2, function() SMAZ_TORNADO.spawnNear() end)
	makeButton(sec, "Spawn random", 3, function() SMAZ_TORNADO.spawnRandom() end)
	makeButton(sec, "Kill all", 4, function() SMAZ_TORNADO.killAll() end)
	local _, tr1 = makeToggle(sec, "Auto-spawn", 5, SMAZ_TORNADO.isAutoSpawn, SMAZ_TORNADO.setAutoSpawn)
	local efBtn = makeButton(sec, "EF: " .. SMAZ_TORNADO.getEF(), 6, function()
		SMAZ_TORNADO.setEF((SMAZ_TORNADO.getEF() + 1) % 6)
	end)
	table.insert(refreshers, function()
		tr1()
		info.Text = string.format("Active: %d / %d", SMAZ_TORNADO.count(), SMAZ_TORNADO.max())
		efBtn.Text = "EF: " .. SMAZ_TORNADO.getEF() .. "  [click to cycle]"
	end)
end

-- ===== LIGHTNING section =====
local function buildLightning()
	local SMAZ_LIGHTNING = getgenv and getgenv().SMAZ_LIGHTNING
	if not SMAZ_LIGHTNING then return end
	local sec = makeSection("LIGHTNING", 3)
	makeButton(sec, "Strike now", 1, function() SMAZ_LIGHTNING.strike() end)
	local _, l1 = makeToggle(sec, "Auto strikes", 2, SMAZ_LIGHTNING.isAuto, SMAZ_LIGHTNING.setAuto)
	table.insert(refreshers, function() l1() end)
end

buildRain(); buildTornado(); buildLightning()

task.spawn(function()
	while gui and gui.Parent do
		for _, fn in ipairs(refreshers) do pcall(fn) end
		task.wait(0.5)
	end
end)

print("[Control Panel] Loaded with " .. #refreshers .. " sections")
