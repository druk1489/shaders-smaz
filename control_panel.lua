--==========================================================
-- SMAZ Studio Control Panel v6 (Silent Engine UI style)
-- Полный редактор шейдеров: свет, пост-FX, камера/фрикам,
-- атмосфера, погода, эффекты-модули, пресеты, настройки.
--==========================================================
local player = game:GetService("Players").LocalPlayer
local pgui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 5)
if not pgui then return end

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local UIS = UserInputService

local old = pgui:FindFirstChild("SMAZ_ControlPanel")
if old then old:Destroy() end
local guiParent = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")
local old2 = guiParent:FindFirstChild("SMAZ_ControlPanel")
if old2 then old2:Destroy() end

local genv = getgenv or function() return _G end
local G = genv()
local ATMOS = G.SMAZ_ATMOS
local RN = G.SMAZ_RAIN
local TN = G.SMAZ_TORNADO
local LG = G.SMAZ_LIGHTNING
local RF = G.SMAZ_REFL
local PR = G.SMAZ_PRESETS

-- состояние GUI
local uiFx = {
	grain = { on = false, amt = 0.5 },
	vig   = { on = false, amt = 0.35, color = Color3.new(0, 0, 0) },
	dof   = { auto = false },
}
local wCyc     = { on = false, every = 15 }
local camFov   = { manual = 70 }
local camBreath = { on = false, amp = 1.5, speed = 0.8 }
local menuBindKey = "RightControl"
local activeKeybindBtn = nil
local lastCaptureClock = 0
local sliderDragging = false

-- цвета (Silent Engine)
local darkColor   = Color3.fromRGB(32, 32, 32)
local cardColor   = Color3.fromRGB(70, 70, 70)
local pillColor   = Color3.fromRGB(80, 80, 80)
local defaultColor = Color3.fromRGB(255, 255, 255)
local selectedColor = Color3.fromRGB(175, 175, 175)
local ACCENT = Color3.fromRGB(90, 130, 255)
local DANGER = Color3.fromRGB(235, 80, 90)
local OK     = Color3.fromRGB(60, 170, 110)

--==========================================================
-- ОКНО + САЙДБАР (в стиле Silent Engine UI)
--==========================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SMAZ_ControlPanel"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = pgui

local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.fromOffset(640, 440)
main.AnchorPoint = Vector2.new(0.5, 0.5)
main.Position = UDim2.fromScale(0.5, 0.5)
main.BackgroundColor3 = Color3.fromRGB(57, 57, 57)
main.BackgroundTransparency = 0.1
main.BorderSizePixel = 0
main.Active = true
main.ClipsDescendants = true
main.Parent = screenGui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)

local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.Size = UDim2.new(1, 0, 0, 40)
topBar.BackgroundTransparency = 1
topBar.Parent = main

local logo = Instance.new("TextLabel")
logo.Name = "Logo"
logo.Size = UDim2.fromOffset(45, 40)
logo.Position = UDim2.fromOffset(10, 0)
logo.BackgroundTransparency = 1
logo.RichText = true
logo.Text = '<font color="#FFFFFF">S</font><font color="#8C8C8C">Z</font>'
logo.Font = Enum.Font.SourceSansBold
logo.TextSize = 34
logo.TextXAlignment = Enum.TextXAlignment.Left
logo.Parent = topBar

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.fromOffset(130, 20)
title.Position = UDim2.fromOffset(47, 4)
title.BackgroundTransparency = 1
title.Text = "SMAZ Studio"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Font = Enum.Font.SourceSansBold
title.TextSize = 18
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = topBar

local subtitle = Instance.new("TextLabel")
subtitle.Name = "Subtitle"
subtitle.Size = UDim2.fromOffset(130, 14)
subtitle.Position = UDim2.fromOffset(47, 22)
subtitle.BackgroundTransparency = 1
subtitle.Text = "shaders" .. (ATMOS and " / atmos" or " / standalone")
subtitle.TextColor3 = Color3.fromRGB(140, 140, 140)
subtitle.Font = Enum.Font.SourceSansBold
subtitle.TextSize = 13
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Parent = topBar

local crumbLabel = Instance.new("TextLabel")
crumbLabel.Name = "CrumbLabel"
crumbLabel.Size = UDim2.new(1, -220, 0, 40)
crumbLabel.Position = UDim2.fromOffset(210, 0)
crumbLabel.BackgroundTransparency = 1
crumbLabel.RichText = true
crumbLabel.Text = ""
crumbLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
crumbLabel.Font = Enum.Font.SourceSansBold
crumbLabel.TextSize = 15
crumbLabel.TextXAlignment = Enum.TextXAlignment.Left
crumbLabel.Parent = main

local hLine = Instance.new("Frame")
hLine.Name = "HLine"
hLine.Size = UDim2.new(1, 0, 0, 1)
hLine.Position = UDim2.fromOffset(0, 40)
hLine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
hLine.BackgroundTransparency = 0.75
hLine.BorderSizePixel = 0
hLine.Parent = main

local vLine = Instance.new("Frame")
vLine.Name = "VLine"
vLine.Size = UDim2.new(0, 1, 1, 0)
vLine.Position = UDim2.fromOffset(170, 0)
vLine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
vLine.BackgroundTransparency = 0.75
vLine.BorderSizePixel = 0
vLine.Parent = main

local sidebar = Instance.new("Frame")
sidebar.Name = "Sidebar"
sidebar.Size = UDim2.new(0, 170, 1, -41)
sidebar.Position = UDim2.fromOffset(0, 41)
sidebar.BackgroundTransparency = 1
sidebar.Parent = main

local mainLabel = Instance.new("TextLabel")
mainLabel.Name = "MainLabel"
mainLabel.Size = UDim2.fromOffset(100, 14)
mainLabel.Position = UDim2.fromOffset(14, 5)
mainLabel.BackgroundTransparency = 1
mainLabel.Text = "SMAZ"
mainLabel.TextColor3 = Color3.fromRGB(120, 120, 120)
mainLabel.Font = Enum.Font.SourceSansBold
mainLabel.TextSize = 12
mainLabel.TextXAlignment = Enum.TextXAlignment.Left
mainLabel.Parent = sidebar

local content = Instance.new("Frame")
content.Name = "Content"
content.Size = UDim2.new(1, -171, 1, -53)
content.Position = UDim2.fromOffset(171, 41)
content.BackgroundTransparency = 1
content.Parent = main

local tabHolder = Instance.new("ScrollingFrame")
tabHolder.Name = "TabHolder"
tabHolder.Size = UDim2.new(1, 0, 1, -26)
tabHolder.Position = UDim2.fromOffset(0, 26)
tabHolder.BackgroundTransparency = 1
tabHolder.BorderSizePixel = 0
tabHolder.ScrollBarThickness = 2
tabHolder.ScrollBarImageColor3 = Color3.fromRGB(150, 150, 150)
tabHolder.ScrollBarImageTransparency = 0.4
tabHolder.ScrollingDirection = Enum.ScrollingDirection.Y
tabHolder.CanvasSize = UDim2.fromOffset(0, 0)
tabHolder.AutomaticCanvasSize = Enum.AutomaticSize.Y
tabHolder.ClipsDescendants = true
tabHolder.Parent = sidebar
local holderPadding = Instance.new("UIPadding")
holderPadding.PaddingLeft = UDim.new(0, 8)
holderPadding.PaddingRight = UDim.new(0, 16)
holderPadding.Parent = tabHolder
local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 4)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = tabHolder

local TABS = {}
local tabButtons = {}
local tabPages = {}
local tabSections = {}
local currentTab = nil
local refreshers = {}

local function regRefresh(node, fn)
	while node do
		if node.GetAttribute and node:GetAttribute("SMAZPAGE") then
			local list = refreshers[node]
			if not list then list = {}; refreshers[node] = list end
			table.insert(list, fn)
			return
		end
		node = node.Parent
	end
end

local function setTabVisual(tabName, hovered)
	local tab = tabButtons[tabName]
	if not tab then return end
	if currentTab == tabName then
		tab.button.BackgroundTransparency = 0.4
		tab.label.TextColor3 = selectedColor
	elseif hovered then
		tab.button.BackgroundTransparency = 0.55
		tab.label.TextColor3 = defaultColor
	else
		tab.button.BackgroundTransparency = 1
		tab.label.TextColor3 = defaultColor
	end
end

local function selectTab(tabName)
	currentTab = tabName
	for name, _ in pairs(tabButtons) do
		setTabVisual(name, false)
	end
	for name, page in pairs(tabPages) do
		page.Visible = (name == tabName)
	end
	crumbLabel.Text = '<font color="#969696">' .. (tabSections[tabName] or "Main") .. '  /  </font>' .. tabName
end

local layoutOrder = 0
local function mkTab(name, section)
	local layoutOrderSection = layoutOrder
	if section then
		layoutOrder = layoutOrder + 1
		local sectionLabel = Instance.new("TextLabel")
		sectionLabel.Name = section .. "Section"
		sectionLabel.Size = UDim2.new(1, 0, 0, 22)
		sectionLabel.BackgroundTransparency = 1
		sectionLabel.Text = section
		sectionLabel.TextColor3 = Color3.fromRGB(120, 120, 120)
		sectionLabel.Font = Enum.Font.SourceSansBold
		sectionLabel.TextSize = 12
		sectionLabel.TextXAlignment = Enum.TextXAlignment.Left
		sectionLabel.TextYAlignment = Enum.TextYAlignment.Bottom
		sectionLabel.LayoutOrder = layoutOrderSection
		sectionLabel.Parent = tabHolder
	end
	layoutOrder = layoutOrder + 1

	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.new(1, 0, 0, 26)
	button.BackgroundColor3 = pillColor
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = ""
	button.LayoutOrder = layoutOrder
	button.Parent = tabHolder
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 7)

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, -20, 1, 0)
	label.Position = UDim2.fromOffset(14, 0)
	label.BackgroundTransparency = 1
	label.Text = name
	label.TextColor3 = defaultColor
	label.Font = Enum.Font.SourceSansBold
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = button

	local page = Instance.new("ScrollingFrame")
	page.Name = name .. "Page"
	page.Size = UDim2.new(1, 0, 1, 0)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ScrollBarThickness = 4
	page.ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255)
	page.ScrollBarImageTransparency = 0.2
	page.CanvasSize = UDim2.fromOffset(0, 0)
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.ScrollingDirection = Enum.ScrollingDirection.Y
	page.Visible = false
	page:SetAttribute("SMAZPAGE", true)
	page.Parent = content
	local lay = Instance.new("UIListLayout")
	lay.Padding = UDim.new(0, 4)
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Parent = page

	table.insert(TABS, name)
	tabButtons[name] = { button = button, label = label }
	tabPages[name] = page
	tabSections[name] = section or "Main"

	button.MouseEnter:Connect(function() setTabVisual(name, true) end)
	button.MouseLeave:Connect(function() setTabVisual(name, false) end)
	button.MouseButton1Click:Connect(function() selectTab(name) end)
	return page
end

--==========================================================
-- ВИДЖЕТЫ (карточки в стиле Silent Engine)
--==========================================================
local function mkSection(parent, text)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -28, 0, 18)
	label.Position = UDim2.fromOffset(14, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(120, 120, 120)
	label.Font = Enum.Font.SourceSansBold
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

local function mkCard(parent, height, plain)
	local card = Instance.new("Frame")
	if plain then
		card.Size = UDim2.new(1, 0, 0, height)
		card.Position = UDim2.fromOffset(0, 0)
	else
		card.Size = UDim2.new(1, -28, 0, height)
		card.Position = UDim2.fromOffset(14, 0)
	end
	card.BackgroundColor3 = cardColor
	card.BackgroundTransparency = 0.15
	card.BorderSizePixel = 0
	card.Parent = parent
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)
	return card
end

local function mkInfoCard(parent, text)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, -28, 0, 0)
	card.Position = UDim2.fromOffset(14, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = Color3.fromRGB(45, 48, 58)
	card.BackgroundTransparency = 0.15
	card.BorderSizePixel = 0
	card.Parent = parent
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, -16, 0, 0)
	l.Position = UDim2.fromOffset(8, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = Color3.fromRGB(170, 175, 190)
	l.Font = Enum.Font.SourceSansBold
	l.TextSize = 13
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = card
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, 6)
	p.PaddingBottom = UDim.new(0, 6)
	p.Parent = l
	return card
end

local function mkSwitch(parent, width, height)
	local knobSize = height - 4
	local switch = Instance.new("TextButton")
	switch.Name = "Switch"
	switch.Size = UDim2.fromOffset(width, height)
	switch.AnchorPoint = Vector2.new(1, 0.5)
	switch.Position = UDim2.new(1, -10, 0.5, 0)
	switch.BackgroundColor3 = darkColor
	switch.BorderSizePixel = 0
	switch.AutoButtonColor = false
	switch.Text = ""
	switch.Parent = parent
	Instance.new("UICorner", switch).CornerRadius = UDim.new(1, 0)
	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.Size = UDim2.fromOffset(knobSize, knobSize)
	knob.Position = UDim2.new(0, 2, 0.5, -knobSize / 2)
	knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	knob.BorderSizePixel = 0
	knob.Parent = switch
	Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
	local state = false
	local function setState(v)
		state = not not v
		local pillGoal = state and Color3.fromRGB(80, 180, 120) or darkColor
		local knobGoal = state and Color3.fromRGB(240, 240, 240) or Color3.fromRGB(255, 255, 255)
		local knobPos = state and UDim2.new(1, -knobSize - 2, 0.5, -knobSize / 2) or UDim2.new(0, 2, 0.5, -knobSize / 2)
		TweenService:Create(switch, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundColor3 = pillGoal }):Play()
		TweenService:Create(knob, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundColor3 = knobGoal, Position = knobPos }):Play()
	end
	switch.MouseButton1Click:Connect(function() setState(not state) end)
	return switch, setState
end

local function mkToggleCard(page, titleText, descText, get, set)
	local card = mkCard(page, 52)
	local cardTitle = Instance.new("TextLabel")
	cardTitle.Size = UDim2.new(1, -70, 0, 18)
	cardTitle.Position = UDim2.fromOffset(12, 9)
	cardTitle.BackgroundTransparency = 1
	cardTitle.Text = titleText
	cardTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	cardTitle.Font = Enum.Font.SourceSansBold
	cardTitle.TextSize = 16
	cardTitle.TextXAlignment = Enum.TextXAlignment.Left
	cardTitle.Parent = card
	local cardDesc = Instance.new("TextLabel")
	cardDesc.Size = UDim2.new(1, -70, 0, 14)
	cardDesc.Position = UDim2.fromOffset(12, 28)
	cardDesc.BackgroundTransparency = 1
	cardDesc.Text = descText or ""
	cardDesc.TextColor3 = Color3.fromRGB(140, 140, 140)
	cardDesc.Font = Enum.Font.SourceSansBold
	cardDesc.TextSize = 13
	cardDesc.TextXAlignment = Enum.TextXAlignment.Left
	cardDesc.TextTruncate = Enum.TextTruncate.AtEnd
	cardDesc.Parent = card
	local sw, setState = mkSwitch(card, 34, 16)
	sw.MouseButton1Click:Connect(function()
		local v = get and not not (get()) or false
		if set then set(not v) end
	end)
	local function refresh()
		if get then setState(not not get()) end
	end
	regRefresh(page, refresh)
	refresh()
	return setState
end

local function mkSliderCard(page, label, get, set, minV, maxV, fmt, height, nested)
	fmt = fmt or "%.2f"
	height = height or 40
	local card = mkCard(page, height, nested)
	local lab = Instance.new("TextLabel")
	lab.Size = UDim2.new(0, 40, 1, 0)
	lab.Position = UDim2.fromOffset(10, 0)
	lab.BackgroundTransparency = 1
	lab.Text = label
	lab.TextColor3 = Color3.fromRGB(255, 255, 255)
	lab.Font = Enum.Font.SourceSansBold
	lab.TextSize = 13
	lab.TextXAlignment = Enum.TextXAlignment.Left
	lab.TextTruncate = Enum.TextTruncate.AtEnd
	lab.Parent = card

	local valueBox = Instance.new("Frame")
	valueBox.Size = UDim2.fromOffset(46, 16)
	valueBox.AnchorPoint = Vector2.new(1, 0.5)
	valueBox.Position = UDim2.new(1, -8, 0.5, 0)
	valueBox.BackgroundColor3 = darkColor
	valueBox.BorderSizePixel = 0
	valueBox.Parent = card
	Instance.new("UICorner", valueBox).CornerRadius = UDim.new(0, 4)
	local valueLabel = Instance.new("TextLabel")
	valueLabel.Size = UDim2.new(1, 0, 1, 0)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Text = fmt:format(minV)
	valueLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	valueLabel.Font = Enum.Font.SourceSansBold
	valueLabel.TextSize = 11
	valueLabel.Parent = valueBox

	local track = Instance.new("Frame")
	track.Size = UDim2.new(0, 120, 0, 4)
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.Position = UDim2.new(1, -62, 0.5, 0)
	track.BackgroundColor3 = darkColor
	track.BorderSizePixel = 0
	track.Parent = card
	Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	fill.BorderSizePixel = 0
	fill.Parent = track
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
	local knob = Instance.new("Frame")
	knob.Size = UDim2.fromOffset(10, 10)
	knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	knob.BorderSizePixel = 0
	knob.Parent = track
	Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

	local function applyRatio(ratio)
		ratio = math.clamp(ratio, 0, 1)
		local v = minV + (maxV - minV) * ratio
		if set then pcall(set, v) end
		fill.Size = UDim2.fromScale(ratio, 1)
		knob.Position = UDim2.new(ratio, -5, 0.5, -5)
		valueLabel.Text = fmt:format(v)
	end
	local function refresh()
		local v = tonumber(get and get()) or minV
		local ratio = math.clamp((v - minV) / math.max(0.0001, maxV - minV), 0, 1)
		fill.Size = UDim2.fromScale(ratio, 1)
		knob.Position = UDim2.new(ratio, -5, 0.5, -5)
		valueLabel.Text = fmt:format(v)
	end

	local hit = Instance.new("TextButton")
	hit.Size = UDim2.new(0, 126, 1, 0)
	hit.AnchorPoint = Vector2.new(1, 0)
	hit.Position = UDim2.new(1, -56, 0, 0)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.ZIndex = 3
	hit.Parent = card
	local active = false
	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			active = true
			sliderDragging = true
			applyRatio((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X)
		end
	end)
	UIS.InputChanged:Connect(function(input)
		if active and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			applyRatio((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X)
		end
	end)
	UIS.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			active = false
			sliderDragging = false
		end
	end)

	regRefresh(page, refresh)
	refresh()
	return refresh
end

local function mkButtonCard(page, label, cb, accent)
	local card = mkCard(page, 38)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 1, 0)
	b.BackgroundTransparency = 1
	b.Text = label
	b.Font = Enum.Font.SourceSansBold
	b.TextSize = 14
	b.TextColor3 = accent or defaultColor
	b.AutoButtonColor = false
	b.Parent = card
	b.MouseButton1Click:Connect(function()
		if cb then pcall(cb) end
	end)
	return b
end

local function mkDropdownCard(page, label, options, get, set)
	local card = mkCard(page, 40)
	local lab = Instance.new("TextLabel")
	lab.Size = UDim2.new(1, -160, 1, 0)
	lab.Position = UDim2.fromOffset(12, 0)
	lab.BackgroundTransparency = 1
	lab.Text = label
	lab.TextColor3 = Color3.fromRGB(255, 255, 255)
	lab.Font = Enum.Font.SourceSansBold
	lab.TextSize = 14
	lab.TextXAlignment = Enum.TextXAlignment.Left
	lab.TextTruncate = Enum.TextTruncate.AtEnd
	lab.Parent = card
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.fromOffset(120, 22)
	btn.AnchorPoint = Vector2.new(1, 0.5)
	btn.Position = UDim2.new(1, -10, 0.5, 0)
	btn.BackgroundColor3 = darkColor
	btn.BorderSizePixel = 0
	btn.Text = options[1] or ""
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Font = Enum.Font.SourceSansBold
	btn.TextSize = 13
	btn.Parent = card
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromOffset(120, 0)
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -10, 0, 40)
	panel.BackgroundColor3 = darkColor
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ClipsDescendants = true
	panel.ZIndex = 20
	panel.Parent = card
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 6)
	local holder = Instance.new("ScrollingFrame")
	holder.Size = UDim2.new(1, 0, 0, math.min(#options * 24, 60))
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.ScrollBarThickness = 3
	holder.CanvasSize = UDim2.fromOffset(0, 0)
	holder.AutomaticCanvasSize = Enum.AutomaticSize.Y
	holder.ZIndex = 21
	holder.Parent = panel
	local ol = Instance.new("UIListLayout")
	ol.SortOrder = Enum.SortOrder.LayoutOrder
	ol.Parent = holder
	local open = false
	local selected = options[1] or ""
	local function refresh()
		local cur = get and get() or nil
		local idx = 1
		if cur then
			for i, o in ipairs(options) do
				if tostring(o) == tostring(cur) then idx = i end
			end
		end
		selected = options[idx]
		btn.Text = tostring(selected)
	end
	for i, opt in ipairs(options) do
		local ob = Instance.new("TextButton")
		ob.Size = UDim2.new(1, -6, 0, 24)
		ob.BackgroundTransparency = 1
		ob.Text = tostring(opt)
		ob.TextColor3 = Color3.fromRGB(200, 200, 200)
		ob.Font = Enum.Font.SourceSansBold
		ob.TextSize = 13
		ob.ZIndex = 21
		ob.Parent = holder
		ob.MouseButton1Click:Connect(function()
			selected = opt
			btn.Text = tostring(opt)
			if set then pcall(set, opt) end
			open = false
			panel.Visible = false
		end)
	end
	btn.MouseButton1Click:Connect(function()
		open = not open
		panel.Visible = open
		panel.Size = UDim2.fromOffset(120, open and (34 + math.min(#options * 24, 60)) or 0)
	end)
	regRefresh(page, refresh)
	refresh()
	return refresh
end

local function mkKeybindCard(page, label, defaultKey, onRebind)
	local card = mkCard(page, 40)
	local lab = Instance.new("TextLabel")
	lab.Size = UDim2.new(1, -140, 1, 0)
	lab.Position = UDim2.fromOffset(12, 0)
	lab.BackgroundTransparency = 1
	lab.Text = label
	lab.TextColor3 = Color3.fromRGB(255, 255, 255)
	lab.Font = Enum.Font.SourceSansBold
	lab.TextSize = 14
	lab.TextXAlignment = Enum.TextXAlignment.Left
	lab.Parent = card
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.fromOffset(0, 20)
	btn.AutomaticSize = Enum.AutomaticSize.X
	btn.AnchorPoint = Vector2.new(1, 0.5)
	btn.Position = UDim2.new(1, -10, 0.5, 0)
	btn.BackgroundColor3 = darkColor
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Text = defaultKey or "None"
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Font = Enum.Font.SourceSansBold
	btn.TextSize = 12
	btn.Parent = card
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = btn
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
	local function setText(t)
		btn.Text = t
	end
	btn.MouseButton1Click:Connect(function()
		activeKeybindBtn = btn
		btn.Text = "..."
	end)
	UIS.InputBegan:Connect(function(input, gp)
		if gp then return end
		if activeKeybindBtn ~= btn then return end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		activeKeybindBtn = nil
		lastCaptureClock = os.clock()
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Backspace then
			btn.Text = "None"
			if onRebind then pcall(onRebind, "None") end
		else
			btn.Text = input.KeyCode.Name
			if onRebind then pcall(onRebind, input.KeyCode.Name) end
		end
	end)
	return { setKey = setText }
end

local function mkColorCard(page, label, get, set)
	local card = mkCard(page, 110)
	local chip = Instance.new("Frame")
	chip.Size = UDim2.fromOffset(40, 18)
	chip.Position = UDim2.fromOffset(10, 8)
	chip.BackgroundColor3 = Color3.new(1, 0, 0)
	chip.BorderSizePixel = 0
	chip.Parent = card
	Instance.new("UICorner", chip).CornerRadius = UDim.new(0, 5)
	local lab = Instance.new("TextLabel")
	lab.Size = UDim2.new(1, -140, 0, 18)
	lab.Position = UDim2.fromOffset(58, 8)
	lab.BackgroundTransparency = 1
	lab.Text = label
	lab.TextColor3 = Color3.fromRGB(255, 255, 255)
	lab.Font = Enum.Font.SourceSansBold
	lab.TextSize = 14
	lab.TextXAlignment = Enum.TextXAlignment.Left
	lab.Parent = card
	local inner = Instance.new("Frame")
	inner.Size = UDim2.new(1, -20, 0, 0)
	inner.Position = UDim2.fromOffset(10, 30)
	inner.AutomaticSize = Enum.AutomaticSize.Y
	inner.BackgroundTransparency = 1
	inner.Parent = card
	local il = Instance.new("UIListLayout")
	il.Padding = UDim.new(0, 2)
	il.SortOrder = Enum.SortOrder.LayoutOrder
	il.Parent = inner
	local function cur() return get and (get() or Color3.new()) or Color3.new() end
	local r = mkSliderCard(inner, "R", function() return cur().R end, function(v) set(Color3.new(v, cur().G, cur().B)) end, 0, 1, "%.2f", 24, true)
	local g = mkSliderCard(inner, "G", function() return cur().G end, function(v) set(Color3.new(cur().R, v, cur().B)) end, 0, 1, "%.2f", 24, true)
	local b = mkSliderCard(inner, "B", function() return cur().B end, function(v) set(Color3.new(cur().R, cur().G, v)) end, 0, 1, "%.2f", 24, true)
	local function refresh()
		local c = cur()
		chip.BackgroundColor3 = c
		r(); g(); b()
	end
	regRefresh(card, refresh)
	refresh()
	return refresh
end

--==========================================================
-- ДОСТУП К Lighting / ЭФФЕКТАМ (безопасно)
--==========================================================
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
local function mkInputCard(page, label, get, set)
	local row = Instance.new("Frame")
	row.Name = "InputCard"
	row.Size = UDim2.new(1, 0, 0, 54)
	row.BackgroundColor3 = Color3.fromRGB(34, 38, 52)
	row.BorderSizePixel = 0
	row.Parent = page
	pcall(function()
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = row
	end)
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Position = UDim2.new(0, 10, 0, 4); lbl.Size = UDim2.new(1, -20, 0, 18)
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Font = Enum.Font.Gotham; lbl.TextSize = 13
	lbl.TextColor3 = Color3.fromRGB(220, 220, 230)
	lbl.Text = label
	lbl.Parent = row
	local box = Instance.new("TextBox")
	box.Position = UDim2.new(0, 10, 0, 26); box.Size = UDim2.new(1, -20, 0, 20)
	box.BackgroundColor3 = Color3.fromRGB(22, 25, 36)
	box.TextColor3 = Color3.fromRGB(235, 235, 245)
	box.PlaceholderColor3 = Color3.fromRGB(120, 125, 145)
	box.PlaceholderText = "вставь id..."
	box.Font = Enum.Font.Gotham; box.TextSize = 12
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.ClearTextOnFocus = false
	pcall(function()
		local c2 = Instance.new("UICorner"); c2.CornerRadius = UDim.new(0, 4); c2.Parent = box
	end)
	local ok, cur = pcall(get)
	box.Text = (ok and cur ~= nil) and tostring(cur) or ""
	box.Parent = row
	box.FocusLost:Connect(function()
		pcall(set, box.Text)
	end)
	return row
end

local function getOrCreate(name, className)
	local e = Lighting:FindFirstChild(name)
	if e and e:IsA(className) then return e end
	if e then pcall(function() e:Destroy() end) end
	-- ФИКС: раньше Name не ставился и эффект создавался ВКЛЮЧЁННЫМ —
	-- каждый запуск панели плодил безымянные дубликаты SunRays/Bloom/Blur/CC/DoF,
	-- которые уже нельзя было выключить ("лучи не вырубаются")
	local n = Instance.new(className)
	n.Name = name
	n.Enabled = false
	n.Parent = Lighting
	return n
end

--==========================================================
-- ВКЛАДКА: СВЕТ
--==========================================================
local pLight = mkTab("СВЕТ", "СЦЕНА")

mkSection(pLight, "ОСВЕЩЕНИЕ / ВРЕМЯ")
if ATMOS then
	mkSliderCard(pLight, "Яркость макс.", function() return ATMOS.get("maxBrightness") or 2.5 end,
		function(v) ATMOS.set("maxBrightness", v) end, 0.3, 10, "%.2f")
	mkToggleCard(pLight, "Цикл день/ночь", "Автопрокрутка времени", function() return ATMOS.get("dayNight") ~= false end,
		function(v) ATMOS.set("dayNight", v) end)
	mkSliderCard(pLight, "Время суток", function() return ATMOS.get("timeOfDay") or 12 end,
		function(v) ATMOS.set("dayNight", false); ATMOS.set("timeOfDay", v) end, 0, 24, "%.1f")
else
	mkSliderCard(pLight, "Яркость", function() return getL("Brightness") or 1 end,
		function(v) setL("Brightness", v) end, 0, 10, "%.2f")
	mkSliderCard(pLight, "Время суток", function() return getL("ClockTime") or 12 end,
		function(v) setL("ClockTime", v) end, 0, 24, "%.1f")
end

mkSection(pLight, "ЭКСПОЗИЦИЯ")
mkSliderCard(pLight, "Экспозиция (EV)", function() return getL("ExposureCompensation") or 0 end,
	function(v) setL("ExposureCompensation", v) end, -5, 5, "%.2f")

mkSection(pLight, "ТЕНИ")
mkToggleCard(pLight, "Глобальные тени", "", function() return getL("GlobalShadows") end,
	function(v) setL("GlobalShadows", v) end)
mkSliderCard(pLight, "Мягкость теней", function() return getL("ShadowSoftness") or 0 end,
	function(v) setL("ShadowSoftness", v) end, 0, 1, "%.2f")
mkSliderCard(pLight, "Интенсивность тени", function() return getL("ShadowIntensity") or 0 end,
	function(v) setL("ShadowIntensity", v) end, 0, 1, "%.2f")

mkSection(pLight, "ОКРУЖЕНИЕ / ТЕХНОЛОГИЯ")
mkSliderCard(pLight, "Спекуляр", function() return getL("SpecularScale") or 1 end,
	function(v) setL("SpecularScale", v) end, 0, 1, "%.2f")
mkSliderCard(pLight, "Диффузия окруж.", function() return getL("EnvironmentDiffuseScale") or 1 end,
	function(v) setL("EnvironmentDiffuseScale", v) end, 0, 1, "%.2f")
mkSliderCard(pLight, "Спекуляр окруж.", function() return getL("EnvironmentSpecularScale") or 1 end,
	function(v) setL("EnvironmentSpecularScale", v) end, 0, 1, "%.2f")
mkSliderCard(pLight, "Гео-широта", function() return getL("GeographicLatitude") or 0 end,
	function(v) setL("GeographicLatitude", v) end, -90, 90, "%.0f")
mkDropdownCard(pLight, "Технология рендера", {"Legacy","Voxel","ShadowMap","Compatibility","Future","Video"}, getTech, setTech)

mkSection(pLight, "ТУМАН")
mkToggleCard(pLight, "Туман", "", function() return getL("FogEnabled") end,
	function(v) setL("FogEnabled", v) end)
mkSliderCard(pLight, "Fog Start", function() return getL("FogStart") or 0 end,
	function(v) setL("FogStart", v) end, 0, 100000, "%.0f")
mkSliderCard(pLight, "Fog End", function() return getL("FogEnd") or 1024 end,
	function(v) setL("FogEnd", v) end, 0, 100000, "%.0f")
mkColorCard(pLight, "Цвет тумана", function() return getL("FogColor") or Color3.new(0.75, 0.78, 0.8) end,
	function(c) setL("FogColor", c) end)
mkToggleCard(pLight, "Туман на прозрачных", "FogTransparencyMaterials", function() return getL("FogTransparencyMaterials") == true end,
	function(v) setL("FogTransparencyMaterials", v) end)

mkSection(pLight, "ОКРУЖАЮЩИЙ СВЕТ (AMBIENT)")
mkColorCard(pLight, "Ambient", function() return getL("Ambient") or Color3.new(0.1, 0.1, 0.1) end,
	function(c) setL("Ambient", c) end)
mkColorCard(pLight, "OutdoorAmbient", function() return getL("OutdoorAmbient") or Color3.new(0, 0, 0) end,
	function(c) setL("OutdoorAmbient", c) end)
mkColorCard(pLight, "AmbientSky", function() return getL("AmbientSkyColor") or Color3.new(0.4, 0.4, 0.4) end,
	function(c) setL("AmbientSkyColor", c) end)
mkColorCard(pLight, "IndoorAmbient", function() return getL("IndoorAmbient") or Color3.new(0, 0, 0) end,
	function(c) setL("IndoorAmbient", c) end)

mkSection(pLight, "АТМОСФЕРА (ОБЪЕКТ ROBLOX)")
local function atmosphereObj()
	return Lighting:FindFirstChildOfClass("Atmosphere")
end
mkSliderCard(pLight, "Плотность", function()
	local a = atmosphereObj()
	local ok, v = pcall(function() return ATMOS and ATMOS.get("atmDensity") or (a and a.Density or 0.3) end)
	return ok and v or 0.3
end, function(v)
	if ATMOS then ATMOS.set("atmDensity", v) else local a = atmosphereObj(); if a then pcall(function() a.Density = v end) end end
end, 0, 1, "%.2f")
mkSliderCard(pLight, "Дымка (Haze)", function()
	local a = atmosphereObj()
	local ok, v = pcall(function() return ATMOS and ATMOS.get("atmHaze") or (a and a.Haze or 1.4) end)
	return ok and v or 1.4
end, function(v)
	if ATMOS then ATMOS.set("atmHaze", v) else local a = atmosphereObj(); if a then pcall(function() a.Haze = v end) end end
end, 0, 4, "%.2f")
mkSliderCard(pLight, "Offset", function() local a = atmosphereObj(); local ok, v = pcall(function() return a and a.Offset or 0 end) return ok and v or 0 end,
	function(v) local a = atmosphereObj(); if a then pcall(function() a.Offset = v end) end end, -1, 1, "%.2f")
mkSliderCard(pLight, "Glare", function() local a = atmosphereObj(); local ok, v = pcall(function() return a and a.Glare or 0 end) return ok and v or 0 end,
	function(v) local a = atmosphereObj(); if a then pcall(function() a.Glare = v end) end end, 0, 1, "%.2f")
mkSliderCard(pLight, "Distortion", function() local a = atmosphereObj(); local ok, v = pcall(function() return a and a.DistortionScale or 0 end) return ok and v or 0 end,
	function(v) local a = atmosphereObj(); if a then pcall(function() a.DistortionScale = v end) end end, 0, 10, "%.2f")

--==========================================================
-- ВКЛАДКА: ПОСТ FX
--==========================================================
local pFX = mkTab("ПОСТ FX", "СЦЕНА")

mkSection(pFX, "BLOOM / СВЕЧЕНИЕ")
local bloomFx = getOrCreate("__PanelBloom", "BloomEffect")
mkToggleCard(pFX, "Bloom", "", function()
	if ATMOS then return ATMOS.get("bloom") ~= false end
	return pcall(function() return bloomFx.Enabled == true end)
end, function(v)
	if ATMOS then ATMOS.set("bloom", v) else pcall(function() bloomFx.Enabled = v end) end
end)
mkSliderCard(pFX, "Интенсивность", function()
	if ATMOS and ATMOS.get("bloomIntensity") and ATMOS.get("bloomIntensity") > 0 then return ATMOS.get("bloomIntensity") end
	local ok, v = pcall(function() return bloomFx.Intensity end); return ok and v or 1
end, function(v)
	if ATMOS then ATMOS.set("bloomIntensity", v) end
	pcall(function() bloomFx.Intensity = v end)
end, 0, 5, "%.2f")
mkSliderCard(pFX, "Размер", function() local ok, v = pcall(function() return bloomFx.Size end) return ok and v or 20 end,
	function(v) pcall(function() bloomFx.Size = v end) end, 0, 100, "%.0f")
mkSliderCard(pFX, "Порог (Threshold)", function() local ok, v = pcall(function() return bloomFx.Threshold end) return ok and v or 1 end,
	function(v) pcall(function() bloomFx.Threshold = v end) end, 0, 3, "%.2f")

mkSection(pFX, "BLUR / РАЗМЫТИЕ")
local sBlur = {
	on      = ATMOS and ATMOS.get("blur") == true or false,
	mode    = ATMOS and ATMOS.getBlurMode() or "global",
	size    = (ATMOS and ATMOS.get("blurAmt")) or 12,
	maxDist = (ATMOS and ATMOS.get("blurMaxDist")) or 250,
}
local myBlurFx = nil
local function panelBlurFx()
	if ATMOS then return nil end
	myBlurFx = myBlurFx or getOrCreate("__PanelBlur", "BlurEffect")
	return myBlurFx
end
mkToggleCard(pFX, "Blur", "", function()
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
mkSliderCard(pFX, "Сила (Size)", function()
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
mkDropdownCard(pFX, "Режим блюра", {"global", "distance"}, function()
	if ATMOS then return ATMOS.getBlurMode() or "global" end
	return sBlur.mode
end, function(v)
	sBlur.mode = v
	if ATMOS then ATMOS.setBlurMode(v) end
end)
mkSliderCard(pFX, "Макс. дистанция", function()
	if ATMOS then return ATMOS.get("blurMaxDist") or sBlur.maxDist end
	return sBlur.maxDist
end, function(v)
	sBlur.maxDist = v
	if ATMOS then ATMOS.set("blurMaxDist", v) end
end, 20, 1000, "%.0f")
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
			if not cam then return end
			local prm = RaycastParams.new()
			prm.FilterType = Enum.RaycastFilterType.Exclude
			-- ФИКС: свой персонаж в игноре, иначе превью блюра скачет при ходьбе
			local excl = { cam }
			pcall(function()
				local lp = game:GetService("Players").LocalPlayer
				local ch = lp and lp.Character or nil
				if ch then excl[#excl + 1] = ch end
			end)
			prm.FilterDescendantsInstances = excl
			prm.IgnoreWater = true
			local hit = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * sBlur.maxDist, prm)
			local d = hit and hit.Distance or sBlur.maxDist
			if d < 12 then d = sBlur.maxDist end
			pcall(function() fx.Size = math.clamp(d / math.max(1, sBlur.maxDist), 0, 1) * sBlur.size end)
		end)
	end)
end

mkSection(pFX, "ЗЕРНО / ВИНЬЕТКА")
mkToggleCard(pFX, "Зерно (grain)", "Киноплёночный шум", function() return uiFx.grain.on end,
	function(v) uiFx.grain.on = v end)
mkSliderCard(pFX, "Интенсивность зерна", function() return uiFx.grain.amt end,
	function(v) uiFx.grain.amt = v end, 0, 1, "%.2f")
mkToggleCard(pFX, "Виньетка", "", function() return uiFx.vig.on end,
	function(v) uiFx.vig.on = v end)
mkSliderCard(pFX, "Сила виньетки", function() return uiFx.vig.amt end,
	function(v) uiFx.vig.amt = v end, 0, 1, "%.2f")
mkColorCard(pFX, "Цвет виньетки", function() return uiFx.vig.color end,
	function(c) uiFx.vig.color = c end)

mkSection(pFX, "ЦВЕТОКОРРЕКЦИЯ")
local ccFx = getOrCreate("__PanelCC", "ColorCorrectionEffect")
mkToggleCard(pFX, "ColorCorrection", "", function() return ccFx.Enabled end,
	function(v) pcall(function() ccFx.Enabled = v end) end)
mkSliderCard(pFX, "Яркость (Luma)", function() local ok, v = pcall(function() return ccFx.Brightness end) return ok and v or 0 end,
	function(v) pcall(function() ccFx.Brightness = v end) end, -1, 1, "%.2f")
mkSliderCard(pFX, "Контраст", function() local ok, v = pcall(function() return ccFx.Contrast end) return ok and v or 0 end,
	function(v) pcall(function() ccFx.Contrast = v end) end, -1, 1, "%.2f")
mkSliderCard(pFX, "Насыщенность", function() local ok, v = pcall(function() return ccFx.Saturation end) return ok and v or 0 end,
	function(v) pcall(function() ccFx.Saturation = v end) end, -2, 2, "%.2f")
mkColorCard(pFX, "Тонировка (Tint)", function() local ok, v = pcall(function() return ccFx.TintColor end) return ok and v or Color3.new(1, 1, 1) end,
	function(c) pcall(function() ccFx.TintColor = c end) end)

mkSection(pFX, "СОЛНЕЧНЫЕ ЛУЧИ (SunRays)")
local sunFx = getOrCreate("__PanelSunRays", "SunRaysEffect")
mkToggleCard(pFX, "SunRays", "", function()
	if ATMOS then return ATMOS.get("rays") ~= false end
	return sunFx.Enabled
end, function(v)
	if ATMOS then ATMOS.set("rays", v) end
	pcall(function() sunFx.Enabled = v end) -- свой дубликат панели гасим всегда, иначе лучи висят
end)
mkSliderCard(pFX, "Интенсивность лучей", function()
	if ATMOS then
		local ri = ATMOS.get("raysIntensity") or 0
		return ri > 0 and ri or 0.4
	end
	local ok, v = pcall(function() return sunFx.Intensity end); return ok and v or 0.2
end, function(v)
	pcall(function() sunFx.Intensity = v end)
	if ATMOS then ATMOS.set("raysIntensity", v) end
end, 0, 2, "%.2f")
mkSliderCard(pFX, "Spread", function()
	if ATMOS then
		local rs = ATMOS.get("raysSpread") or 0
		return rs > 0 and rs or 0.9
	end
	local ok, v = pcall(function() return sunFx.Spread end); return ok and v or 1
end, function(v)
	pcall(function() sunFx.Spread = v end)
	if ATMOS then ATMOS.set("raysSpread", v) end
end, 0, 3, "%.2f")

mkSection(pFX, "ГЛУБИНА РЕЗКОСТИ (DoF)")
local dofFx = getOrCreate("__PanelDoF", "DepthOfFieldEffect")
mkToggleCard(pFX, "DepthOfField", "", function() return dofFx.Enabled end,
	function(v) pcall(function() dofFx.Enabled = v end) end)
mkSliderCard(pFX, "Фокусная дистанция", function() local ok, v = pcall(function() return dofFx.FocusDistance end) return ok and v or 512 end,
	function(v) pcall(function() dofFx.FocusDistance = v end) end, 0, 10000, "%.0f")
mkSliderCard(pFX, "Зона фокуса", function() local ok, v = pcall(function() return dofFx.InFocusRadius end) return ok and v or 256 end,
	function(v) pcall(function() dofFx.InFocusRadius = v end) end, 0, 3000, "%.0f")
mkSliderCard(pFX, "Дальний блюр", function() local ok, v = pcall(function() return dofFx.FarIntensity end) return ok and v or 0.3 end,
	function(v) pcall(function() dofFx.FarIntensity = v end) end, 0, 1, "%.2f")
mkSliderCard(pFX, "Ближний блюр", function() local ok, v = pcall(function() return dofFx.NearIntensity end) return ok and v or 0 end,
	function(v) pcall(function() dofFx.NearIntensity = v end) end, 0, 1, "%.2f")
mkToggleCard(pFX, "Автофокус по прицелу", "Raycast в направлении камеры", function() return uiFx.dof.auto end,
	function(v) uiFx.dof.auto = v end)

--==========================================================
-- ВКЛАДКА: КАМЕРА
--==========================================================
local pCam = mkTab("КАМЕРА", "СЦЕНА")

local camBase = workspace.CurrentCamera
local camBaseFov = pcall(function() return camBase and camBase.FieldOfView or 70 end) and camBase and camBase.FieldOfView or 70
camFov.manual = camBaseFov

mkSection(pCam, "ПРОЕКЦИЯ")
mkSliderCard(pCam, "FOV (обзор)", function()
	local c = workspace.CurrentCamera
	local ok, v = pcall(function() return c and c.FieldOfView or camFov.manual end)
	return ok and v or camFov.manual
end, function(v)
	camFov.manual = v
	local c = workspace.CurrentCamera
	if c and not camBreath.on then pcall(function() c.FieldOfView = v end) end
end, 30, 120, "%.0f")
mkButtonCard(pCam, "Сбросить FOV (" .. math.floor(camBaseFov) .. "°)", function()
	camFov.manual = camBaseFov
	local c = workspace.CurrentCamera
	if c and not camBreath.on then pcall(function() c.FieldOfView = camBaseFov end) end
end)

mkSection(pCam, "ФРИКАМ (MYTHOS / QUENTY)")
mkToggleCard(pCam, "Фрикам", "Shift+P или тумблер; ПКМ — обзор",
	function() return ATMOS and ATMOS.isFreecam() or false end,
	function(v) if ATMOS then ATMOS.setFreecam(v) end end)
mkSliderCard(pCam, "Скорость", function() return (ATMOS and ATMOS.get("freeCamSpeed")) or 140 end,
	function(v) if ATMOS then ATMOS.set("freeCamSpeed", v) end end, 20, 500, "%.0f")
mkSliderCard(pCam, "Чувствительность мыши", function() return (ATMOS and ATMOS.get("sens")) or 1 end,
	function(v) if ATMOS then ATMOS.set("sens", v) end end, 0.1, 4, "%.2f")
mkInfoCard(pCam, "Управление: WASD — движение, E/Q — вверх/вниз, удерживай ПКМ и двигай мышь — обзор, колесо — зум, Shift — медленно, Ctrl — быстро. Фрикам встроен в Atmosphere (версия Quenty из Mythos admin).")

mkSection(pCam, "ПОВЕДЕНИЕ / ЖИВОСТЬ")
mkToggleCard(pCam, "Дышащая перспектива", "Плавное колебание FOV", function() return camBreath.on end,
	function(v)
		camBreath.on = v
		if not v then
			local c = workspace.CurrentCamera
			if c then pcall(function() c.FieldOfView = camFov.manual end) end
		end
	end)
mkSliderCard(pCam, "Амплитуда дыхания", function() return camBreath.amp end,
	function(v) camBreath.amp = v end, 0, 8, "%.2f")
mkSliderCard(pCam, "Скорость дыхания", function() return camBreath.speed end,
	function(v) camBreath.speed = v end, 0.1, 5, "%.2f")

--==========================================================
-- ВКЛАДКА: АТМОС
--==========================================================
local pAtm = mkTab("АТМОС", "АТМОСФЕРА")
if ATMOS then
	mkSection(pAtm, "ОБЛАКА")
	mkToggleCard(pAtm, "Облака", "", function() return ATMOS.get("clouds") ~= false end,
		function(v) ATMOS.set("clouds", v) end)
	mkToggleCard(pAtm, "Анимация облаков", "", function() return ATMOS.get("cloudAnimate") ~= false end,
		function(v) ATMOS.set("cloudAnimate", v) end)
	mkSliderCard(pAtm, "Покрытие", function() return ATMOS.get("cloudCover") or 0.6 end,
		function(v) ATMOS.set("cloudCover", v) end, 0, 1, "%.2f")
	mkSliderCard(pAtm, "Плотность", function() return ATMOS.get("cloudDensity") or 0.55 end,
		function(v) ATMOS.set("cloudDensity", v) end, 0, 1, "%.2f")
	mkSliderCard(pAtm, "Яркость", function() return ATMOS.get("cloudColor") or 0.9 end,
		function(v) ATMOS.set("cloudColor", v) end, 0, 1, "%.2f")
	mkSliderCard(pAtm, "Скорость", function() return ATMOS.get("cloudSpeed") or 0.5 end,
		function(v) ATMOS.set("cloudSpeed", v) end, 0, 2, "%.2f")

	mkSection(pAtm, "СВЕТИЛА")
	mkSliderCard(pAtm, "Размер солнца", function() return ATMOS.get("sunSize") or 350 end,
		function(v) ATMOS.set("sunSize", v) end, 80, 900, "%.0f")
	mkSliderCard(pAtm, "Яркость солнца", function() return ATMOS.get("sunBright") or 2 end,
		function(v) ATMOS.set("sunBright", v) end, 0, 6, "%.2f")
	mkSliderCard(pAtm, "Размер луны", function() return ATMOS.get("moonSize") or 450 end,
		function(v) ATMOS.set("moonSize", v) end, 80, 900, "%.0f")
	mkSliderCard(pAtm, "Яркость луны", function() return ATMOS.get("moonBright") or 1 end,
		function(v) ATMOS.set("moonBright", v) end, 0, 6, "%.2f")
	mkSliderCard(pAtm, "Диапазон солнца", function() return ATMOS.get("sunRange") or 60 end,
		function(v) ATMOS.set("sunRange", v) end, 10, 200, "%.0f")
	mkToggleCard(pAtm, "Текстура солнца", "", function() return ATMOS.get("sunTexOn") ~= false end,
		function(v) ATMOS.set("sunTexOn", v) end)
	mkInputCard(pAtm, "ID текстуры солнца", function() return ATMOS.get("sunTex") or "" end,
		function(v) ATMOS.set("sunTex", v) end)
	mkToggleCard(pAtm, "Текстура луны", "", function() return ATMOS.get("moonTexOn") ~= false end,
		function(v) ATMOS.set("moonTexOn", v) end)
	mkInputCard(pAtm, "ID текстуры луны", function() return ATMOS.get("moonTex") or "" end,
		function(v) ATMOS.set("moonTex", v) end)
	mkSliderCard(pAtm, "Размер текстуры", function() return ATMOS.get("texSize") or 512 end,
		function(v) ATMOS.set("texSize", v) end, 128, 1024, "%.0f")

	mkSection(pAtm, "СКАЙБОКС")
	mkToggleCard(pAtm, "Свой скайбокс", "", function() return ATMOS.get("skyOn") == true end,
		function(v) ATMOS.set("skyOn", v) end)
	mkInputCard(pAtm, "ID скайбокса (все 6 граней)", function() return ATMOS.get("skyTex") or "" end,
		function(v) ATMOS.set("skyTex", v) end)
	mkInfoCard(pAtm, "Свой ID вставь выше — применится на все грани, оригинал карты вернётся при выкл.")
	-- пресеты скайбоксов из assets.txt репы (id=название), фолбэк — вшитый список
	do
		local skyPresetURL = "https://raw.githubusercontent.com/druk1489/shaders-smaz/main/assets.txt"
		local skyFallback = {
			{"2846635652", "grass"},
			{"2886131957", "winter grass"},
			{"7108851308", "aesthetic sky"},
			{"911025794", "realistic night sky"},
			{"83244547123697", "day sky"},
			{"10256505900", "alt day sky"},
			{"591067775", "sunless blue skybox"},
			{"15502592084", "mega realstic sunset"},
			{"8202961731", "pink sky"},
			{"136055162054954", "scary red skybox"},
			{"4696746436", "black sky"},
			{"72835926026092", "anime style day sky"},
			{"12376964583", "rain sky"},
			{"324015877", "skybox with mountains"},
			{"14589496741", "city sky"},
		}
		local function skyUse(id)
			if not ATMOS then return end
			ATMOS.set("skyTex", "rbxassetid://" .. tostring(id))
			ATMOS.set("skyOn", true)
		end
		local skyPresets = {}
		pcall(function()
			local body = game:HttpGet(skyPresetURL, true)
			for line in tostring(body):gmatch("[^\r\n]+") do
				local id, name = line:match("^%s*(%d+)%s*=%s*(.+)%s*$")
				if id and name then skyPresets[#skyPresets + 1] = {id, name} end
			end
		end)
		if #skyPresets == 0 then skyPresets = skyFallback end
		for _, pr in ipairs(skyPresets) do
			local id, name = pr[1], pr[2]
			mkButtonCard(pAtm, name, function() skyUse(id) end)
		end
	end

	mkSection(pAtm, "РЕЗКОСТЬ / ЦИКЛ")
	mkToggleCard(pAtm, "Резкость (CC)", "", function() return ATMOS.get("sharpen") == true end,
		function(v) ATMOS.set("sharpen", v) end)
	mkSliderCard(pAtm, "Сила резкости", function() return ATMOS.get("sharpenAmt") or 0.2 end,
		function(v) ATMOS.set("sharpenAmt", v) end, 0, 1, "%.2f")
	mkSliderCard(pAtm, "Длительность дня (сек)", function() return ATMOS.get("dayLength") or 240 end,
		function(v) ATMOS.set("dayLength", v) end, 60, 3600, "%.0f")
else
	mkInfoCard(pAtm, "Слой Atmosphere не найден. Загрузи поле Atmosphere (атмосферу), либо используй автономный режим панели — СВЕТ и ПОСТ FX работают напрямую.")
end

--==========================================================
-- ВКЛАДКА: ПОГОДА
--==========================================================
local pWeather = mkTab("ПОГОДА", "АТМОСФЕРА")
if ATMOS then
	mkSection(pWeather, "ПОГОДА СЕЙЧАС")
	mkButtonCard(pWeather, "☀  Ясно", function() ATMOS.weather.set("none") end)
	mkButtonCard(pWeather, "🌧  Дождь", function() ATMOS.weather.set("rain") end)
	mkButtonCard(pWeather, "❄  Снег", function() ATMOS.weather.set("snow") end)
	mkButtonCard(pWeather, "🌨  Град", function() ATMOS.weather.set("hail") end)
	mkSliderCard(pWeather, "Интенсивность", function() return ATMOS.get("weatherIntensity") or 0.6 end,
		function(v) ATMOS.weather.setIntensity(v) end, 0, 1, "%.2f")
	local wCard = mkCard(pWeather, 40)
	local wLab = Instance.new("TextLabel")
	wLab.Size = UDim2.new(1, -20, 1, 0)
	wLab.Position = UDim2.fromOffset(14, 0)
	wLab.BackgroundTransparency = 1
	wLab.Text = "Сейчас: " .. tostring(ATMOS.get("weather") or "none")
	wLab.TextColor3 = Color3.fromRGB(255, 255, 255)
	wLab.Font = Enum.Font.SourceSansBold
	wLab.TextSize = 14
	wLab.TextXAlignment = Enum.TextXAlignment.Left
	wLab.Parent = wCard
	regRefresh(pWeather, function()
		wLab.Text = "Сейчас: " .. tostring(ATMOS.get("weather") or "none")
	end)

	mkSection(pWeather, "АВТО-ЦИКЛ ПОГОДЫ")
	mkToggleCard(pWeather, "Авто-цикл", "Ясно → Дождь → Снег → Град", function() return wCyc.on end,
		function(v) wCyc.on = v end)
	mkSliderCard(pWeather, "Интервал (сек)", function() return wCyc.every end,
		function(v) wCyc.every = math.max(3, v) end, 3, 120, "%.0f")
else
	mkInfoCard(pWeather, "Погода управляется через слой Atmosphere. Слой не найден.")
end

--==========================================================
-- ВКЛАДКА: ЭФФЕКТЫ (модули SMAZ)
--==========================================================
local pMod = mkTab("ЭФФЕКТЫ", "МОДУЛИ")

mkSection(pMod, "МОЛНИИ")
if LG then
	mkButtonCard(pMod, "⚡ Ударить сейчас", function() pcall(LG.strike) end, ACCENT)
	mkToggleCard(pMod, "Авто-молнии", "", function() return pcall(LG.isAuto) and LG.isAuto() or false end,
		function(v) pcall(LG.setAuto, v) end)
else
	mkInfoCard(pMod, "Молнии недоступны (нет модуля).")
end

mkSection(pMod, "ТОРНАДО")
if TN then
	mkButtonCard(pMod, "🌪 Создать рядом", function() pcall(TN.spawnNear) end, ACCENT)
	mkButtonCard(pMod, "🌪 Случайно", function() pcall(TN.spawnRandom) end)
	mkButtonCard(pMod, "✕ Убить все", function() pcall(TN.killAll) end, DANGER)
	mkToggleCard(pMod, "Авто-спавн", "", function() return pcall(TN.isAutoSpawn) and TN.isAutoSpawn() or false end,
		function(v) pcall(TN.setAutoSpawn, v) end)
	do
		local efBtn = mkButtonCard(pMod, "Сила EF: 0  [цикл]", function()
			pcall(function() TN.setEF((TN.getEF() + 1) % 6) end)
		end)
		local efCard = efBtn.Parent
		regRefresh(pMod, function()
			local ok, n = pcall(TN.getEF)
			local _, cnt = pcall(TN.count)
			efBtn.Text = "Сила EF: " .. tostring(ok and n or 0) .. "  (всего: " .. tostring(cnt or 0) .. ")  [цикл]"
		end)
	end
else
	mkInfoCard(pMod, "Торнадо недоступно (нет модуля).")
end

mkSection(pMod, "ДОЖДЬ (МОДУЛЬ)")
if RN then
	mkToggleCard(pMod, "Дождь", "", function() return pcall(RN.isEnabled) and RN.isEnabled() or false end,
		function(v) pcall(RN.setEnabled, v) end)
	mkToggleCard(pMod, "3D капли", "", function() return pcall(RN.isRain3D) and RN.isRain3D() or false end,
		function(v) pcall(RN.setRain3D, v) end)
	mkToggleCard(pMod, "Капли на экране", "", function() return pcall(RN.isScreenDrops) and RN.isScreenDrops() or false end,
		function(v) pcall(RN.setScreenDrops, v) end)
else
	mkInfoCard(pMod, "Дождь (модуль) недоступен.")
end

mkSection(pMod, "ОТРАЖЕНИЯ")
if RF then
	mkToggleCard(pMod, "Отражения", "", function() return pcall(RF.isEnabled) and RF.isEnabled() or false end,
		function(v) pcall(RF.setEnabled, v) end)
	mkToggleCard(pMod, "Клонировать персонажа", "", function() return pcall(RF.isCloneCharacter) and RF.isCloneCharacter() or false end,
		function(v) pcall(RF.setCloneCharacter, v) end)
	mkButtonCard(pMod, "Пересобрать клоны", function() pcall(RF.rebuild) end)
	mkSliderCard(pMod, "Радиус", function() return pcall(RF.getRadius) and RF.getRadius() or 64 end,
		function(v) pcall(RF.setRadius, v) end, 8, 120, "%.0f")
	mkSliderCard(pMod, "Прозрачность (x100)", function()
		local ok, v = pcall(RF.getBaseTransparency)
		return ok and v and math.floor(v * 100) or 0
	end, function(v) pcall(RF.setBaseTransparency, v / 100) end, 0, 90, "%.0f")
	mkSection(pMod, "ОТРАЖЕНИЯ-ЛАЙТ (PBR, видно везде)")
	mkToggleCard(pMod, "Shine (блики/металл)", "", function() return ATMOS and ATMOS.get("shine") == true or false end,
		function(v) if ATMOS then ATMOS.set("shine", v) end end)
	mkSliderCard(pMod, "Сила shine", function() return ATMOS and ATMOS.get("shineStrength") or 0.35 end,
		function(v) if ATMOS then ATMOS.set("shineStrength", v) end end, 0, 1, "%.2f")
	mkToggleCard(pMod, "Зеркальная вода", "", function() return ATMOS and ATMOS.get("waterMirror") == true or false end,
		function(v) if ATMOS then ATMOS.set("waterMirror", v) end end)
	mkInfoCard(pMod, "Планарные клоны выше видно только на стекле/воде (под обычным полом их скрывает глубина). Shine виден везде и почти ничего не стоит.")
else
	mkInfoCard(pMod, "Отражения недоступны (нет модуля).")
end

--==========================================================
-- ВКЛАДКА: ПРЕСЕТЫ
--==========================================================
local pPres = mkTab("ПРЕСЕТЫ", "МОДУЛИ")
if PR then
	local list = pcall(function() return PR.list() end) and PR.list() or {}
	for i, name in ipairs(list) do
		local pretty = pcall(function() return PR.pretty(name) end) and PR.pretty(name) or name
		mkButtonCard(pPres, pretty, function()
			pcall(function() PR.apply(name) end)
		end, (i % 2 == 0) and Color3.fromRGB(180, 180, 255) or defaultColor)
	end
	mkButtonCard(pPres, "⏮ Сброс к нейтральному", function() pcall(function() PR.reset() end) end, DANGER)
	mkButtonCard(pPres, "Современный рендер", function() pcall(function() PR.futureLighting() end) end, ACCENT)
else
	mkInfoCard(pPres, "Пресеты недоступны (нет модуля).")
end

--==========================================================
-- ВКЛАДКА: НАСТРОЙКИ
--==========================================================
local pSet = mkTab("НАСТРОЙКИ", "МОДУЛИ")

mkSection(pSet, "ПАНЕЛЬ")
local bindHandle = mkKeybindCard(pSet, "Клавиша показа/скрытия", menuBindKey, function(key)
	menuBindKey = key
end)

mkSection(pSet, "СОХРАНЕНИЕ НАСТРОЕК")
local HttpService = game:GetService("HttpService")
local savePath = "smaз_settings_" .. tostring(game.PlaceId) .. ".json"
local function copyInto(dst, src)
	for k, v in pairs(src) do dst[k] = v end
end
local function sanitize(t, out)
	out = out or {}
	for k, v in pairs(t) do
		if typeof(v) == "Color3" then
			out[k] = { r = v.R, g = v.G, b = v.B }
		elseif typeof(v) == "Vector3" then
			out[k] = { x = v.X, y = v.Y, z = v.Z }
		elseif typeof(v) == "table" then
			local sub = {}
			sanitize(v, sub)
			out[k] = sub
		elseif typeof(v) == "number" or typeof(v) == "string" or typeof(v) == "boolean" then
			out[k] = v
		end
	end
	return out
end
local function rehydrate(t)
	for k, v in pairs(t) do
		if typeof(v) == "table" then
			if v.r and v.g and v.b and typeof(v.r) == "number" and typeof(v.g) == "number" and typeof(v.b) == "number" then
				t[k] = Color3.new(v.r, v.g, v.b)
			elseif v.x and v.y and v.z and typeof(v.x) == "number" and typeof(v.y) == "number" and typeof(v.z) == "number" then
				t[k] = Vector3.new(v.x, v.y, v.z)
			else
				rehydrate(v)
			end
		end
	end
end
local function settingsSnapshot()
	local t = {
		panel = {
			uiFx = uiFx, wCyc = wCyc, camFov = camFov, camBreath = camBreath, menuBindKey = menuBindKey,
		},
	}
	if ATMOS then
		t.atmos = {}
		for k, v in pairs(ATMOS.settings) do t.atmos[k] = v end
	end
	if RN and RN.CFG then t.rain = RN.CFG end
	if TN and TN.CFG then t.tornado = TN.CFG end
	if LG and LG.CFG then t.lightning = LG.CFG end
	if RF and RF.CFG then t.refl = RF.CFG end
	if PR and PR.Values then
		t.preset = {}
		for k, v in pairs(PR.Values) do t.preset[k] = v end
	end
	return t
end
local function doSave()
	local okJson, json = pcall(HttpService.JSONEncode, HttpService, sanitize(settingsSnapshot()))
	if not okJson then return false end
	local okWrite = pcall(function()
		if isfile and typeof(isfile) == "function" then
			if isfile(savePath) then delfile(savePath) end
			writefile(savePath, json)
		elseif game:GetService("Players").LocalPlayer:IsInStudio() then
			warn("[SMAZ] setclipboard(JSON): " .. json)
		else
			setclipboard(json)
		end
	end)
	return okWrite
end
local function doLoad()
	if not (readfile and typeof(readfile) == "function") then return false end
	if not (isfile and typeof(isfile) == "function") or not isfile(savePath) then return false end
	local json = readfile(savePath)
	local ok, t = pcall(HttpService.JSONDecode, HttpService, json)
	if not ok or typeof(t) ~= "table" then return false end
	rehydrate(t)
	if t.atmos and ATMOS then
		for k, v in pairs(t.atmos) do
			if type(k) == "string" and ATMOS.settings[k] ~= nil then
				pcall(function() ATMOS.set(k, v) end)
			end
		end
	end
	if t.rain and RN and RN.CFG then copyInto(RN.CFG, t.rain); if RN.setEnabled then RN.setEnabled(RN.CFG.enabled) end end
	if t.tornado and TN and TN.CFG then copyInto(TN.CFG, t.tornado) end
	if t.lightning and LG and LG.CFG then copyInto(LG.CFG, t.lightning); if LG.setAuto then LG.setAuto(LG.CFG.autoOn) end end
	if t.refl and RF and RF.CFG then copyInto(RF.CFG, t.refl); if RF.rebuild then RF.rebuild() end end
	if t.preset and PR and PR.Values then
		for k, v in pairs(t.preset) do
			if PR.Values[k] ~= nil then PR.Values[k] = v end
		end
		if PR.commit then PR.commit() end
	end
	if t.panel then
		if t.panel.uiFx then copyInto(uiFx, t.panel.uiFx) end
		if t.panel.wCyc then copyInto(wCyc, t.panel.wCyc) end
		if t.panel.camFov then copyInto(camFov, t.panel.camFov) end
		if t.panel.camBreath then copyInto(camBreath, t.panel.camBreath) end
		if t.panel.menuBindKey then menuBindKey = t.panel.menuBindKey end
	end
	return true
end
local saveBtn = mkButtonCard(pSet, "💾 Сохранить настройки", function()
	pcall(function()
		StarterGui:SetCore("SendNotification", {Title="SMAZ", Text="Настройки сохранены: " .. savePath, Duration=3})
	end)
end, OK)
local savedOk = pcall(doSave)
local loadBtn = mkButtonCard(pSet, "📂 Загрузить настройки", function()
	local loaded = pcall(doLoad)
	pcall(function()
		StarterGui:SetCore("SendNotification", {Title="SMAZ", Text=loaded and "Настройки загружены ✓" or "Файл не найден или ошибка", Duration=3})
	end)
end)
mkInfoCard(pSet, "Файл: " .. savePath .. ". Без save-функции (напр. синх-экзекутор) настройки не сохранятся.")

mkSection(pSet, "ИНФО")
mkInfoCard(pSet, "Хоткеи: " .. tostring(menuBindKey) .. " — показать/скрыть панель; X — спрятать ВСЕ гуи (ещё раз — показать); Shift+P (в атмосфере) — фрикам.")
mkInfoCard(pSet, "СВЕТ и ПОСТ FX пишут напрямую в Lighting и эффекты. При наличии слоя Atmosphere часть параметров (яркость, bloom, лучи, блюр) идёт через него. Всё в одном проксирующем GUI в стиле Silent Engine UI.")

--==========================================================
-- ДВИЖОК UI-ЭФФЕКТОВ: зерно, виньетка, автофокус DoF,
-- дыхание камеры, авто-цикл погоды
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
			-- ФИКС: свой персонаж в игноре, иначе фокус прилипает к затылку при ходьбе
			local excl = { cam }
			pcall(function()
				local lp = game:GetService("Players").LocalPlayer
				local ch = lp and lp.Character or nil
				if ch then excl[#excl + 1] = ch end
			end)
			prm.FilterDescendantsInstances = excl
			prm.IgnoreWater = true
			local hit = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * 600, prm)
			local d = hit and hit.Distance or 600
			if d < 12 then d = 600 end -- всё равно задел своё -> небо
			pcall(function()
				local cur = dofFx.FocusDistance
				if typeof(cur) ~= "number" then cur = d end
				dofFx.FocusDistance = cur + (d - cur) * 0.2 -- сглаживание, без рывков
			end)
		end
	end
	if camBreath.on then
		local cam = workspace.CurrentCamera
		if cam then
			local target = camFov.manual + camBreath.amp * math.sin(tick() * camBreath.speed)
			local cur = cam.FieldOfView
			-- детект войны за FOV: игра вернула своё мимо нашего значения
			if camBreath._last ~= nil and camBreath.amp > 0 and math.abs(cur - camBreath._last) > 1.5 then
				camBreath._fight = (camBreath._fight or 0) + 1
				if camBreath._fight >= 30 then
					camBreath.on = false -- игра держит FOV каждый кадр: выключаемся, вакханалии не будет
					camBreath._fight = 0
					pcall(function()
						game:GetService("StarterGui"):SetCore("SendNotification", {Title="SMAZ FOV", Text="Игра держит свой FOV — дыхание выкл.", Duration=5})
					end)
				end
			else
				camBreath._fight = 0
			end
			if camBreath.on then
				pcall(function() cam.FieldOfView = target end)
				camBreath._last = target
			end
		end
	end
end)

task.spawn(function()
	local acc = 0
	while screenGui and screenGui.Parent do
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
-- ОБНОВЛЕНИЕ ВИДЖЕТОВ ПО КРУГУ + ХОТКЕИ + ДРАГ
--==========================================================
selectTab(TABS[1])

task.spawn(function()
	while screenGui and screenGui.Parent do
		for page, list in pairs(refreshers) do
			if page and page.Visible then
				for _, fn in ipairs(list) do
					pcall(fn)
				end
			end
		end
		task.wait(0.35)
	end
end)

UIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	if activeKeybindBtn then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	if os.clock() - lastCaptureClock < 0.2 then return end
	if input.KeyCode.Name == menuBindKey then
		main.Visible = not main.Visible
	end
end)

-- X: спрятать ВСЕ GUI (все ScreenGui, что мы создали + core)
local allGuiHidden = false
local hiddenGuis = {}
local function collectGui(parent, out)
	for _, g in ipairs(parent:GetChildren()) do
		if g:IsA("ScreenGui") then
			if g.Name:find("SMAZ", 1, true) or g.Name:find("Atmos", 1, true)
			or g.Name:find("RainV11", 1, true) or g.Name:find("LightningV12", 1, true)
			or g.Name:find("__AtmosFlash", 1, true) or g.Name == "SMAZ_ControlPanel" then
				if g.Enabled then table.insert(out, g); g.Enabled = false end
			end
		end
	end
end
local function toggleAllGui()
	allGuiHidden = not allGuiHidden
	if allGuiHidden then
		hiddenGuis = {}
		pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)
		UserInputService.MouseIconEnabled = false
		collectGui(pgui, hiddenGuis)
		local coreParent = game:GetService("CoreGui")
		if coreParent then collectGui(coreParent, hiddenGuis) end
	else
		pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true) end)
		UserInputService.MouseIconEnabled = true
		for _, g in ipairs(hiddenGuis) do
			if g and g.Parent and g:IsA("ScreenGui") then g.Enabled = true end
		end
		hiddenGuis = {}
	end
end
UIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	if activeKeybindBtn then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	if input.KeyCode == Enum.KeyCode.X then
		toggleAllGui()
	end
end)

local dragging = false
local dragStart, startPos
topBar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		if sliderDragging then return end
		dragging = true
		dragStart = input.Position
		startPos = main.Position
	end
end)
topBar.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)
UIS.InputChanged:Connect(function(input)
	if dragging and not sliderDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local delta = input.Position - dragStart
		main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
	end
end)
UIS.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		sliderDragging = false
	end
end)

print("[SMAZ Studio v6] Panel (Silent Engine UI) loaded" .. (ATMOS and " (atmos API)" or " (standalone)"))
