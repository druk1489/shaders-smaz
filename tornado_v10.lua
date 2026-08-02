--==============================================================
-- TORNADO ENGINE v10 — Multi-tornado visual simulation
-- • Rankine combined vortex math (solid core + potential outer)
-- • Random spawn / drift on ground / merge / split / rope-out
-- • Multiple tornadoes simultaneously
-- • Uses store textures:
--     Tornado-particle 3318493519
--     Tornado-texture  4620269460
--     weather-cloud    5398996805
--     cloud-noise      41686044
--     black-clouds     1578526427
--
-- Hotkeys:
--   T           = заспавнить торнадо рядом
--   Shift+T     = вкл/выкл auto-spawn
--   Ctrl+T      = убить всё
--   Alt+T       = скрыть/показать панель
--==============================================================

if getgenv and getgenv().__TORNADO_V10_LOADED then
	warn("[Tornado v10] Уже загружен, перезагружаю")
	if getgenv().__TORNADO_V10_UNLOAD then pcall(getgenv().__TORNADO_V10_UNLOAD) end
end
if getgenv then getgenv().__TORNADO_V10_LOADED = true end

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local Workspace  = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local function pgui()
	return player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 5)
end

-- ================== ASSETS ==================
local A = {
	Particle    = "rbxassetid://3318493519",
	Texture     = "rbxassetid://4620269460",
	WeatherCld  = "rbxassetid://5398996805",
	CloudNoise  = "rbxassetid://41686044",
	BlackClouds = "rbxassetid://1578526427",
}

-- ================== CONFIG ==================
local CFG = {
	maxConcurrent      = 3,
	spawnCheckInterval = 10,
	spawnChance        = 0.6,
	spawnMinDist       = 250,
	spawnMaxDist       = 750,
	minTornadoSep      = 120,
	mergeDist          = 55,
	splitBaseChance    = 0.0012,     -- per second per tornado (EF>=3)
	formingTime        = 6.0,
	matureTimeMin      = 30,
	matureTimeMax      = 90,
	dyingTime          = 12,
	coreRadiusMin      = 10,
	coreRadiusMax      = 32,
	heightMin          = 200,
	heightMax          = 340,
	moveSpeedMin       = 6,
	moveSpeedMax       = 22,
	driftFreq          = 0.06,
	autoSpawn          = true,
	strengthEF         = 2,
	debug              = false,
}

-- ================== CONTAINER ==================
local existing = Workspace:FindFirstChild("_TornadoV10_Root")
if existing then existing:Destroy() end
local root = Instance.new("Folder")
root.Name = "_TornadoV10_Root"
root.Parent = Workspace

-- ================== UTILS ==================
local rng = Random.new()
local function lerp(a, b, t) return a + (b - a) * t end
local function clamp(v, lo, hi) return v < lo and lo or (v > hi and hi or v) end
local function urand(lo, hi) return lo + rng:NextNumber() * (hi - lo) end

local function playerPos()
	local ch = player.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	return hrp and hrp.Position or Vector3.new(0, 5, 0)
end

local function groundYAt(x, z)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = {player.Character, root}
	local hit = Workspace:Raycast(Vector3.new(x, 800, z), Vector3.new(0, -1600, 0), rp)
	return hit and hit.Position.Y or 0
end

local function makePart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do p[k] = v end
	return p
end

local function ns2(v1, v2, v3)
	if v3 then
		return NumberSequence.new({
			NumberSequenceKeypoint.new(0, v1),
			NumberSequenceKeypoint.new(0.5, v2),
			NumberSequenceKeypoint.new(1, v3),
		})
	end
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, v1),
		NumberSequenceKeypoint.new(1, v2),
	})
end

-- ================== RANKINE VORTEX ==================
-- Возвращает тангенциальную скорость в точке (dx, dz) относительно центра.
-- v(r) = vPeak * r / R           при r < R  (solid body)
-- v(r) = vPeak * R / r           при r >= R (potential)
local function rankineTangent(dx, dz, R, vPeak)
	local r = math.sqrt(dx*dx + dz*dz)
	if r < 0.001 then return Vector3.new(), 0, 0 end
	local vTan
	if r < R then
		vTan = vPeak * (r / R)
	else
		vTan = vPeak * (R / r)
	end
	local tx, tz = -dz / r, dx / r
	return Vector3.new(tx * vTan, 0, tz * vTan), vTan, r
end

-- ================== TORNADO CLASS ==================
local activeTornadoes = {}
local nextId = 1
local Tornado = {}
Tornado.__index = Tornado

function Tornado.new(pos, ef)
	local self = setmetatable({}, Tornado)
	self.id = nextId; nextId = nextId + 1
	self.pos = Vector3.new(pos.X, 0, pos.Z)
	self.ef = clamp(ef or CFG.strengthEF, 0, 5)
	self.age = 0
	self.state = "forming"
	self.stateTimer = 0
	self.matureDuration = urand(CFG.matureTimeMin, CFG.matureTimeMax)
	self.baseCoreRadius = urand(CFG.coreRadiusMin, CFG.coreRadiusMax) * (0.55 + self.ef * 0.15)
	self.baseHeight = urand(CFG.heightMin, CFG.heightMax)
	self.vPeak = 18 + self.ef * 25   -- EF0=18, EF5=143 m/s
	self.moveSpeed = urand(CFG.moveSpeedMin, CFG.moveSpeedMax)
	self.moveDir = Vector3.new(rng:NextNumber()*2-1, 0, rng:NextNumber()*2-1)
	if self.moveDir.Magnitude < 0.01 then self.moveDir = Vector3.new(1,0,0) end
	self.moveDir = self.moveDir.Unit
	self.noiseSeed = rng:NextNumber() * 1000
	self.merged = false
	self.folder = Instance.new("Folder")
	self.folder.Name = "Tornado_" .. self.id
	self.folder.Parent = root
	self:build()
	activeTornadoes[self.id] = self
	return self
end

function Tornado:build()
	-- ==== Основной ствол воронки: стек цилиндров ====
	self.segments = {}
	local segCount = 14
	for i = 1, segCount do
		local seg = makePart({
			Size = Vector3.new(2, 4, 2),
			Transparency = 0.4,
			Color = Color3.fromRGB(135, 133, 145),
			Material = Enum.Material.Neon,
		})
		seg.Name = "seg_" .. i
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Cylinder
		mesh.Scale = Vector3.new(1, 1, 1)
		mesh.Parent = seg
		seg.Parent = self.folder
		table.insert(self.segments, {part = seg, ti = (i - 1) / (segCount - 1)})
	end

	-- ==== "Rukava" (rotating texture sleeves) — вертикальные полосы с Tornado-texture ====
	self.sleeves = {}
	for i = 1, 7 do
		local sleeve = makePart({
			Size = Vector3.new(0.3, 100, 6),
			Transparency = 1,
		})
		sleeve.Name = "sleeve_" .. i
		for _, face in ipairs({Enum.NormalId.Front, Enum.NormalId.Back}) do
			local d = Instance.new("Decal")
			d.Face = face
			d.Texture = A.Texture
			d.Transparency = 0.25
			d.Color3 = Color3.fromRGB(200, 197, 210)
			d.Parent = sleeve
		end
		sleeve.Parent = self.folder
		table.insert(self.sleeves, {part = sleeve, phase = (i - 1) / 7 * math.pi * 2})
	end

	-- ==== Wall cloud (вращающийся диск тёмного облака под основой) ====
	self.wallCloud = makePart({
		Size = Vector3.new(100, 8, 100),
		Transparency = 0.25,
		Color = Color3.fromRGB(38, 38, 48),
	})
	self.wallCloud.Name = "wallCloud"
	local wcMesh = Instance.new("SpecialMesh")
	wcMesh.MeshType = Enum.MeshType.Sphere
	wcMesh.Scale = Vector3.new(1, 0.15, 1)
	wcMesh.Parent = self.wallCloud
	for _, face in ipairs({Enum.NormalId.Top, Enum.NormalId.Bottom}) do
		local d = Instance.new("Decal")
		d.Face = face
		d.Texture = A.BlackClouds
		d.Transparency = 0.1
		d.Color3 = Color3.fromRGB(80, 78, 92)
		d.Parent = self.wallCloud
	end
	self.wallCloud.Parent = self.folder

	-- ==== Верхняя облачная шапка (over-cloud) ====
	self.topCloud = makePart({
		Size = Vector3.new(200, 6, 200),
		Transparency = 0.3,
		Color = Color3.fromRGB(55, 55, 68),
	})
	self.topCloud.Name = "topCloud"
	local tcMesh = Instance.new("SpecialMesh")
	tcMesh.MeshType = Enum.MeshType.Sphere
	tcMesh.Scale = Vector3.new(1, 0.1, 1)
	tcMesh.Parent = self.topCloud
	for _, face in ipairs({Enum.NormalId.Top, Enum.NormalId.Bottom}) do
		local d = Instance.new("Decal")
		d.Face = face
		d.Texture = A.CloudNoise
		d.Transparency = 0.2
		d.Color3 = Color3.fromRGB(120, 118, 135)
		d.Parent = self.topCloud
	end
	self.topCloud.Parent = self.folder

	-- ==== Weather-tornado-cloud посередине высоты, вращается ====
	self.midCloud = makePart({
		Size = Vector3.new(60, 20, 60),
		Transparency = 0.4,
		Color = Color3.fromRGB(90, 88, 100),
	})
	self.midCloud.Name = "midCloud"
	local mcMesh = Instance.new("SpecialMesh")
	mcMesh.MeshType = Enum.MeshType.Sphere
	mcMesh.Scale = Vector3.new(1, 0.5, 1)
	mcMesh.Parent = self.midCloud
	for _, face in ipairs({Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right}) do
		local d = Instance.new("Decal")
		d.Face = face
		d.Texture = A.WeatherCld
		d.Transparency = 0.35
		d.Parent = self.midCloud
	end
	self.midCloud.Parent = self.folder

	-- ==== Ground base для частиц (пыль + обломки) ====
	self.basePart = makePart({Size = Vector3.new(0.1, 0.1, 0.1), Transparency = 1})
	self.basePart.Name = "basePart"
	self.basePart.Parent = self.folder
	local baseAtt = Instance.new("Attachment")
	baseAtt.Parent = self.basePart

	-- Обломки/пыль летящие от земли по спирали
	local debris = Instance.new("ParticleEmitter")
	debris.Texture = A.Particle
	debris.Rate = 80 + self.ef * 60
	debris.Lifetime = NumberRange.new(1.5, 3.0)
	debris.Speed = NumberRange.new(25, 55)
	debris.SpreadAngle = Vector2.new(180, 180)
	debris.Rotation = NumberRange.new(0, 360)
	debris.RotSpeed = NumberRange.new(-180, 180)
	debris.Color = ColorSequence.new(Color3.fromRGB(115, 110, 120))
	debris.LightEmission = 0.05
	debris.LockedToPart = false
	debris.Acceleration = Vector3.new(0, -8, 0)
	debris.Parent = baseAtt
	self.debrisEmitter = debris

	-- Основной вихревой эмиттер (спиральный подъём частиц)
	local swirl = Instance.new("ParticleEmitter")
	swirl.Texture = A.Particle
	swirl.Rate = 180 + self.ef * 80
	swirl.Lifetime = NumberRange.new(3.5, 5.5)
	swirl.Speed = NumberRange.new(20, 32)
	swirl.SpreadAngle = Vector2.new(8, 8)
	swirl.Rotation = NumberRange.new(0, 360)
	swirl.RotSpeed = NumberRange.new(-360, 360)
	swirl.Color = ColorSequence.new(Color3.fromRGB(160, 155, 170))
	swirl.LightEmission = 0.1
	swirl.Acceleration = Vector3.new(0, 40, 0)
	swirl.Parent = baseAtt
	self.swirlEmitter = swirl

	-- Плотное ядро (маленькие быстрые частицы)
	local core = Instance.new("ParticleEmitter")
	core.Texture = A.Particle
	core.Rate = 220 + self.ef * 80
	core.Lifetime = NumberRange.new(4, 6)
	core.Speed = NumberRange.new(10, 20)
	core.SpreadAngle = Vector2.new(3, 3)
	core.Rotation = NumberRange.new(0, 360)
	core.RotSpeed = NumberRange.new(-540, 540)
	core.Color = ColorSequence.new(Color3.fromRGB(180, 175, 190))
	core.LightEmission = 0.15
	core.Acceleration = Vector3.new(0, 55, 0)
	core.Parent = baseAtt
	self.coreEmitter = core
end

function Tornado:radiusScale()
	if self.state == "forming" then return clamp(self.stateTimer / CFG.formingTime, 0.02, 1) end
	if self.state == "mature" then return 1 end
	if self.state == "dying" then
		return math.max(0, 1 - (self.stateTimer / CFG.dyingTime) * 0.9)
	end
	return 0
end

function Tornado:funnelReach()
	-- 0..1 насколько воронка спустилась к земле
	if self.state == "forming" then
		return clamp(self.stateTimer / CFG.formingTime, 0.05, 1)
	end
	if self.state == "mature" then return 1 end
	if self.state == "dying" then
		return math.max(0.1, 1 - (self.stateTimer / CFG.dyingTime) * 0.7)
	end
	return 0
end

function Tornado:update(dt)
	if self.state == "dead" then return end
	self.age = self.age + dt
	self.stateTimer = self.stateTimer + dt

	-- Переходы состояний
	if self.state == "forming" and self.stateTimer >= CFG.formingTime then
		self.state = "mature"; self.stateTimer = 0
	elseif self.state == "mature" and self.stateTimer >= self.matureDuration then
		self.state = "dying"; self.stateTimer = 0
	elseif self.state == "dying" and self.stateTimer >= CFG.dyingTime then
		self:destroy(); return
	end

	-- Движение по земле с дрейфом
	local t = self.age * CFG.driftFreq + self.noiseSeed
	local driftX = math.sin(t) * 0.5 + math.sin(t * 2.3) * 0.3
	local driftZ = math.cos(t * 1.1) * 0.5 + math.cos(t * 1.7) * 0.3
	local target = Vector3.new(self.moveDir.X + driftX * 0.4, 0, self.moveDir.Z + driftZ * 0.4)
	if target.Magnitude > 0.01 then self.moveDir = target.Unit end
	self.pos = self.pos + self.moveDir * self.moveSpeed * dt

	local scale = self:radiusScale()
	local reach = self:funnelReach()
	local breathe = 1 + math.sin(self.age * 3) * 0.08
	local activeR = self.baseCoreRadius * scale * breathe
	if self.state == "dying" then
		activeR = activeR * math.max(0.25, 1 - self.stateTimer / CFG.dyingTime * 0.7)
	end

	local groundY = groundYAt(self.pos.X, self.pos.Z)
	self.groundY = groundY
	local topY = groundY + self.baseHeight
	local bottomY = topY - self.baseHeight * reach
	local totalH = topY - bottomY
	if totalH < 1 then totalH = 1 end

	-- Обновляем сегменты ствола (конус: узкий у земли, шире вверху)
	local segCount = #self.segments
	local segH = totalH / segCount * 1.05
	for i, s in ipairs(self.segments) do
		local ti = s.ti
		local y = lerp(bottomY, topY, ti) + segH * 0.5 - totalH / segCount * 0.5
		local rHere = lerp(activeR * 0.55, activeR * 1.45, ti)
		-- Wobble: сильный в rope-out, слабый нормально
		local wobAmp = self.state == "dying" and (5 * ti * (self.stateTimer / CFG.dyingTime)) or (1.2 * ti)
		local wobX = math.sin(self.age * 2.5 + ti * 6) * wobAmp
		local wobZ = math.cos(self.age * 2.5 + ti * 6) * wobAmp
		s.part.Size = Vector3.new(rHere * 2, segH, rHere * 2)
		s.part.CFrame = CFrame.new(self.pos.X + wobX, y, self.pos.Z + wobZ)
		local segTrans = 0.4
		if self.state == "dying" then
			segTrans = lerp(0.4, 0.9, self.stateTimer / CFG.dyingTime)
		elseif self.state == "forming" then
			segTrans = lerp(0.75, 0.4, self.stateTimer / CFG.formingTime)
		end
		s.part.Transparency = segTrans
	end

	-- Обновляем sleeves (вращающиеся вертикальные плоскости с текстурой)
	local rotSpeed = 2.2 + self.ef * 0.9
	if self.state == "dying" then rotSpeed = rotSpeed * 1.4 end
	for i, sv in ipairs(self.sleeves) do
		local phase = sv.phase + self.age * rotSpeed
		local centerR = activeR * 1.02
		local sx = math.cos(phase) * centerR
		local sz = math.sin(phase) * centerR
		local center = Vector3.new(self.pos.X + sx, (topY + bottomY) * 0.5, self.pos.Z + sz)
		local towardCenter = Vector3.new(self.pos.X, center.Y, self.pos.Z)
		sv.part.Size = Vector3.new(0.3, totalH, activeR * 2.3)
		sv.part.CFrame = CFrame.lookAt(center, towardCenter)
	end

	-- Wall cloud (толстый диск сразу над основой)
	self.wallCloud.CFrame = CFrame.new(self.pos.X, topY + 6, self.pos.Z)
	self.wallCloud.Size = Vector3.new(activeR * 11, 8, activeR * 11)

	-- Top cloud (высоко)
	self.topCloud.CFrame = CFrame.new(self.pos.X, topY + 45, self.pos.Z) * CFrame.Angles(0, self.age * 0.15, 0)
	self.topCloud.Size = Vector3.new(activeR * 20, 6, activeR * 20)
	self.topCloud.Transparency = self.state == "dying" and lerp(0.3, 0.85, self.stateTimer / CFG.dyingTime) or 0.3

	-- Mid cloud (посередине воронки, вращается)
	self.midCloud.CFrame = CFrame.new(self.pos.X, (topY + bottomY) * 0.5, self.pos.Z) * CFrame.Angles(0, self.age * (rotSpeed * 0.5), 0)
	self.midCloud.Size = Vector3.new(activeR * 3.5, totalH * 0.5, activeR * 3.5)
	self.midCloud.Transparency = self.state == "dying" and lerp(0.45, 0.95, self.stateTimer / CFG.dyingTime) or 0.45

	-- База для частиц у земли
	self.basePart.CFrame = CFrame.new(self.pos.X, groundY + 1, self.pos.Z)

	local touching = reach > 0.85 and self.state ~= "dead"
	self.debrisEmitter.Enabled = touching
	self.swirlEmitter.Enabled = self.state ~= "dead" and reach > 0.15
	self.coreEmitter.Enabled = self.state ~= "dead" and reach > 0.3

	-- Размеры эмиттеров подстраиваем под радиус
	self.debrisEmitter.Size = ns2(activeR * 0.35, activeR * 1.6)
	self.debrisEmitter.Transparency = ns2(0.35, 1)
	self.swirlEmitter.Size = ns2(activeR * 0.45, activeR * 0.9, activeR * 1.7)
	self.swirlEmitter.Transparency = ns2(0.25, 0.5, 1)
	self.coreEmitter.Size = ns2(activeR * 0.5, activeR * 0.7, activeR * 1.1)
	self.coreEmitter.Transparency = ns2(0.15, 0.45, 1)
end

function Tornado:destroy()
	self.state = "dead"
	if self.folder then self.folder:Destroy() end
	activeTornadoes[self.id] = nil
end

-- ================== MANAGER ==================
local Manager = {spawnAccum = 0}

function Manager:snapshot()
	local list = {}
	for _, t in pairs(activeTornadoes) do table.insert(list, t) end
	return list
end

function Manager:countActive()
	local n = 0
	for _ in pairs(activeTornadoes) do n = n + 1 end
	return n
end

function Manager:tooCloseToExisting(pos)
	for _, t in pairs(activeTornadoes) do
		if t.state ~= "dying" then
			local d = Vector3.new(t.pos.X - pos.X, 0, t.pos.Z - pos.Z).Magnitude
			if d < CFG.minTornadoSep then return true end
		end
	end
	return false
end

function Manager:spawnRandom()
	if self:countActive() >= CFG.maxConcurrent then return nil end
	local pp = playerPos()
	for attempt = 1, 8 do
		local angle = rng:NextNumber() * math.pi * 2
		local dist = urand(CFG.spawnMinDist, CFG.spawnMaxDist)
		local spawnPos = Vector3.new(pp.X + math.cos(angle) * dist, 0, pp.Z + math.sin(angle) * dist)
		if not self:tooCloseToExisting(spawnPos) then
			local efRoll = CFG.strengthEF + math.floor(urand(-1, 1.9))
			return Tornado.new(spawnPos, clamp(efRoll, 0, 5))
		end
	end
end

function Manager:spawnNearPlayer()
	local pp = playerPos()
	local angle = rng:NextNumber() * math.pi * 2
	local dist = urand(80, 160)
	local pos = Vector3.new(pp.X + math.cos(angle) * dist, 0, pp.Z + math.sin(angle) * dist)
	return Tornado.new(pos, CFG.strengthEF)
end

function Manager:killAll()
	for _, t in pairs(self:snapshot()) do t:destroy() end
end

function Manager:checkMerges()
	-- Если два взрослых торнадо сближаются < mergeDist — сливаются
	local list = {}
	for _, t in pairs(activeTornadoes) do
		if t.state == "mature" and not t.merged then table.insert(list, t) end
	end
	for i = 1, #list do
		local a = list[i]
		if not a.merged then
			for j = i + 1, #list do
				local b = list[j]
				if not b.merged then
					local d = Vector3.new(a.pos.X - b.pos.X, 0, a.pos.Z - b.pos.Z).Magnitude
					if d < CFG.mergeDist then
						local big, small = a, b
						if a.baseCoreRadius < b.baseCoreRadius then big, small = b, a end
						local newR = math.sqrt(big.baseCoreRadius^2 + small.baseCoreRadius^2)
						big.baseCoreRadius = math.min(newR, CFG.coreRadiusMax * 1.9)
						big.baseHeight = math.max(big.baseHeight, small.baseHeight)
						big.ef = math.min(5, math.max(big.ef, small.ef) + 1)
						big.vPeak = 18 + big.ef * 25
						big.matureDuration = big.matureDuration + small.matureDuration * 0.35
						small.merged = true
						small.state = "dying"
						small.stateTimer = CFG.dyingTime * 0.55  -- быстрый rope-out
						break
					end
				end
			end
		end
	end
end

function Manager:checkSplits(dt)
	if self:countActive() >= CFG.maxConcurrent then return end
	local snapshot = self:snapshot()
	for _, t in ipairs(snapshot) do
		if t.state == "mature" and t.ef >= 3 and (t.matureDuration - t.stateTimer) > 20 then
			if rng:NextNumber() < CFG.splitBaseChance * dt * 60 then
				local angle = rng:NextNumber() * math.pi * 2
				local d = urand(45, 90)
				local newPos = Vector3.new(t.pos.X + math.cos(angle)*d, 0, t.pos.Z + math.sin(angle)*d)
				if not self:tooCloseToExisting(newPos) and self:countActive() < CFG.maxConcurrent then
					local child = Tornado.new(newPos, math.max(0, t.ef - 2))
					child.baseCoreRadius = t.baseCoreRadius * 0.55
					child.baseHeight = t.baseHeight * 0.8
					child.moveDir = ((newPos - t.pos).Unit)
				end
			end
		end
	end
end

function Manager:step(dt)
	for _, t in ipairs(self:snapshot()) do
		pcall(t.update, t, dt)
	end
	self:checkMerges()
	self:checkSplits(dt)
	if CFG.autoSpawn then
		self.spawnAccum = self.spawnAccum + dt
		if self.spawnAccum >= CFG.spawnCheckInterval then
			self.spawnAccum = 0
			if rng:NextNumber() < CFG.spawnChance then self:spawnRandom() end
		end
	end
end

-- ================== GUI ==================
local gui
local function buildGui()
	local pg = pgui()
	if not pg then return end
	if gui then gui:Destroy() end
	gui = Instance.new("ScreenGui")
	gui.Name = "TornadoV10GUI"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = pg

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, 230, 0, 195)
	frame.Position = UDim2.new(1, -250, 1, -215)
	frame.BackgroundColor3 = Color3.fromRGB(18, 18, 26)
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.Parent = gui
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

	local stroke = Instance.new("UIStroke", frame)
	stroke.Color = Color3.fromRGB(80, 80, 110)
	stroke.Thickness = 1
	stroke.Transparency = 0.4

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 24)
	title.BackgroundTransparency = 1
	title.Text = "🌪️  TORNADO ENGINE v10"
	title.TextColor3 = Color3.fromRGB(230, 230, 245)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 13
	title.Parent = frame

	local info = Instance.new("TextLabel")
	info.Size = UDim2.new(1, -10, 0, 40)
	info.Position = UDim2.new(0, 5, 0, 24)
	info.BackgroundTransparency = 1
	info.TextXAlignment = Enum.TextXAlignment.Left
	info.TextYAlignment = Enum.TextYAlignment.Top
	info.Text = ""
	info.TextColor3 = Color3.fromRGB(170, 170, 195)
	info.Font = Enum.Font.Gotham
	info.TextSize = 11
	info.TextWrapped = true
	info.Parent = frame

	local function mkBtn(label, y, cb)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(1, -10, 0, 24)
		b.Position = UDim2.new(0, 5, 0, y)
		b.BackgroundColor3 = Color3.fromRGB(55, 55, 78)
		b.TextColor3 = Color3.fromRGB(230, 230, 250)
		b.Font = Enum.Font.Gotham
		b.TextSize = 12
		b.Text = label
		b.BorderSizePixel = 0
		b.Parent = frame
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
		b.MouseButton1Click:Connect(cb)
		return b
	end

	local yy = 68
	mkBtn("🌪️ Заспавнить рядом [T]", yy, function() Manager:spawnNearPlayer() end); yy = yy + 27
	local autoBtn = mkBtn("Auto: ON  [Shift+T]", yy, function() CFG.autoSpawn = not CFG.autoSpawn end); yy = yy + 27
	mkBtn("💀 Убить все [Ctrl+T]", yy, function() Manager:killAll() end); yy = yy + 27
	local efBtn = mkBtn("EF: 2 [click]", yy, function() CFG.strengthEF = (CFG.strengthEF + 1) % 6 end); yy = yy + 27

	-- Info refresh
	task.spawn(function()
		while gui and gui.Parent do
			info.Text = string.format("Active: %d / %d\nEF-preset: %d   |   Auto: %s",
				Manager:countActive(), CFG.maxConcurrent, CFG.strengthEF, CFG.autoSpawn and "ON" or "OFF")
			autoBtn.Text = "Auto: " .. (CFG.autoSpawn and "ON" or "OFF") .. "  [Shift+T]"
			efBtn.Text = "EF: " .. CFG.strengthEF .. " [click]"
			task.wait(0.4)
		end
	end)
end

pcall(buildGui)

-- ================== HOTKEYS ==================
local inputConn = UIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.T then
		local shift = UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)
		local ctrl  = UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)
		local alt   = UIS:IsKeyDown(Enum.KeyCode.LeftAlt) or UIS:IsKeyDown(Enum.KeyCode.RightAlt)
		if ctrl then Manager:killAll()
		elseif shift then CFG.autoSpawn = not CFG.autoSpawn
		elseif alt then if gui then gui.Enabled = not gui.Enabled end
		else Manager:spawnNearPlayer() end
	end
end)

-- ================== MAIN LOOP ==================
local hbConn = RunService.Heartbeat:Connect(function(dt)
	if dt > 0.1 then dt = 0.1 end
	pcall(Manager.step, Manager, dt)
end)

-- Character respawn — пересобрать GUI
player.CharacterAdded:Connect(function()
	task.wait(1)
	pcall(buildGui)
end)

-- ================== UNLOAD ==================
if getgenv then
	getgenv().__TORNADO_V10_UNLOAD = function()
		if inputConn then inputConn:Disconnect() end
		if hbConn then hbConn:Disconnect() end
		Manager:killAll()
		if gui then gui:Destroy() end
		if root then root:Destroy() end
		getgenv().__TORNADO_V10_LOADED = nil
		getgenv().__TORNADO_V10_UNLOAD = nil
	end
end

pcall(function()
	StarterGui:SetCore("SendNotification", {
		Title = "Tornado v10",
		Text = "T=spawn, Shift+T=auto, Ctrl+T=kill, Alt+T=панель",
		Duration = 6,
	})
end)

print("[Tornado v10] Loaded. Hotkeys: T=spawn, Shift+T=auto, Ctrl+T=kill, Alt+T=panel toggle")
