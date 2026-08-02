--==============================================================
-- RAIN ENGINE v11
--   • 3D дождь вокруг игрока (Rain-Texture 202975952)
--   • Капли на экране (rain-drops 8940172292)
--   • Raycast вверх: если есть блок над игроком — дождь выкл (и в 3D и на экране)
--   • On-screen капли не блокируют мышь (Active=false)
--   • Прозрачность: в центре экрана почти прозрачные, по краям видимы
--
-- Hotkeys:
--   Правая скобка ]  — toggle весь дождь
--   Shift+]              — toggle только экранные капли
--   Ctrl+]               — toggle только 3D дождь
--==============================================================

if getgenv and getgenv().__RAIN_V11_LOADED then
	warn("[Rain v11] уже загружен, перезагружаю")
	if getgenv().__RAIN_V11_UNLOAD then pcall(getgenv().__RAIN_V11_UNLOAD) end
end
if getgenv then getgenv().__RAIN_V11_LOADED = true end

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local Workspace  = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- ================== ASSETS ==================
local ASSET = {
	RainTex  = "rbxassetid://202975952",
	DropsTex = "rbxassetid://8940172292",
}

-- ================== CONFIG ==================
local CFG = {
	-- 3D rain
	rain3DEnabled   = true,
	rainRate        = 900,
	rainHeight      = 100,
	rainArea        = 220,
	rainSpeed       = 220,
	rainDropSize    = 0.55,
	rainOpacity     = 0.15,     -- lower = more visible

	-- On-screen drops
	screenDropsEnabled = true,
	maxDrops        = 26,
	dropSizeMin     = 55,
	dropSizeMax     = 130,
	dropLifeMin     = 1.2,
	dropLifeMax     = 2.6,
	dropDriftPx     = 22,
	centerAlpha     = 0.96,   -- ваше требование: в центре почти невидно
	edgeAlpha       = 0.18,   -- по краям видно

	-- Shared
	raycastInterval = 0.35,
	enabled         = true,
}

-- ================== CONTAINER ==================
local prev = Workspace:FindFirstChild("_RainV11_Root")
if prev then prev:Destroy() end
local root = Instance.new("Folder")
root.Name = "_RainV11_Root"
root.Parent = Workspace

-- ================== 3D RAIN EMITTER ==================
local rainPart = Instance.new("Part")
rainPart.Name = "Rain3D_Emitter"
rainPart.Size = Vector3.new(CFG.rainArea, 2, CFG.rainArea)
rainPart.Transparency = 1
rainPart.Anchored = true
rainPart.CanCollide = false
rainPart.CanQuery = false
rainPart.CanTouch = false
rainPart.Massless = true
rainPart.CastShadow = false
rainPart.Parent = root

local rainEmitter = Instance.new("ParticleEmitter")
rainEmitter.Texture = ASSET.RainTex
rainEmitter.Rate = CFG.rainRate
rainEmitter.Lifetime = NumberRange.new(0.4, 0.7)
rainEmitter.Speed = NumberRange.new(CFG.rainSpeed * 0.95, CFG.rainSpeed * 1.1)
rainEmitter.SpreadAngle = Vector2.new(3, 3)
rainEmitter.Acceleration = Vector3.new(0, -80, 0)
rainEmitter.EmissionDirection = Enum.NormalId.Bottom
rainEmitter.Rotation = NumberRange.new(0, 0)
rainEmitter.RotSpeed = NumberRange.new(0, 0)
rainEmitter.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, CFG.rainDropSize),
	NumberSequenceKeypoint.new(1, CFG.rainDropSize),
})
rainEmitter.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0,   CFG.rainOpacity),
	NumberSequenceKeypoint.new(0.85, CFG.rainOpacity),
	NumberSequenceKeypoint.new(1,   1),
})
rainEmitter.Color = ColorSequence.new(Color3.fromRGB(210, 218, 230))
rainEmitter.LightEmission = 0.12
rainEmitter.LightInfluence = 0.5
rainEmitter.LockedToPart = false
-- Вытягиваем текстуру вдоль вектора скорости — полосы капель
-- (в новых Roblox: Orientation.VelocityParallel; в старых fallback — pcall)
pcall(function()
	rainEmitter.Orientation = Enum.ParticleOrientation.VelocityParallel
end)
pcall(function()
	rainEmitter.SpreadAngle = Vector2.new(3, 3)
end)
rainEmitter.Parent = rainPart

-- ================== ON-SCREEN DROPS ==================
local function waitForPGui()
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then
		pg = player:WaitForChild("PlayerGui", 5)
	end
	return pg
end

local pgui = waitForPGui()
local screenGui
local screenDrops = {}

local function rebuildScreenGui()
	if not pgui then return end
	if screenGui then screenGui:Destroy() end
	screenDrops = {}
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "RainV11_ScreenDrops"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = -5
	screenGui.Parent = pgui

	for i = 1, CFG.maxDrops do
		local img = Instance.new("ImageLabel")
		img.Name = "Drop_" .. i
		img.BackgroundTransparency = 1
		img.Image = ASSET.DropsTex
		img.ImageTransparency = 1
		img.Active = false           -- НЕ блокирует мышь
		img.Selectable = false
		img.ZIndex = 1
		img.ScaleType = Enum.ScaleType.Fit
		img.Parent = screenGui

		local data = {
			img = img,
			baseAlpha = 0.5,
			timer = -math.random() * 1.5,   -- разброс стартовых времён
			lifetime = 1,
			initX = 0,
			initY = 0,
			started = false,
		}
		table.insert(screenDrops, data)
	end
end

local function alphaForNormPos(nx, ny)
	local r = math.min(1, math.sqrt(nx * nx + ny * ny) / math.sqrt(2))
	-- ease: r^1.5 — края ярче выражены
	local e = r ^ 1.4
	return CFG.centerAlpha + (CFG.edgeAlpha - CFG.centerAlpha) * e
end

local function respawnDrop(data)
	local vp = camera.ViewportSize
	local w, h = vp.X, vp.Y
	if w < 100 or h < 100 then return end
	local size = math.random(CFG.dropSizeMin, CFG.dropSizeMax)
	local x = math.random(0, math.max(1, w - size))
	local y = math.random(0, math.max(1, h - size))
	local cx = x + size * 0.5
	local cy = y + size * 0.5
	local nx = (cx - w * 0.5) / (w * 0.5)
	local ny = (cy - h * 0.5) / (h * 0.5)
	data.baseAlpha = alphaForNormPos(nx, ny)
	data.initX = x
	data.initY = y
	data.img.Position = UDim2.new(0, x, 0, y)
	data.img.Size = UDim2.new(0, size, 0, size)
	data.img.ImageTransparency = 1
	data.img.Rotation = math.random(-25, 25)
	data.timer = 0
	data.lifetime = math.random() * (CFG.dropLifeMax - CFG.dropLifeMin) + CFG.dropLifeMin
	data.started = true
end

local function updateDrop(data, dt, blocked)
	if blocked or not CFG.screenDropsEnabled or not CFG.enabled then
		-- Затухаем и не возрождаемся
		if data.img.ImageTransparency < 1 then
			data.img.ImageTransparency = math.min(1, data.img.ImageTransparency + dt * 2.5)
		end
		data.timer = -math.random() * 1.2   -- когда включат — спавнятся не сразу все
		data.started = false
		return
	end
	data.timer = data.timer + dt
	if data.timer < 0 then return end
	if not data.started then respawnDrop(data); return end
	local t = data.timer / data.lifetime
	if t >= 1 then respawnDrop(data); return end
	local a
	if t < 0.15 then
		a = 1 + (data.baseAlpha - 1) * (t / 0.15)
	elseif t > 0.75 then
		a = data.baseAlpha + (1 - data.baseAlpha) * ((t - 0.75) / 0.25)
	else
		a = data.baseAlpha
	end
	data.img.ImageTransparency = a
	local drift = t * CFG.dropDriftPx
	data.img.Position = UDim2.new(0, data.initX, 0, data.initY + drift)
end

rebuildScreenGui()

-- ================== RAYCAST BLOCK CHECK ==================
local playerBlocked = false
local raycastAcc = 0
local function updateRaycast(dt)
	raycastAcc = raycastAcc + dt
	if raycastAcc < CFG.raycastInterval then return end
	raycastAcc = 0
	local ch = player.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	if not hrp then playerBlocked = true; return end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = {ch, root, screenGui}
	local hit = Workspace:Raycast(hrp.Position + Vector3.new(0, 3, 0), Vector3.new(0, 600, 0), rp)
	playerBlocked = hit ~= nil
end

-- ================== POSITION UPDATE ==================
local function updateRainPos()
	local ch = player.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	if hrp then
		rainPart.CFrame = CFrame.new(hrp.Position + Vector3.new(0, CFG.rainHeight, 0))
	end
	rainEmitter.Enabled = CFG.rain3DEnabled and CFG.enabled and not playerBlocked
end

-- ================== MAIN LOOP ==================
local hbConn = RunService.Heartbeat:Connect(function(dt)
	if dt > 0.1 then dt = 0.1 end
	pcall(updateRaycast, dt)
	pcall(updateRainPos)
	if screenGui then
		for _, d in ipairs(screenDrops) do
			pcall(updateDrop, d, dt, playerBlocked)
		end
	end
end)

-- ================== VIEWPORT RESIZE ==================
local vpConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
	-- При изменении разрешения — переспавним капли
	for _, d in ipairs(screenDrops) do
		d.started = false
		d.timer = -math.random() * 1
	end
end)

-- ================== CHARACTER RESPAWN ==================
local charConn = player.CharacterAdded:Connect(function()
	task.wait(0.5)
	pgui = waitForPGui()
	rebuildScreenGui()
end)

-- ================== HOTKEYS ==================
local inputConn = UIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.RightBracket then
		local shift = UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)
		local ctrl  = UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)
		if shift then
			CFG.screenDropsEnabled = not CFG.screenDropsEnabled
			pcall(function()
				StarterGui:SetCore("SendNotification", {
					Title = "Rain v11",
					Text = "Screen drops: " .. (CFG.screenDropsEnabled and "ON" or "OFF"),
					Duration = 2,
				})
			end)
		elseif ctrl then
			CFG.rain3DEnabled = not CFG.rain3DEnabled
			pcall(function()
				StarterGui:SetCore("SendNotification", {
					Title = "Rain v11",
					Text = "3D rain: " .. (CFG.rain3DEnabled and "ON" or "OFF"),
					Duration = 2,
				})
			end)
		else
			CFG.enabled = not CFG.enabled
			pcall(function()
				StarterGui:SetCore("SendNotification", {
					Title = "Rain v11",
					Text = "Rain: " .. (CFG.enabled and "ON" or "OFF"),
					Duration = 2,
				})
			end)
		end
	end
end)

-- ================== UNLOAD ==================
if getgenv then
	getgenv().__RAIN_V11_UNLOAD = function()
		if hbConn then hbConn:Disconnect() end
		if vpConn then vpConn:Disconnect() end
		if charConn then charConn:Disconnect() end
		if inputConn then inputConn:Disconnect() end
		if screenGui then screenGui:Destroy() end
		if root then root:Destroy() end
		getgenv().__RAIN_V11_LOADED = nil
		getgenv().__RAIN_V11_UNLOAD = nil
	end
end

pcall(function()
	StarterGui:SetCore("SendNotification", {
		Title = "Rain v11",
		Text = "] toggle, Shift+] = экранные, Ctrl+] = 3D",
		Duration = 5,
	})
end)

print("[Rain v11] Loaded. ] toggle rain, Shift+] screen drops, Ctrl+] 3D only")
