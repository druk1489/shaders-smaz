-- Reflections v1 - real planar reflections via world clones
-- Clones nearby BaseParts and character bones, mirrors CFrame under a horizontal plane
-- Correct rotation math: flips pitch and roll, keeps yaw (planar mirror across Y).

if getgenv and getgenv().__REFL_V1_LOADED then
	if getgenv().__REFL_V1_UNLOAD then pcall(getgenv().__REFL_V1_UNLOAD) end
end
if getgenv then getgenv().__REFL_V1_LOADED = true end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local CFG = {
	enabled = true,
	radius = 32,             -- clone nearby BaseParts within this many studs
	scanInterval = 0.5,      -- rescan for new/vanished parts
	updateInterval = 0.06,   -- ~16 Hz clone CFrame refresh
	baseTransparency = 0.45, -- how see-through the reflection is at nearest
	edgeTransparency = 0.95, -- fades out at radius edge
	reflectionTint = Color3.fromRGB(150, 160, 190),
	tintMix = 0.3,           -- 0 = original color, 1 = full tint
	cloneCharacter = true,
	maxClones = 220,
	autoMirrorY = true,      -- raycast to find ground under player
	fixedMirrorY = 0,        -- used when autoMirrorY is false
	clearance = 0.05,        -- lift mirrored parts slightly below the plane
}

local prev = Workspace:FindFirstChild("_ReflectionsV1_Root")
if prev then prev:Destroy() end
local root = Instance.new("Folder"); root.Name = "_ReflectionsV1_Root"; root.Parent = Workspace

local pairsMap = {}         -- [origPart] = {clone=Part}
local charProxies = {}      -- {orig, proxy}
local mirrorY = 0

local function playerHRP()
	local ch = player.Character
	return ch and ch:FindFirstChild("HumanoidRootPart")
end

local function raycastMirrorY(hrp)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = {player.Character, root}
	local hit = Workspace:Raycast(hrp.Position + Vector3.new(0, 2, 0), Vector3.new(0, -300, 0), rp)
	return hit and hit.Position.Y or nil
end

local function isCharacterPart(part)
	local m = part:FindFirstAncestorOfClass("Model")
	while m do
		if m:FindFirstChildOfClass("Humanoid") or Players:GetPlayerFromCharacter(m) then return true end
		m = m.Parent and m.Parent:FindFirstAncestorOfClass("Model") or nil
	end
	return false
end

local function isCloneable(part)
	if not part:IsA("BasePart") then return false end
	if part.Transparency >= 1 then return false end
	if part:IsA("Terrain") then return false end
	if part.Name == "Terrain" then return false end
	if part:IsDescendantOf(root) then return false end
	if isCharacterPart(part) then return false end
	return true
end

local function makeClone(orig)
	local ok, clone = pcall(function()
		local wasArc = orig.Archivable
		orig.Archivable = true
		local c = orig:Clone()
		orig.Archivable = wasArc
		for _, ch in ipairs(c:GetChildren()) do ch:Destroy() end
		c.Anchored = true; c.CanCollide = false; c.CanQuery = false; c.CanTouch = false
		c.CastShadow = false; c.Massless = true
		c.Transparency = CFG.baseTransparency
		pcall(function() c.Color = orig.Color:Lerp(CFG.reflectionTint, CFG.tintMix) end)
		c.Parent = root
		return c
	end)
	return ok and clone or nil
end

-- Reflect a CFrame across horizontal plane y = mY.
-- Correct planar-mirror math: pitch and roll invert, yaw preserved.
local function mirrorCFrame(origCF, mY)
	local p = origCF.Position
	local mp = Vector3.new(p.X, 2 * mY - p.Y - CFG.clearance, p.Z)
	local rx, ry, rz = origCF:ToOrientation()
	return CFrame.new(mp) * CFrame.fromOrientation(-rx, ry, -rz)
end

local function countClones()
	local n = 0
	for _ in pairs(pairsMap) do n = n + 1 end
	return n
end

local function purgeAll()
	for orig, d in pairs(pairsMap) do if d.clone then d.clone:Destroy() end; pairsMap[orig] = nil end
	for _, p in ipairs(charProxies) do if p.proxy then p.proxy:Destroy() end end
	charProxies = {}
end

local function updateClonePair(orig, data, mY, hrp)
	local clone = data.clone
	if not clone or not clone.Parent then pairsMap[orig] = nil; return end
	if not orig or not orig.Parent then clone:Destroy(); pairsMap[orig] = nil; return end
	local d = (orig.Position - hrp.Position).Magnitude
	if d > CFG.radius then clone:Destroy(); pairsMap[orig] = nil; return end
	pcall(function() clone.Size = orig.Size end)
	clone.CFrame = mirrorCFrame(orig.CFrame, mY)
	local t = d / CFG.radius
	clone.Transparency = math.min(0.99, CFG.baseTransparency + (CFG.edgeTransparency - CFG.baseTransparency) * (t * t))
end

local function scanAndAdd(hrp)
	local cur = countClones()
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {root, player.Character}
	local nearby
	local ok = pcall(function()
		nearby = Workspace:GetPartBoundsInRadius(hrp.Position, CFG.radius, params)
	end)
	if not ok or not nearby then return end
	for _, part in ipairs(nearby) do
		if cur >= CFG.maxClones then break end
		if not pairsMap[part] and isCloneable(part) then
			local clone = makeClone(part)
			if clone then
				pairsMap[part] = {clone = clone}
				cur = cur + 1
			end
		end
	end
end

local CHAR_BONES = {"Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "LeftHand", "RightHand", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg"}

local function ensureCharProxies()
	if not CFG.cloneCharacter then
		if #charProxies > 0 then
			for _, p in ipairs(charProxies) do p.proxy:Destroy() end
			charProxies = {}
		end
		return
	end
	if #charProxies > 0 then return end
	local ch = player.Character; if not ch then return end
	for _, name in ipairs(CHAR_BONES) do
		local orig = ch:FindFirstChild(name)
		if orig and orig:IsA("BasePart") then
			local ok, c = pcall(function() return orig:Clone() end)
			if ok and c then
				for _, chi in ipairs(c:GetChildren()) do chi:Destroy() end
				c.Anchored = true; c.CanCollide = false; c.CanQuery = false; c.CanTouch = false
				c.CastShadow = false; c.Massless = true
				c.Transparency = CFG.baseTransparency
				pcall(function() c.Color = orig.Color:Lerp(CFG.reflectionTint, CFG.tintMix) end)
				c.Parent = root
				table.insert(charProxies, {orig = orig, proxy = c})
			end
		end
	end
end

local function updateCharProxies(mY)
	for i = #charProxies, 1, -1 do
		local p = charProxies[i]
		if not p.orig or not p.orig.Parent then
			if p.proxy then p.proxy:Destroy() end
			table.remove(charProxies, i)
		else
			pcall(function() p.proxy.Size = p.orig.Size end)
			p.proxy.CFrame = mirrorCFrame(p.orig.CFrame, mY)
			p.proxy.Transparency = math.min(0.9, CFG.baseTransparency + 0.15)
		end
	end
end

local scanAcc, updateAcc = 0, 0
local hbConn = RunService.Heartbeat:Connect(function(dt)
	if dt > 0.15 then dt = 0.15 end
	if not CFG.enabled then
		if countClones() > 0 or #charProxies > 0 then purgeAll() end
		return
	end
	local hrp = playerHRP(); if not hrp then return end
	local mY
	if CFG.autoMirrorY then
		mY = raycastMirrorY(hrp)
		if mY then mirrorY = mY else mY = mirrorY end
	else mY = CFG.fixedMirrorY; mirrorY = mY end
	scanAcc = scanAcc + dt
	if scanAcc >= CFG.scanInterval then
		scanAcc = 0
		pcall(scanAndAdd, hrp)
		ensureCharProxies()
	end
	updateAcc = updateAcc + dt
	if updateAcc >= CFG.updateInterval then
		updateAcc = 0
		for orig, data in pairs(pairsMap) do pcall(updateClonePair, orig, data, mY, hrp) end
		pcall(updateCharProxies, mY)
	end
end)

local charConn = player.CharacterAdded:Connect(function()
	for _, p in ipairs(charProxies) do if p.proxy then p.proxy:Destroy() end end
	charProxies = {}
end)

if getgenv then
	getgenv().SMAZ_REFL = {
		CFG = CFG,
		setEnabled = function(v) CFG.enabled = v end,
		isEnabled = function() return CFG.enabled end,
		setCloneCharacter = function(v) CFG.cloneCharacter = v end,
		isCloneCharacter = function() return CFG.cloneCharacter end,
		setRadius = function(v) CFG.radius = math.clamp(v, 8, 120); purgeAll() end,
		getRadius = function() return CFG.radius end,
		setBaseTransparency = function(v) CFG.baseTransparency = math.clamp(v, 0, 0.9) end,
		getBaseTransparency = function() return CFG.baseTransparency end,
		count = function() return countClones() + #charProxies end,
		rebuild = purgeAll,
	}
	getgenv().__REFL_V1_UNLOAD = function()
		hbConn:Disconnect(); charConn:Disconnect()
		purgeAll()
		if root then root:Destroy() end
		getgenv().__REFL_V1_LOADED = nil; getgenv().__REFL_V1_UNLOAD = nil
		getgenv().SMAZ_REFL = nil
	end
end

print("[Reflections v1] Loaded (radius=" .. CFG.radius .. ", API: getgenv().SMAZ_REFL)")
