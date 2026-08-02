-- Tornado v12 (overwrites v10) - PARTICLE-BASED. No cylinder models. All from textures.
-- Each tornado = rotating attachments with ParticleEmitters using tornado textures.

if getgenv and getgenv().__TORNADO_V10_LOADED then
	if getgenv().__TORNADO_V10_UNLOAD then pcall(getgenv().__TORNADO_V10_UNLOAD) end
end
if getgenv then getgenv().__TORNADO_V10_LOADED = true end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer

local TEX = {
	Particle = "rbxassetid://3318493519",
	Texture = "rbxassetid://4620269460",
	WeatherCld = "rbxassetid://5398996805",
	CloudNoise = "rbxassetid://41686044",
	BlackClouds = "rbxassetid://1578526427",
}

local CFG = {
	maxConcurrent = 3,
	autoSpawn = true,
	spawnInterval = 12,
	spawnChance = 0.6,
	spawnMinDist = 200,
	spawnMaxDist = 700,
	minSeparation = 120,
	mergeDist = 60,
	splitChance = 0.0015,
	formingTime = 5,
	matureTimeMin = 30,
	matureTimeMax = 90,
	dyingTime = 12,
	radiusMin = 10,
	radiusMax = 34,
	heightMin = 200,
	heightMax = 340,
	moveSpeedMin = 6,
	moveSpeedMax = 22,
	strengthEF = 2,
	ringsPerTornado = 14,       -- horizontal rings up the funnel
	emittersPerRing = 5,         -- rotating emitters per ring
	particleRate = 55,
	particleLife = {0.5, 0.9},
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
			local anchor = makeAnchor(); anchor.Name = string.format("r%d_e%d", r, e); anchor.Parent = self.folder
			local att = Instance.new("Attachment"); att.Parent = anchor
			local pe = Instance.new("ParticleEmitter")
			pe.Texture = TEX.Particle
			pe.Rate = CFG.particleRate
			pe.Lifetime = NumberRange.new(CFG.particleLife[1], CFG.particleLife[2])
			pe.Speed = NumberRange.new(0, 0)
			pe.SpreadAngle = Vector2.new(0, 0)
			pe.Rotation = NumberRange.new(0, 360)
			pe.RotSpeed = NumberRange.new(-90, 90)
		