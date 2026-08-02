-- Rain v13 - no hotkeys, exposes SMAZ_RAIN API for control panel

if getgenv and getgenv().__RAIN_V11_LOADED then
	if getgenv().__RAIN_V11_UNLOAD then pcall(getgenv().__RAIN_V11_UNLOAD) end
end
if getgenv then getgenv().__RAIN_V11_LOADED = true end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local RAIN_TEX = "rbxassetid://202975952"
local DROPS_TEX = "rbxassetid://8940172292"

local CFG = {
	enabled = true, rain3D = true, screenDrops = true,
	numEmitters = 6, emitterHeight = 55, emitterSpread = 25,
	ratePerEmitter = 2200,
	lifetime = {0.35, 0.7}, speed = {180, 250},
	dropSize = 0.7, opacity = 0.08,
	maxDrops = 45, dropSizeMin = 60, dropSizeMax = 170,
	dropLifeMin = 0.9, dropLifeMax = 2.2, dropDriftPx = 32,
	centerAlpha = 0.97, edgeAlpha = 0.12, raycastInterval = 0.3,
}

local prev = Workspace:FindFirstChild("_RainV11_Root")
if prev then prev:Destroy() end
local root = Instance.new("Folder"); root.Name = "_RainV11_Root"; root.Parent = Workspace

local emitters = {}
for i = 1, CFG.numEmitters do
	local part = Instance.new("Part")
	part.Size = Vector3.new(70, 2, 70); part.Transparency = 1
	part.Anchored = true; part.CanCollide = false; part.CanQuery = false; part.CanTouch = false
	part.Massless = true; part.CastShadow = false; part.Parent = root
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = RAIN_TEX
	pe.Rate = CFG.ratePerEmitter
	pe.Lifetime = NumberRange.new(CFG.lifetime[1], CFG.lifetime[2])
	pe.Speed = NumberRange.new(CFG.speed[1], CFG.speed[2])
	pe.SpreadAngle = Vector2.new(4, 4)
	pe.Acceleration = Vector3.new(0, -90, 0)
	pe.EmissionDirection = Enum.NormalId.Bottom
	pe.Size = NumberSequence.new(CFG.dropSize)
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, CFG.opacity),
		NumberSequenceKeypoint.new(0.85, CFG.opacity),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Color = ColorSequence.new(Color3.fromRGB(215, 222, 235))
	pe.LightEmission = 0.15; pe.LightInfluence = 0.4; pe.LockedToPart = false
	pcall(function() pe.Orientation = Enum.ParticleOrientation.VelocityParallel end)
	pe.Parent = part
	local angle = (i - 1) / CFG.numEmitters * math.pi * 2
	table.insert(emitters, {part = part, pe = pe, angle = angle})
end

local function waitPGui() return player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 5) end
local pgui = waitPGui()
local screenGui; local screenDrops = {}

local function alphaFor(nx, ny)
	local r = math.min(1, math.sqrt(nx*nx + ny*ny) / math.sqrt(2))
	return CFG.centerAlpha + (CFG.edgeAlpha - CFG.centerAlpha) * (r ^ 1.5)
end

local function respawnDrop(d)
	local vp = camera.ViewportSize
	local w, h = vp.X, vp.Y
	if w < 100 then return end
	local size = math.random(CFG.dropSizeMin, CFG.dropSizeMax)
	local x = math.random(0, math.max(1, w - size))
	local y = math.random(0, math.max(1, h - size))
	local nx = (x + size*0.5 - w*0.5) / (w*0.5)
	local ny = (y + size*0.5 - h*0.5) / (h*0.5)
	d.baseAlpha = alphaFor(nx, ny)
	d.initX = x; d.initY = y
	d.img.Position = UDim2.new(0, x, 0, y)
	d.img.Size = UDim2.new(0, size, 0, size)
	d.img.ImageTransparency = 1
	d.img.Rotation = math.random(-25, 25)
	d.timer = 0
	d.lifetime = math.random() * (CFG.dropLifeMax - CFG.dropLifeMin) + CFG.dropLifeMin
	d.started = true
end

local function buildScreenGui()
	if not pgui then return end
	if screenGui then screenGui:Destroy() end
	screenDrops = {}
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "RainV11_Drops"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 100
	screenGui.Parent = pgui
	for i = 1, CFG.maxDrops do
		local img = Instance.new("ImageLabel")
		img.Name = "d" .. i; img.BackgroundTransparency = 1
		img.Image = DROPS_TEX; img.ImageTransparency = 1
		img.Active = false; img.Selectable = false
		img.ScaleType = Enum.ScaleType.Fit
		img.ImageColor3 = Color3.fromRGB(225, 232, 245)
		img.Parent = screenGui
		table.insert(screenDrops, {img = img, baseAlpha = 0.5, timer = -math.random() * 1.5, lifetime = 1, initX = 0, initY = 0, started = false})
	end
end
buildScreenGui()

local playerBlocked = false
local rayAcc = 0
local function updateRay(dt)
	rayAcc = rayAcc + dt
	if rayAcc < CFG.raycastInterval then return end
	rayAcc = 0
	local ch = player.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	if not hrp then playerBlocked = true; return end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = {ch, root, screenGui}
	local hit = Workspace:Raycast(hrp.Position + Vector3.new(0, 3, 0), Vector3.new(0, 600, 0), rp)
	playerBlocked = hit ~= nil
end

local function updateEmitters()
	local ch = player.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	local pos = hrp and hrp.Position or Vector3.new(0, 5, 0)
	for _, e in ipairs(emitters) do
		local px = pos.X + math.cos(e.angle) * CFG.emitterSpread
		local pz = pos.Z + math.sin(e.angle) * CFG.emitterSpread
		e.part.CFrame = CFrame.new(px, pos.Y + CFG.emitterHeight, pz)
		e.pe.Enabled = CFG.rain3D and CFG.enabled and not playerBlocked
	end
end

local function updateDrops(dt)
	for _, d in ipairs(screenDrops) do
		if playerBlocked or not CFG.screenDrops or not CFG.enabled then
			if d.img.ImageTransparency < 1 then
				d.img.ImageTransparency = math.min(1, d.img.ImageTransparency + dt * 3)
			end
			d.started = false; d.timer = -math.random() * 1
		else
			d.timer = d.timer + dt
			if d.timer >= 0 then
				if not d.started then respawnDrop(d)
				else
					local t = d.timer / d.lifetime
					if t >= 1 then respawnDrop(d)
					else
						local a
						if t < 0.15 then a = 1 + (d.baseAlpha - 1) * (t / 0.15)
						elseif t > 0.75 then a = d.baseAlpha + (1 - d.baseAlpha) * ((t - 0.75) / 0.25)
						else a = d.baseAlpha end
						d.img.ImageTransparency = a
						d.img.Position = UDim2.new(0, d.initX, 0, d.initY + t * CFG.dropDriftPx)
					end
				end
			end
		end
	end
end

local hbConn = RunService.Heartbeat:Connect(function(dt)
	if dt > 0.1 then dt = 0.1 end
	pcall(updateRay, dt); pcall(updateEmitters); pcall(updateDrops, dt)
end)

local vpConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
	for _, d in ipairs(screenDrops) do d.started = false; d.timer = -math.random()*0.5 end
end)

local charConn = player.CharacterAdded:Connect(function()
	task.wait(0.5); pgui = waitPGui(); buildScreenGui()
end)

if getgenv then
	getgenv().SMAZ_RAIN = {
		CFG = CFG,
		setEnabled = function(v) CFG.enabled = v end,
		setRain3D = function(v) CFG.rain3D = v end,
		setScreenDrops = function(v) CFG.screenDrops = v end,
		isEnabled = function() return CFG.enabled end,
		isRain3D = function() return CFG.rain3D end,
		isScreenDrops = function() return CFG.screenDrops end,
	}
	getgenv().__RAIN_V11_UNLOAD = function()
		hbConn:Disconnect(); vpConn:Disconnect(); charConn:Disconnect()
		if screenGui then screenGui:Destroy() end
		if root then root:Destroy() end
		getgenv().__RAIN_V11_LOADED = nil; getgenv().__RAIN_V11_UNLOAD = nil
		getgenv().SMAZ_RAIN = nil
	end
end

print("[Rain v13] Loaded, API: getgenv().SMAZ_RAIN")
