-- Tornado v13 - no hotkeys, no own GUI, autoSpawn=false default, SMAZ_TORNADO API

if getgenv and getgenv().__TORNADO_V10_LOADED then
	if getgenv().__TORNADO_V10_UNLOAD then pcall(getgenv().__TORNADO_V10_UNLOAD) end
end
if getgenv then getgenv().__TORNADO_V10_LOADED = true end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local TEX = {
	Particle = "rbxassetid://3318493519",
	Texture = "rbxassetid://4620269460",
	WeatherCld = "rbxassetid://5398996805",
}

local CFG = {
	maxConcurrent = 3, autoSpawn = false,   -- DEFAULT OFF
	spawnInterval = 12, spawnChance = 0.6,
	spawnMinDist = 200, spawnMaxDist = 700,
	minSeparation = 120, mergeDist = 60, splitChance = 0.0015,
	formingTime = 5, matureTimeMin = 30, matureTimeMax = 90, dyingTime = 12,
	radiusMin = 10, radiusMax = 34,
	heightMin = 200, heightMax = 340,
	moveSpeedMin = 6, moveSpeedMax = 22,
	strengthEF = 2,
	ringsPerTornado = 14, emittersPerRing = 5,
	particleRate = 55, particleLife = {0.5, 0.9},
	debrisRate = 900,
}

local prev = Workspace:FindFirstChild("_TornadoV10_Root")
if prev then prev:Destroy() end
local root = Instance.new("Folder"); root.Name = "_TornadoV10_Root"; root.Parent = Workspace

local rng = Random.new()
local function urand(lo, hi) return lo + rng:NextNumber() * (hi - lo) end
local function clamp(v, lo, hi) return v < lo and lo or (v > hi and hi or v) end
local function lerp(a, b, t) return a + (b - a) * t end

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

local function makeAnchor()
	local p = Instance.new("Part")
	p.Size = Vector3.new(0.1, 0.1, 0.1); p.Transparency = 1
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.Massless = true; p.CastShadow = false
	return p
end

local Tornado = {}; Tornado.__index = Tornado
local active = {}; local nextId = 1

function Tornado.new(pos, ef)
	local self = setmetatable({}, Tornado)
	self.id = nextId; nextId = nextId + 1
	self.pos = Vector3.new(pos.X, 0, pos.Z)
	self.ef = clamp(ef or CFG.strengthEF, 0, 5)
	self.age = 0; self.state = "forming"; self.stateTimer = 0
	self.matureDuration = urand(CFG.matureTimeMin, CFG.matureTimeMax)
	self.baseR = urand(CFG.radiusMin, CFG.radiusMax) * (0.6 + self.ef * 0.15)
	self.baseH = urand(CFG.heightMin, CFG.heightMax)
	self.omega = 3 + self.ef * 1.2
	self.moveSpeed = urand(CFG.moveSpeedMin, CFG.moveSpeedMax)
	self.moveDir = Vector3.new(rng:NextNumber()*2-1, 0, rng:NextNumber()*2-1)
	if self.moveDir.Magnitude < 0.01 then self.moveDir = Vector3.new(1,0,0) end
	self.moveDir = self.moveDir.Unit
	self.driftSeed = rng:NextNumber() * 100
	self.merged = false
	self.folder = Instance.new("Folder"); self.folder.Name = "T_" .. self.id; self.folder.Parent = root
	self:build()
	active[self.id] = self
	return self
end

function Tornado:build()
	self.rings = {}
	for r = 1, CFG.ringsPerTornado do
		local ti = (r - 1) / (CFG.ringsPerTornado - 1)
		local ring = {ti = ti, emitters = {}}
		for e = 1, CFG.emittersPerRing do
			local anchor = makeAnchor(); anchor.Name = "r"..r.."_e"..e; anchor.Parent = self.folder
			local att = Instance.new("Attachment"); att.Parent = anchor
			local pe = Instance.new("ParticleEmitter")
			pe.Texture = TEX.Particle; pe.Rate = CFG.particleRate
			pe.Lifetime = NumberRange.new(CFG.particleLife[1], CFG.particleLife[2])
			pe.Speed = NumberRange.new(0, 0); pe.SpreadAngle = Vector2.new(0, 0)
			pe.Rotation = NumberRange.new(0, 360); pe.RotSpeed = NumberRange.new(-90, 90)
			pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 8), NumberSequenceKeypoint.new(1, 12)})
			pe.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.15, 0.35),
				NumberSequenceKeypoint.new(0.7, 0.5),
				NumberSequenceKeypoint.new(1, 1),
			})
			pe.Color = ColorSequence.new(Color3.fromRGB(155, 152, 165))
			pe.LightEmission = 0.05; pe.LightInfluence = 0.7; pe.LockedToPart = false; pe.Parent = att
			local pe2 = Instance.new("ParticleEmitter")
			pe2.Texture = TEX.Texture; pe2.Rate = CFG.particleRate * 0.5
			pe2.Lifetime = NumberRange.new(CFG.particleLife[1]*1.5, CFG.particleLife[2]*1.5)
			pe2.Speed = NumberRange.new(0, 0); pe2.SpreadAngle = Vector2.new(0, 0)
			pe2.Rotation = NumberRange.new(0, 360); pe2.RotSpeed = NumberRange.new(-180, 180)
			pe2.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(1, 14)})
			pe2.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.2, 0.5),
				NumberSequenceKeypoint.new(1, 1),
			})
			pe2.Color = ColorSequence.new(Color3.fromRGB(175, 173, 185))
			pe2.LightEmission = 0.1; pe2.LockedToPart = false; pe2.Parent = att
			table.insert(ring.emitters, {
				anchor = anchor, att = att, pe = pe, pe2 = pe2,
				phaseOff = (e - 1) / CFG.emittersPerRing * math.pi * 2 + rng:NextNumber() * 0.3,
			})
		end
		table.insert(self.rings, ring)
	end
	self.baseAnchor = makeAnchor(); self.baseAnchor.Name = "base"; self.baseAnchor.Parent = self.folder
	local baseAtt = Instance.new("Attachment"); baseAtt.Parent = self.baseAnchor
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = TEX.Particle
	dust.Rate = CFG.debrisRate * (0.5 + self.ef * 0.2)
	dust.Lifetime = NumberRange.new(1.5, 3); dust.Speed = NumberRange.new(20, 45)
	dust.SpreadAngle = Vector2.new(180, 180); dust.Rotation = NumberRange.new(0, 360)
	dust.RotSpeed = NumberRange.new(-360, 360)
	dust.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 20)})
	dust.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1)})
	dust.Color = ColorSequence.new(Color3.fromRGB(120, 115, 125))
	dust.Acceleration = Vector3.new(0, -5, 0); dust.LockedToPart = false; dust.Parent = baseAtt
	self.dustEmitter = dust
	self.cloudAnchor = makeAnchor(); self.cloudAnchor.Name = "cloud"; self.cloudAnchor.Parent = self.folder
	local cloudAtt = Instance.new("Attachment"); cloudAtt.Parent = self.cloudAnchor
	local cloud = Instance.new("ParticleEmitter")
	cloud.Texture = TEX.WeatherCld; cloud.Rate = 28
	cloud.Lifetime = NumberRange.new(3, 5); cloud.Speed = NumberRange.new(0, 0)
	cloud.SpreadAngle = Vector2.new(0, 0); cloud.Rotation = NumberRange.new(0, 360)
	cloud.RotSpeed = NumberRange.new(-30, 30)
	cloud.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 50), NumberSequenceKeypoint.new(1, 85)})
	cloud.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	cloud.Color = ColorSequence.new(Color3.fromRGB(60, 58, 72))
	cloud.LockedToPart = false; cloud.Parent = cloudAtt
	self.cloudEmitter = cloud
end

function Tornado:radiusScale()
	if self.state == "forming" then return clamp(self.stateTimer / CFG.formingTime, 0.05, 1) end
	if self.state == "mature" then return 1 end
	if self.state == "dying" then return math.max(0, 1 - (self.stateTimer / CFG.dyingTime) * 0.9) end
	return 0
end

function Tornado:reach()
	if self.state == "forming" then return clamp(self.stateTimer / CFG.formingTime, 0.1, 1) end
	if self.state == "mature" then return 1 end
	if self.state == "dying" then return math.max(0.1, 1 - (self.stateTimer / CFG.dyingTime) * 0.7) end
	return 0
end

function Tornado:update(dt)
	if self.state == "dead" then return end
	self.age = self.age + dt; self.stateTimer = self.stateTimer + dt
	if self.state == "forming" and self.stateTimer >= CFG.formingTime then
		self.state = "mature"; self.stateTimer = 0
	elseif self.state == "mature" and self.stateTimer >= self.matureDuration then
		self.state = "dying"; self.stateTimer = 0
	elseif self.state == "dying" and self.stateTimer >= CFG.dyingTime then
		self:destroy(); return
	end
	local t = self.age * 0.05 + self.driftSeed
	local dx = math.sin(t) * 0.5 + math.sin(t * 2.3) * 0.3
	local dz = math.cos(t * 1.1) * 0.5 + math.cos(t * 1.7) * 0.3
	local target = Vector3.new(self.moveDir.X + dx * 0.4, 0, self.moveDir.Z + dz * 0.4)
	if target.Magnitude > 0.01 then self.moveDir = target.Unit end
	self.pos = self.pos + self.moveDir * self.moveSpeed * dt
	local scale = self:radiusScale(); local reach = self:reach()
	local activeR = self.baseR * scale * (1 + math.sin(self.age * 3) * 0.06)
	if self.state == "dying" then
		activeR = activeR * math.max(0.25, 1 - self.stateTimer / CFG.dyingTime * 0.7)
	end
	local groundY = groundYAt(self.pos.X, self.pos.Z)
	local topY = groundY + self.baseH; local bottomY = topY - self.baseH * reach
	for _, ring in ipairs(self.rings) do
		local ti = ring.ti
		local y = lerp(bottomY, topY, ti)
		local rHere = lerp(activeR * 0.4, activeR * 1.4, ti)
		local wobAmp = self.state == "dying" and (4 * ti * (self.stateTimer / CFG.dyingTime)) or (0.8 * ti)
		local wobX = math.sin(self.age * 2.5 + ti * 6) * wobAmp
		local wobZ = math.cos(self.age * 2.5 + ti * 6) * wobAmp
		local ringCX = self.pos.X + wobX; local ringCZ = self.pos.Z + wobZ
		for _, em in ipairs(ring.emitters) do
			local phase = em.phaseOff + self.age * self.omega * (0.7 + ti * 0.5)
			local ax = ringCX + math.cos(phase) * rHere
			local az = ringCZ + math.sin(phase) * rHere
			em.anchor.CFrame = CFrame.new(ax, y, az)
			local enabled = reach > 0.1
			em.pe.Enabled = enabled; em.pe2.Enabled = enabled
		end
	end
	self.baseAnchor.CFrame = CFrame.new(self.pos.X, groundY + 1, self.pos.Z)
	self.dustEmitter.Enabled = reach > 0.85 and self.state ~= "dead"
	self.cloudAnchor.CFrame = CFrame.new(self.pos.X, topY + 30, self.pos.Z)
	self.cloudEmitter.Enabled = self.state ~= "dead"
end

function Tornado:destroy()
	self.state = "dead"
	if self.folder then self.folder:Destroy() end
	active[self.id] = nil
end

local Manager = {spawnAccum = 0}

function Manager:count()
	local n = 0
	for _ in pairs(active) do n = n + 1 end
	return n
end

function Manager:snapshot()
	local list = {}
	for _, t in pairs(active) do table.insert(list, t) end
	return list
end

function Manager:tooClose(pos)
	for _, t in pairs(active) do
		if t.state ~= "dying" then
			local d = Vector3.new(t.pos.X - pos.X, 0, t.pos.Z - pos.Z).Magnitude
			if d < CFG.minSeparation then return true end
		end
	end
	return false
end

function Manager:spawnRandom()
	if self:count() >= CFG.maxConcurrent then return end
	local pp = playerPos()
	for a = 1, 8 do
		local ang = rng:NextNumber() * math.pi * 2
		local d = urand(CFG.spawnMinDist, CFG.spawnMaxDist)
		local p = Vector3.new(pp.X + math.cos(ang)*d, 0, pp.Z + math.sin(ang)*d)
		if not self:tooClose(p) then
			return Tornado.new(p, clamp(CFG.strengthEF + math.floor(urand(-1, 2)), 0, 5))
		end
	end
end

function Manager:spawnNear()
	if self:count() >= CFG.maxConcurrent then return end
	local pp = playerPos()
	local ang = rng:NextNumber() * math.pi * 2
	local d = urand(80, 160)
	return Tornado.new(Vector3.new(pp.X + math.cos(ang)*d, 0, pp.Z + math.sin(ang)*d), CFG.strengthEF)
end

function Manager:killAll()
	for _, t in ipairs(self:snapshot()) do t:destroy() end
end

function Manager:checkMerges()
	local list = {}
	for _, t in pairs(active) do
		if t.state == "mature" and not t.merged then table.insert(list, t) end
	end
	for i = 1, #list do
		local a = list[i]
		if not a.merged then
			for j = i+1, #list do
				local b = list[j]
				if not b.merged then
					local dd = Vector3.new(a.pos.X - b.pos.X, 0, a.pos.Z - b.pos.Z).Magnitude
					if dd < CFG.mergeDist then
						local big, small = a, b
						if a.baseR < b.baseR then big, small = b, a end
						big.baseR = math.min(math.sqrt(big.baseR^2 + small.baseR^2), CFG.radiusMax * 1.9)
						big.baseH = math.max(big.baseH, small.baseH)
						big.ef = math.min(5, math.max(big.ef, small.ef) + 1)
						big.matureDuration = big.matureDuration + small.matureDuration * 0.35
						small.merged = true
						small.state = "dying"; small.stateTimer = CFG.dyingTime * 0.55
						break
					end
				end
			end
		end
	end
end

function Manager:step(dt)
	for _, t in ipairs(self:snapshot()) do pcall(t.update, t, dt) end
	self:checkMerges()
	if CFG.autoSpawn then
		self.spawnAccum = self.spawnAccum + dt
		if self.spawnAccum >= CFG.spawnInterval then
			self.spawnAccum = 0
			if rng:NextNumber() < CFG.spawnChance then self:spawnRandom() end
		end
	end
end

local hbConn = RunService.Heartbeat:Connect(function(dt)
	if dt > 0.1 then dt = 0.1 end
	pcall(Manager.step, Manager, dt)
end)

if getgenv then
	getgenv().SMAZ_TORNADO = {
		CFG = CFG,
		spawnNear = function() return Manager:spawnNear() end,
		spawnRandom = function() return Manager:spawnRandom() end,
		killAll = function() Manager:killAll() end,
		setAutoSpawn = function(v) CFG.autoSpawn = v end,
		isAutoSpawn = function() return CFG.autoSpawn end,
		setEF = function(v) CFG.strengthEF = clamp(v, 0, 5) end,
		getEF = function() return CFG.strengthEF end,
		count = function() return Manager:count() end,
		max = function() return CFG.maxConcurrent end,
	}
	getgenv().__TORNADO_V10_UNLOAD = function()
		hbConn:Disconnect()
		Manager:killAll()
		if root then root:Destroy() end
		getgenv().__TORNADO_V10_LOADED = nil; getgenv().__TORNADO_V10_UNLOAD = nil
		getgenv().SMAZ_TORNADO = nil
	end
end

print("[Tornado v13] Loaded (autoSpawn OFF), API: getgenv().SMAZ_TORNADO")
