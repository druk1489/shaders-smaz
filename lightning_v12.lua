-- Lightning v12 - 3D grid stepped-leader with upward streamers and shortest-path return stroke
-- Physics-inspired: leader grows down from cloud via voxel grid, small streamers rise from ground,
-- when they meet a return-stroke bolt fires along the shortest path back up through the leader tree.

if getgenv and getgenv().__LIGHTNING_V12_LOADED then
	if getgenv().__LIGHTNING_V12_UNLOAD then pcall(getgenv().__LIGHTNING_V12_UNLOAD) end
end
if getgenv then getgenv().__LIGHTNING_V12_LOADED = true end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local BOLT_TEX = "rbxassetid://73663492833517"

local CFG = {
	GRID_W = 10, GRID_L = 10, GRID_H = 20,   -- 2000-cell grid (~500+)
	CELL = 12,
	leaderStepInterval = 0.02,
	branchProb = 0.22,
	maxLeaderSteps = 45,
	streamerCount = 5,
	streamerStartHeight = 4,
	returnStrokeDuration = 0.10,
	returnStrokeGlowDuration = 0.30,
	autoOn = true,
	autoStrikeMin = 6,
	autoStrikeMax = 22,
	edgeDistortDuration = 0.35,   -- glass-edge distortion length
}

local prev = Workspace:FindFirstChild("_LightningV12_Root")
if prev then prev:Destroy() end
local root = Instance.new("Folder"); root.Name = "_LightningV12_Root"; root.Parent = Workspace

local rng = Random.new()

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

local function key(x, y, z) return x .. "," .. y .. "," .. z end

local function cellCenter(ox, gy, oz, x, y, z)
	return Vector3.new(ox + (x + 0.5) * CFG.CELL, gy + (y + 0.5) * CFG.CELL, oz + (z + 0.5) * CFG.CELL)
end

local function makeBillboard(pos, size, transparency)
	local part = Instance.new("Part")
	part.Size = Vector3.new(0.1, 0.1, 0.1); part.Transparency = 1
	part.Anchored = true; part.CanCollide = false; part.CanQuery = false
	part.Massless = true; part.CastShadow = false
	part.CFrame = CFrame.new(pos); part.Parent = root
	local bb = Instance.new("BillboardGui")
	bb.Adornee = part; bb.Size = UDim2.new(size, 0, size, 0); bb.LightInfluence = 0
	bb.AlwaysOnTop = false; bb.Parent = part
	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1; img.Size = UDim2.new(1, 0, 1, 0)
	img.Image = BOLT_TEX
	img.ImageColor3 = Color3.fromRGB(200, 215, 255)
	img.ImageTransparency = transparency or 0.6
	img.Rotation = math.random(-180, 180)
	img.Parent = bb
	return part, img
end

local function makeBeam(fromPos, toPos, thickness, transparency)
	local a1 = Instance.new("Part"); a1.Size = Vector3.new(0.1,0.1,0.1); a1.Transparency = 1
	a1.Anchored = true; a1.CanCollide = false; a1.CanQuery = false; a1.CastShadow = false
	a1.CFrame = CFrame.new(fromPos); a1.Parent = root
	local at1 = Instance.new("Attachment", a1)
	local a2 = Instance.new("Part"); a2.Size = Vector3.new(0.1,0.1,0.1); a2.Transparency = 1
	a2.Anchored = true; a2.CanCollide = false; a2.CanQuery = false; a2.CastShadow = false
	a2.CFrame = CFrame.new(toPos); a2.Parent = root
	local at2 = Instance.new("Attachment", a2)
	local beam = Instance.new("Beam")
	beam.Attachment0 = at1; beam.Attachment1 = at2
	beam.Texture = BOLT_TEX; beam.TextureLength = 8; beam.TextureSpeed = 10
	beam.Width0 = thickness; beam.Width1 = thickness
	beam.LightEmission = 1; beam.LightInfluence = 0; beam.FaceCamera = true
	beam.Transparency = NumberSequence.new(transparency or 0)
	beam.Color = ColorSequence.new(Color3.fromRGB(225, 232, 255))
	beam.Parent = a1
	return {a1 = a1, a2 = a2, beam = beam}
end

-- ============ EDGE DISTORTION (glass-like, no zoom) ============
local function playEdgeDistortion()
	local pgui = player:FindFirstChildOfClass("PlayerGui")
	if not pgui then return end
	local g = Instance.new("ScreenGui")
	g.Name = "LightningV12_Edge"
	g.ResetOnSpawn = false; g.IgnoreGuiInset = true; g.DisplayOrder = 200
	g.Parent = pgui
	-- Full-screen frame with radial gradient (transparent center, opaque edges)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 1, 0); frame.BackgroundColor3 = Color3.fromRGB(190, 210, 255)
	frame.BackgroundTransparency = 0.75; frame.BorderSizePixel = 0
	frame.Active = false; frame.Parent = g
	local grad = Instance.new("UIGradient")
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.35, 0.85),
		NumberSequenceKeypoint.new(0.65, 0.85),
		NumberSequenceKeypoint.new(1, 0.15),
	})
	grad.Parent = frame
	-- Vertical variant overlay for cross pattern
	local frame2 = frame:Clone()
	frame2.Parent = g
	local grad2 = frame2:FindFirstChildOfClass("UIGradient")
	if grad2 then grad2.Rotation = 90 end
	-- Small offset animation for wavy "glass" feel
	task.spawn(function()
		local t0 = tick()
		while tick() - t0 < CFG.edgeDistortDuration do
			local p = (tick() - t0) / CFG.edgeDistortDuration
			local envelope = math.sin(p * math.pi)  -- 0 -> 1 -> 0
			local wob = math.sin(p * 40) * 0.05 * envelope
			frame.Position = UDim2.new(0, math.floor(wob * 30), 0, math.floor(math.cos(p * 35) * envelope * 20))
			frame2.Position = UDim2.new(0, math.floor(-wob * 30), 0, math.floor(-math.cos(p * 35) * envelope * 20))
			frame.BackgroundTransparency = 0.75 + (1 - envelope) * 0.25
			frame2.BackgroundTransparency = 0.85 + (1 - envelope) * 0.15
			RunService.Heartbeat:Wait()
		end
		g:Destroy()
	end)
end

-- ============ MAIN STRIKE ============
local function doStrike()
	local pp = playerPos()
	local groundY = groundYAt(pp.X, pp.Z)
	local ox = pp.X - CFG.GRID_W * CFG.CELL * 0.5
	local oz = pp.Z - CFG.GRID_L * CFG.CELL * 0.5

	local visited = {}   -- key -> cell
	local frontier = {}  -- current growth tips
	local groundTips = {}

	local sx = rng:NextInteger(0, CFG.GRID_W - 1)
	local sz = rng:NextInteger(0, CFG.GRID_L - 1)
	local sy = CFG.GRID_H - 1
	local startCell = {x = sx, y = sy, z = sz, parent = nil}
	visited[key(sx, sy, sz)] = startCell
	table.insert(frontier, startCell)

	local strikeFolder = Instance.new("Folder")
	strikeFolder.Name = "Strike_" .. tostring(math.floor(tick()*1000))
	strikeFolder.Parent = root

	local leaderVis = {}
	local function drawCell(cell, size, transp)
		local pos = cellCenter(ox, groundY, oz, cell.x, cell.y, cell.z)
		local part, img = makeBillboard(pos, size or 3, transp or 0.75)
		part.Parent = strikeFolder
		leaderVis[key(cell.x, cell.y, cell.z)] = {part = part, img = img, cell = cell}
		return part, img
	end
	drawCell(startCell, 3.5, 0.7)

	local streamers = {}
	local streamerVis = {}
	local connectionLeader, connectionStreamer = nil, nil

	local NEIGH = {}
	for dx = -1, 1 do for dz = -1, 1 do table.insert(NEIGH, {dx, -1, dz}) end end

	task.spawn(function()
		local steps = 0
		while not connectionLeader and steps < CFG.maxLeaderSteps and #frontier > 0 do
			local newFrontier = {}
			for _, cell in ipairs(frontier) do
				local branches = 1
				if rng:NextNumber() < CFG.branchProb then branches = 2 end
				if rng:NextNumber() < CFG.branchProb * 0.3 then branches = 3 end
				for b = 1, branches do
					local nd = NEIGH[rng:NextInteger(1, #NEIGH)]
					local nx, ny, nz = cell.x + nd[1], cell.y + nd[2], cell.z + nd[3]
					if nx >= 0 and nx < CFG.GRID_W and ny >= 0 and nz >= 0 and nz < CFG.GRID_L then
						local k = key(nx, ny, nz)
						if not visited[k] then
							local newCell = {x = nx, y = ny, z = nz, parent = cell}
							visited[k] = newCell
							drawCell(newCell, 3, 0.78)
							table.insert(newFrontier, newCell)
							if ny <= 0 then table.insert(groundTips, newCell) end
						end
					end
				end
			end
			frontier = newFrontier
			steps = steps + 1

			-- Spawn streamers when leader is close to ground
			if #streamers == 0 then
				local close = false
				for _, c in ipairs(frontier) do
					if c.y <= CFG.streamerStartHeight then close = true; break end
				end
				if close then
					for s = 1, CFG.streamerCount do
						local ssx = rng:NextInteger(0, CFG.GRID_W - 1)
						local ssz = rng:NextInteger(0, CFG.GRID_L - 1)
						local sc = {x = ssx, y = 0, z = ssz, parent = nil, isStreamer = true}
						table.insert(streamers, sc)
						local pos = cellCenter(ox, groundY, oz, ssx, 0, ssz)
						local part, img = makeBillboard(pos, 2.5, 0.55)
						part.Parent = strikeFolder
						streamerVis[key(ssx, 0, ssz)] = {part = part, img = img, cell = sc}
					end
				end
			end

			-- Grow streamers upward
			local grown = {}
			for _, sc in ipairs(streamers) do
				local nx = sc.x + rng:NextInteger(-1, 1)
				local ny = sc.y + 1
				local nz = sc.z + rng:NextInteger(-1, 1)
				if nx >= 0 and nx < CFG.GRID_W and ny < CFG.GRID_H and nz >= 0 and nz < CFG.GRID_L then
					local k = key(nx, ny, nz)
					local newSC = {x = nx, y = ny, z = nz, parent = sc, isStreamer = true}
					if visited[k] then
						connectionLeader = visited[k]
						connectionStreamer = newSC
						break
					elseif not streamerVis[k] then
						table.insert(grown, newSC)
						local pos = cellCenter(ox, groundY, oz, nx, ny, nz)
						local part, img = makeBillboard(pos, 2.5, 0.6)
						part.Parent = strikeFolder
						streamerVis[k] = {part = part, img = img, cell = newSC}
					end
				end
			end
			for _, g in ipairs(grown) do table.insert(streamers, g) end

			task.wait(CFG.leaderStepInterval)
		end

		-- Fallback: if leader reached ground on its own, take first ground tip
		if not connectionLeader then
			for _, tip in ipairs(groundTips) do
				connectionLeader = tip
				break
			end
		end

		if not connectionLeader then
			-- No connection made -> fade dim leader and exit
			for _, v in pairs(leaderVis) do
				task.spawn(function()
					for i = 1, 20 do
						v.img.ImageTransparency = math.min(1, v.img.ImageTransparency + 0.05)
						task.wait(0.02)
					end
				end)
			end
			task.wait(0.5); strikeFolder:Destroy(); return
		end

		-- ===== Reconstruct shortest path (parent-chain in leader tree, one traversal each side)
		local path = {}
		local cur = connectionLeader
		while cur do table.insert(path, 1, cur); cur = cur.parent end
		if connectionStreamer then
			local spath = {}
			local scur = connectionStreamer
			while scur do table.insert(spath, 1, scur); scur = scur.parent end
			for i = #spath, 1, -1 do table.insert(path, 1, spath[i]) end
		end

		-- ===== FLASH + edge distortion (no zoom, just edges wobble like glass)
		local oldAmbient = Lighting.Ambient
		local oldOutdoor = Lighting.OutdoorAmbient
		pcall(function()
			Lighting.Ambient = Color3.fromRGB(230, 235, 255)
			Lighting.OutdoorAmbient = Color3.fromRGB(210, 220, 250)
		end)
		pcall(playEdgeDistortion)

		-- Draw bright beams along path
		local beams = {}
		for i = 1, #path - 1 do
			local c1 = path[i]; local c2 = path[i + 1]
			local p1 = cellCenter(ox, groundY, oz, c1.x, c1.y, c1.z)
			local p2 = cellCenter(ox, groundY, oz, c2.x, c2.y, c2.z)
			local b = makeBeam(p1, p2, 3.2, 0)
			b.a1.Parent = strikeFolder; b.a2.Parent = strikeFolder
			table.insert(beams, b)
		end

		-- Extra bright textures along path (small billboards)
		local pathBillboards = {}
		for _, c in ipairs(path) do
			local pos = cellCenter(ox, groundY, oz, c.x, c.y, c.z)
			local part, img = makeBillboard(pos, 6, 0.05)
			part.Parent = strikeFolder
			img.ImageColor3 = Color3.fromRGB(255, 255, 255)
			table.insert(pathBillboards, img)
		end

		task.wait(CFG.returnStrokeDuration)

		-- Fade out over glow duration
		local steps2 = 15
		for i = 1, steps2 do
			local t = i / steps2
			for _, b in ipairs(beams) do
				b.beam.Transparency = NumberSequence.new(t)
				b.beam.Width0 = 3.2 * (1 - t * 0.4)
				b.beam.Width1 = 3.2 * (1 - t * 0.4)
			end
			for _, img in ipairs(pathBillboards) do
				img.ImageTransparency = math.min(1, 0.05 + t * 0.95)
			end
			for _, v in pairs(leaderVis) do
				v.img.ImageTransparency = math.min(1, v.img.ImageTransparency + 0.05)
			end
			for _, v in pairs(streamerVis) do
				v.img.ImageTransparency = math.min(1, v.img.ImageTransparency + 0.05)
			end
			if i == 2 then
				pcall(function() Lighting.Ambient = oldAmbient; Lighting.OutdoorAmbient = oldOutdoor end)
			end
			task.wait(CFG.returnStrokeGlowDuration / steps2)
		end

		task.wait(0.1); strikeFolder:Destroy()
	end)
end

-- Auto strike loop
local autoRunning = false
local function startAuto()
	if autoRunning then return end
	autoRunning = true
	task.spawn(function()
		while CFG.autoOn do
			local wait = rng:NextNumber() * (CFG.autoStrikeMax - CFG.autoStrikeMin) + CFG.autoStrikeMin
			task.wait(wait)
			if CFG.autoOn then pcall(doStrike) end
		end
		autoRunning = false
	end)
end
startAuto()

local inputConn = UIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.L then
		local sh = UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)
		if sh then
			CFG.autoOn = not CFG.autoOn
			if CFG.autoOn then startAuto() end
			pcall(function() StarterGui:SetCore("SendNotification", {Title="Lightning v12", Text="Auto: " .. (CFG.autoOn and "ON" or "OFF"), Duration=2}) end)
		else
			pcall(doStrike)
		end
	end
end)

if getgenv then
	getgenv().__LIGHTNING_V12_UNLOAD = function()
		CFG.autoOn = false
		inputConn:Disconnect()
		if root then root:Destroy() end
		local pgui = player:FindFirstChildOfClass("PlayerGui")
		if pgui then
			local g = pgui:FindFirstChild("LightningV12_Edge")
			if g then g:Destroy() end
		end
		getgenv().__LIGHTNING_V12_LOADED = nil
		getgenv().__LIGHTNING_V12_UNLOAD = nil
	end
end

pcall(function() StarterGui:SetCore("SendNotification", {Title="Lightning v12", Text="Grid stepped-leader. L=strike, Shift+L=auto", Duration=5}) end)
print("[Lightning v12] Grid " .. CFG.GRID_W .. "x" .. CFG.GRID_H .. "x" .. CFG.GRID_L .. " = " .. (CFG.GRID_W*CFG.GRID_H*CFG.GRID_L) .. " cells")
