--==============================================================
-- ATMOSPHERE / SHADERS v9 (SOLARA / EXECUTOR)
-- Shift+P = фрикам, X = скрыть GUI, RightShift = панель
-- v9: solar/moon Store-models + lightning beam texture + SHOCKWAVE (flipbook + light distortion)
--   * ветвистые leader'ы (jagged + branches)
--   * upward leader из земли навстречу downward из облака
--   * return stroke = мега-вспышка после соединения
--   * impact FX на месте удара: spark burst, smoke, scorch mark
--   * гром с задержкой по расстоянию (343 studs/сек как m/s)
--==============================================================
local ok, err = pcall(function()

local Players          = game:GetService("Players")
local Lighting         = game:GetService("Lighting")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace        = game:GetService("Workspace")
local StarterGui       = game:GetService("StarterGui")
local SoundService     = game:GetService("SoundService")
local Debris           = game:GetService("Debris")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera
local Terrain     = Workspace:FindFirstChildOfClass("Terrain")

local clamp, rad, exp, pi = math.clamp, math.rad, math.exp, math.pi
local rnd = math.random

--==============================================================
-- АССЕТЫ ИЗ ROBLOX STORE
--==============================================================
-- Модели солнца/луны (грузятся через game:GetObjects в контексте executor'а)
local SUN_ASSET  = "rbxassetid://8430326250"
local MOON_ASSET = "rbxassetid://8430423571"

-- Текстура молнии (Store):
local BOLT_TEX = {
	"rbxassetid://73663492833517", -- lightingbeam
}

-- Ударная волна (flipbook 4x4 = 16 кадров):
local SHOCKWAVE_TEX = "rbxassetid://70564074541084"

-- (опционально, если зальёшь свои PNG'шки):
local FLASH_TEX  = "rbxassetid://0"
local SPARK_TEX  = "rbxassetid://0"
local SMOKE_TEX  = "rbxassetid://0"
local DEBRIS_TEX = "rbxassetid://0"

-- Дистанция до светил ("далеко" по просьбе)
local CELESTIAL_DIST = 8000

-- Fallback (стандартная beam-текстура Roblox если основная не грузится):
local DEFAULT_BOLT_FALLBACK = "rbxassetid://446111271"

-- Звуки грома (залей mp3 в Roblox, получи rbxassetid и вставь сюда — несколько для разнообразия):
local THUNDER_SOUNDS = {
	"rbxassetid://0", -- 4bd08c8067970b7.mp3 (короткий раскат)
	"rbxassetid://0", -- ozarnikru-raskat-groma.mp3
	"rbxassetid://0", -- fonoteca-raskat-groma.mp3
	"rbxassetid://0", -- zvuki_-_zvuk_groma.mp3 (длинный)
	"rbxassetid://0", -- raskaty_groma.mp3
}
local DEFAULT_THUNDER_FALLBACK = "rbxassetid://1839825074"

pcall(function()
	StarterGui:SetCore("SendNotification", {Title="Atmosphere v8", Text="Shift+P = фрикам, X = скрыть GUI, RightShift = панель", Duration=6})
end)

--==============================================================
-- НАСТРОЙКИ
--==============================================================
local S = {
	clouds=true, cloudAnimate=true, cloudCover=0.6, cloudDensity=0.55, cloudColor=0.9, cloudSpeed=0.5,
	rays=true, bloom=true, atmosphere=true,
	dayNight=true, dayLength=240, timeOfDay=12,
	sunSize=350, sunBright=2, sunRange=60,
	moonSize=450, moonBright=1,
	maxBrightness=2.5, atmDensity=0.32, atmHaze=1.4,
	sharpen=false, sharpenAmt=0.2, blur=false, blurAmt=12,
	weather="none", weatherIntensity=0.6,
	lightning=true, lightningRate=0.5,
	lightningMinDist=30, lightningMaxDist=180,
	tornado=false,
	freeCam=false, freeCamSpeed=140, sens=1,
}

--==============================================================
-- ФАЗЫ НЕБА
--==============================================================
local PHASES = {
	dawn    = { ambient=Color3.fromRGB(120,90,80),   atm=Color3.fromRGB(235,150,110), sun=Color3.fromRGB(255,200,150), tint=Color3.fromRGB(255,225,200), contrast=0.05 },
	day     = { ambient=Color3.fromRGB(150,160,180), atm=Color3.fromRGB(199,205,215), sun=Color3.fromRGB(255,245,220), tint=Color3.fromRGB(255,255,255), contrast=0    },
	evening = { ambient=Color3.fromRGB(110,70,70),   atm=Color3.fromRGB(240,120,90),  sun=Color3.fromRGB(255,150,90),  tint=Color3.fromRGB(255,215,190), contrast=0.08 },
	night   = { ambient=Color3.fromRGB(20,25,45),    atm=Color3.fromRGB(50,60,100),   sun=Color3.fromRGB(180,200,255), tint=Color3.fromRGB(180,195,235), contrast=-0.05},
}
local function phaseFromClock(ct)
	if ct >= 5 and ct < 8 then return "dawn"
	elseif ct >= 8 and ct < 17 then return "day"
	elseif ct >= 17 and ct < 20 then return "evening"
	else return "night" end
end

--==============================================================
-- SKY / ATMOSPHERE / EFFECTS
--==============================================================
local sky = Lighting:FindFirstChildOfClass("Sky") or Instance.new("Sky", Lighting)
for _, v in ipairs(Lighting:GetChildren()) do
	if v:IsA("Sky") then pcall(function() v.CelestialBodiesShown=false; v.SunAngularSize=0; v.MoonAngularSize=0 end) end
end

local atm = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
atm.Density = S.atmDensity; atm.Offset = 0.25; atm.Glare = 0.3; atm.Parent = Lighting
local rays = Lighting:FindFirstChildOfClass("SunRaysEffect") or Instance.new("SunRaysEffect")
rays.Intensity = 0.2; rays.Spread = 1; rays.Parent = Lighting
local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
bloom.Intensity = 1.2; bloom.Size = 24; bloom.Threshold = 1.05; bloom.Parent = Lighting
local ccFx = Lighting:FindFirstChild("__AtmosCC") or Instance.new("ColorCorrectionEffect")
ccFx.Name = "__AtmosCC"; ccFx.Parent = Lighting
local ccPhase = Lighting:FindFirstChild("__AtmosPhaseCC") or Instance.new("ColorCorrectionEffect")
ccPhase.Name = "__AtmosPhaseCC"; ccPhase.Parent = Lighting
local blurFx = Lighting:FindFirstChild("__AtmosBlur") or Instance.new("BlurEffect")
blurFx.Name = "__AtmosBlur"; blurFx.Size = 0; blurFx.Parent = Lighting
Lighting.GlobalShadows = true

--==============================================================
-- ОБЛАКА
--==============================================================
local clouds
if Terrain then
	clouds = Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover = S.cloudCover; clouds.Density = S.cloudDensity
	clouds.Color = Color3.fromRGB(255,255,255); clouds.Enabled = true
	clouds.Parent = Terrain
end

--==============================================================
-- FX ROOT + СВЕТИЛА С ТЕКСТУРАМИ
--==============================================================
local oldfx = Workspace:FindFirstChild("__AtmosFX")
if oldfx then oldfx:Destroy() end
local fx = Instance.new("Folder"); fx.Name = "__AtmosFX"; fx.Parent = Workspace

-- Пытаемся загрузить модель Roblox-ассета (работает в executor'е)
local function tryLoadAssetModel(assetId)
	if not assetId or assetId == "" or assetId == "rbxassetid://0" then return nil end
	local ok, objs = pcall(function() return game:GetObjects(assetId) end)
	if not ok or not objs or #objs == 0 then return nil end
	local m = objs[1]
	if not m:IsA("Model") then
		local wrap = Instance.new("Model")
		m.Parent = wrap
		m = wrap
	end
	return m
end

local function normalizeVisualPart(d)
	if d:IsA("BasePart") then
		d.Anchored = true; d.CanCollide = false; d.CastShadow = false
		pcall(function() d.CanQuery = false; d.CanTouch = false end)
	end
end

local function setVisualCFrame(v, cf)
	if not v then return end
	if v:IsA("BasePart") then v.CFrame = cf; return end
	if v:IsA("Model") then pcall(function() v:PivotTo(cf) end) end
end

local function setVisualTransparency(v, t)
	if not v then return end
	if v:IsA("BasePart") then v.Transparency = t; return end
	if v:IsA("Model") then
		for _, d in ipairs(v:GetDescendants()) do
			if d:IsA("BasePart") then d.Transparency = t
			elseif d:IsA("Decal") or d:IsA("Texture") then d.Transparency = t end
		end
	end
end

local function setVisualScale(v, factor)
	if not v then return end
	if v:IsA("Model") then
		local ok = pcall(function() v:ScaleTo(factor) end)
		if not ok then return end
	elseif v:IsA("BasePart") then
		v.Size = Vector3.new(factor, factor, factor)
	end
end

local function makeCelestial(name, color, assetId, fallbackSize)
	local root = Instance.new("Part")
	root.Name = name; root.Anchored=true; root.CanCollide=false; root.CastShadow=false
	root.Transparency = 1; root.Size = Vector3.new(1,1,1)
	pcall(function() root.CanQuery=false; root.CanTouch=false end)
	root.Parent = fx

	local light = Instance.new("PointLight")
	light.Range=60; light.Brightness=2; light.Color=color; light.Parent=root

	local visual
	local model = tryLoadAssetModel(assetId)
	if model then
		model.Name = name.."_Model"
		model.Parent = fx
		for _, d in ipairs(model:GetDescendants()) do normalizeVisualPart(d) end
		visual = model
	else
		local ball = Instance.new("Part")
		ball.Name = name.."_Ball"
		ball.Anchored=true; ball.CanCollide=false; ball.CastShadow=false
		ball.Material=Enum.Material.Neon; ball.Color=color
		ball.Shape=Enum.PartType.Ball
		ball.Size=Vector3.new(fallbackSize, fallbackSize, fallbackSize)
		pcall(function() ball.CanQuery=false; ball.CanTouch=false end)
		ball.Parent = fx
		visual = ball
	end

	return root, light, visual
end

local sunPart,  sunLight,  sunVisual  = makeCelestial("Sun",  Color3.fromRGB(255,240,200), SUN_ASSET,  350)
local moonPart, moonLight, moonVisual = makeCelestial("Moon", Color3.fromRGB(200,215,255), MOON_ASSET, 350)

--==============================================================
-- ПОГОДА
--==============================================================
local weatherPart = Instance.new("Part")
weatherPart.Name = "__AtmosWeather"; weatherPart.Anchored = true; weatherPart.CanCollide = false
weatherPart.Transparency = 1; weatherPart.Size = Vector3.new(90, 2, 90)
pcall(function() weatherPart.CanQuery = false; weatherPart.CanTouch = false end)
weatherPart.Parent = fx
local emitter = Instance.new("ParticleEmitter")
emitter.Enabled = false; emitter.Rate = 0
emitter.EmissionDirection = Enum.NormalId.Bottom
emitter.Parent = weatherPart
local WEATHER_RATE = { rain = 260, snow = 120, hail = 200 }

local function applyWeather()
	local k = S.weather
	if k == "none" then emitter.Enabled = false; emitter.Rate = 0; return end
	emitter.Enabled = true
	if k == "rain" then
		emitter.Color = ColorSequence.new(Color3.fromRGB(170,190,220))
		emitter.Lifetime = NumberRange.new(0.8, 1.0)
		emitter.Speed = NumberRange.new(90, 110)
		emitter.Acceleration = Vector3.new(0, -180, 0)
		emitter.SpreadAngle = Vector2.new(8, 8)
		emitter.Size = NumberSequence.new(0.25)
		emitter.Transparency = NumberSequence.new(0.3)
		emitter.Rotation = NumberRange.new(0, 0)
		pcall(function() emitter.Squash = NumberSequence.new(6) end)
		emitter.LightEmission = 0.3
	elseif k == "snow" then
		emitter.Color = ColorSequence.new(Color3.fromRGB(255,255,255))
		emitter.Lifetime = NumberRange.new(3, 4)
		emitter.Speed = NumberRange.new(8, 14)
		emitter.Acceleration = Vector3.new(2, -9, 0)
		emitter.SpreadAngle = Vector2.new(40, 40)
		emitter.Size = NumberSequence.new(0.35)
		emitter.Transparency = NumberSequence.new(0.1)
		emitter.Rotation = NumberRange.new(0, 360)
		pcall(function() emitter.Squash = NumberSequence.new(0) end)
		emitter.LightEmission = 0.5
	elseif k == "hail" then
		emitter.Color = ColorSequence.new(Color3.fromRGB(220,235,245))
		emitter.Lifetime = NumberRange.new(0.7, 0.9)
		emitter.Speed = NumberRange.new(120, 150)
		emitter.Acceleration = Vector3.new(0, -260, 0)
		emitter.SpreadAngle = Vector2.new(6, 6)
		emitter.Size = NumberSequence.new(0.3)
		emitter.Transparency = NumberSequence.new(0.1)
		emitter.Rotation = NumberRange.new(0, 360)
		pcall(function() emitter.Squash = NumberSequence.new(1.5) end)
		emitter.LightEmission = 0.4
	end
end

--==============================================================
-- МОЛНИИ (v8 core feature)
--==============================================================
local flashGui = Instance.new("ScreenGui")
flashGui.Name = "__AtmosFlash"; flashGui.ResetOnSpawn = false; flashGui.IgnoreGuiInset = true
flashGui.DisplayOrder = 1000; flashGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
local flashFrame = Instance.new("Frame")
flashFrame.Size = UDim2.new(1,0,1,0); flashFrame.BackgroundColor3 = Color3.fromRGB(255,255,255)
flashFrame.BackgroundTransparency = 1; flashFrame.BorderSizePixel = 0; flashFrame.Parent = flashGui

local function getBoltTex()
	local picks = {}
	for _, id in ipairs(BOLT_TEX) do
		if id and id ~= "" and id ~= "rbxassetid://0" then table.insert(picks, id) end
	end
	if #picks == 0 then return DEFAULT_BOLT_FALLBACK end
	return picks[rnd(1, #picks)]
end
local function getThunderId()
	local picks = {}
	for _, id in ipairs(THUNDER_SOUNDS) do
		if id and id ~= "" and id ~= "rbxassetid://0" then table.insert(picks, id) end
	end
	if #picks == 0 then return DEFAULT_THUNDER_FALLBACK end
	return picks[rnd(1, #picks)]
end

-- построить ломаную от A к B с зигзагом + вернуть массив точек
local function jaggedPath(a, b, segments, disp)
	local pts = {a}
	local dir = (b - a)
	for i = 1, segments - 1 do
		local t = i / segments
		local base = a + dir * t
		local perp1 = Vector3.new(-dir.Z, 0, dir.X).Unit
		local perp2 = Vector3.new(0, 1, 0):Cross(dir.Unit)
		if perp2.Magnitude < 0.01 then perp2 = Vector3.new(1,0,0) end
		perp2 = perp2.Unit
		local offset = perp1 * (rnd()*2-1) * disp + perp2 * (rnd()*2-1) * disp
		table.insert(pts, base + offset)
	end
	table.insert(pts, b)
	return pts
end

-- нарисовать одну ветку молнии beam'ами между точками; возвращает список Part'ов/Beam'ов для очистки
local function drawBolt(points, width0, width1, lifetime, tex, brightness)
	local parts = {}
	for i = 1, #points - 1 do
		local p1, p2 = points[i], points[i+1]
		local a = Instance.new("Part")
		a.Anchored=true; a.CanCollide=false; a.Transparency=1; a.Size=Vector3.new(0.1,0.1,0.1)
		pcall(function() a.CanQuery=false; a.CanTouch=false end)
		a.Position = p1; a.Parent = fx
		local b = Instance.new("Part")
		b.Anchored=true; b.CanCollide=false; b.Transparency=1; b.Size=Vector3.new(0.1,0.1,0.1)
		pcall(function() b.CanQuery=false; b.CanTouch=false end)
		b.Position = p2; b.Parent = fx
		local at1 = Instance.new("Attachment", a)
		local at2 = Instance.new("Attachment", b)
		local beam = Instance.new("Beam")
		beam.Attachment0 = at1; beam.Attachment1 = at2
		local segT = (i-1)/math.max(1, #points-1)
		beam.Width0 = width0 * (1 - segT*0.3)
		beam.Width1 = width1 * (1 - (segT+0.1)*0.3)
		beam.Texture = tex
		beam.TextureMode = Enum.TextureMode.Stretch
		beam.TextureLength = (p2 - p1).Magnitude
		beam.Color = ColorSequence.new(Color3.fromRGB(210,220,255))
		beam.LightEmission = brightness or 1
		beam.LightInfluence = 0
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 0),
		})
		beam.FaceCamera = true
		beam.Parent = a
		table.insert(parts, a); table.insert(parts, b)
		Debris:AddItem(a, lifetime)
		Debris:AddItem(b, lifetime)
	end
	return parts
end

-- fade beam'ов через несколько кадров (плавное затухание вместо резкого удаления)
local function fadeBolt(parts, fadeDur)
	task.spawn(function()
		local t = 0
		while t < fadeDur do
			local dt = task.wait()
			t = t + dt
			local a = t / fadeDur
			for _, p in ipairs(parts) do
				if p and p.Parent then
					for _, ch in ipairs(p:GetChildren()) do
						if ch:IsA("Attachment") then
							for _, bm in ipairs(ch:GetChildren()) do
								if bm:IsA("Beam") then
									bm.Transparency = NumberSequence.new(a)
								end
							end
						end
					end
				end
			end
		end
	end)
end

--==============================================================
-- SHOCKWAVE С ИСКАЖЕНИЕМ СВЕТА (fake Schlieren)
--==============================================================
-- Камера-постэффекты для артефакта искажения (Blur + ColorCorrection в Lighting)
local shockBlur = Lighting:FindFirstChild("__ShockBlur") or Instance.new("BlurEffect")
shockBlur.Name = "__ShockBlur"; shockBlur.Size = 0; shockBlur.Parent = Lighting
local shockCC = Lighting:FindFirstChild("__ShockCC") or Instance.new("ColorCorrectionEffect")
shockCC.Name = "__ShockCC"; shockCC.Saturation = 0; shockCC.Contrast = 0; shockCC.TintColor = Color3.new(1,1,1)
shockCC.Parent = Lighting

-- Список активных шокволн для трека (position, currentRadius, maxRadius, thickness)
local activeShockwaves = {}

-- Анимация + проверка камеры каждый кадр
RunService.Heartbeat:Connect(function(dt)
	local cam = Workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or Vector3.new()
	local totalDistort = 0
	local totalTintShift = 0
	for i = #activeShockwaves, 1, -1 do
		local sw = activeShockwaves[i]
		sw.t = sw.t + dt
		local a = sw.t / sw.duration
		if a >= 1 then
			if sw.part and sw.part.Parent then sw.part:Destroy() end
			table.remove(activeShockwaves, i)
		else
			local r = sw.radius0 + (sw.radiusMax - sw.radius0) * a
			sw.currentRadius = r
			if sw.part and sw.part.Parent then
				sw.part.Size = Vector3.new(r*2, r*2, r*2)
				-- полупрозрачная оболочка (тонкий фронт волны)
				sw.part.Transparency = 0.55 + a * 0.45
			end
			-- Проверяем проходит ли фронт волны через камеру
			local distToCam = (sw.pos - camPos).Magnitude
			local edge = math.abs(distToCam - r) -- как близко фронт к камере
			local thickness = sw.thickness or 8
			if edge < thickness then
				local proximity = 1 - (edge / thickness)  -- 1 = в центре фронта, 0 = на краю
				-- чем моложе волна — тем сильнее искажение (энергия рассеивается)
				local energyLeft = 1 - a
				totalDistort = totalDistort + proximity * energyLeft * (sw.power or 1)
				totalTintShift = totalTintShift + proximity * energyLeft * (sw.power or 1) * 0.5
			end
		end
	end
	-- Применяем искажения (плавно затухают)
	shockBlur.Size = shockBlur.Size * 0.5 + math.min(totalDistort * 24, 24) * 0.5
	shockCC.Contrast = shockCC.Contrast * 0.7 + math.min(totalDistort * 0.3, 0.3) * 0.3
	shockCC.Saturation = shockCC.Saturation * 0.7 + math.min(totalDistort * 0.15, 0.15) * 0.3
	-- цветовой сдвиг (chromatic aberration имитация)
	if totalTintShift > 0.01 then
		local wobble = math.sin(tick() * 50) * 0.05 * totalTintShift
		shockCC.TintColor = Color3.new(1 + wobble, 1, 1 - wobble)
	else
		shockCC.TintColor = Color3.new(1, 1, 1)
	end
	-- Камера-сшейк если волна прямо в лицо
	if totalDistort > 0.3 and cam then
		local shake = totalDistort * 0.3
		local offset = CFrame.new(
			(math.random()*2-1) * shake,
			(math.random()*2-1) * shake,
			(math.random()*2-1) * shake
		)
		-- мягкое смещение через CameraOffset если есть humanoid
		local char = LocalPlayer.Character
		if char then
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.CameraOffset = hum.CameraOffset:Lerp(offset.Position, 0.3)
			end
		end
	end
end)

local function spawnShockwave(pos, maxRadius, duration, power)
	maxRadius = maxRadius or 60
	duration = duration or 0.9
	power = power or 1

	-- Прозрачный шар-оболочка (волна)
	local shell = Instance.new("Part")
	shell.Name = "__Shockwave"
	shell.Anchored = true; shell.CanCollide = false; shell.CastShadow = false
	shell.Material = Enum.Material.ForceField; shell.Color = Color3.fromRGB(255,255,255)
	shell.Shape = Enum.PartType.Ball
	shell.Size = Vector3.new(4,4,4); shell.Transparency = 0.5
	pcall(function() shell.CanQuery=false; shell.CanTouch=false end)
	shell.Position = pos
	shell.Parent = fx

	-- Flipbook частицы на оболочке (4x4 грид, 16 кадров)
	local fp = Instance.new("ParticleEmitter")
	fp.Texture = SHOCKWAVE_TEX
	fp.LightEmission = 0.9; fp.LightInfluence = 0
	fp.Color = ColorSequence.new(Color3.fromRGB(255,255,255))
	fp.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, maxRadius * 0.6),
		NumberSequenceKeypoint.new(1, maxRadius * 1.4),
	})
	fp.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.5, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	fp.Lifetime = NumberRange.new(duration, duration)
	fp.Rate = 0
	fp.Speed = NumberRange.new(0, 0)
	fp.Rotation = NumberRange.new(0, 360)
	fp.RotSpeed = NumberRange.new(-30, 30)
	-- flipbook настройка (если движок Roblox поддерживает)
	pcall(function() fp.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4 end)
	pcall(function() fp.FlipbookMode = Enum.ParticleFlipbookMode.OneShot end)
	pcall(function() fp.FlipbookFramerate = NumberRange.new(16/duration, 16/duration) end)
	pcall(function() fp.FlipbookStartRandom = false end)
	fp.Parent = shell
	fp:Emit(3) -- несколько слоёв для объёмности

	table.insert(activeShockwaves, {
		part = shell, pos = pos,
		radius0 = 2, radiusMax = maxRadius, currentRadius = 2,
		t = 0, duration = duration,
		thickness = math.max(6, maxRadius * 0.15),
		power = power,
	})

	Debris:AddItem(shell, duration + 0.5)
end

-- IMPACT FX на месте удара молнии
local function makeImpact(pos)
	-- УДАРНАЯ ВОЛНА (с искажением света при прохождении через камеру)
	spawnShockwave(pos + Vector3.new(0, 1, 0), 55, 0.8, 1.0)
	-- вспышка-точка (Neon шарик + PointLight)
	local glow = Instance.new("Part")
	glow.Name = "__Impact"
	glow.Anchored=true; glow.CanCollide=false; glow.CastShadow=false
	glow.Material=Enum.Material.Neon; glow.Color=Color3.fromRGB(230,240,255)
	glow.Shape=Enum.PartType.Ball; glow.Size=Vector3.new(6,6,6)
	pcall(function() glow.CanQuery=false; glow.CanTouch=false end)
	glow.Position = pos + Vector3.new(0, 0.5, 0); glow.Parent = fx
	local pl = Instance.new("PointLight", glow)
	pl.Range = 60; pl.Brightness = 8; pl.Color = Color3.fromRGB(220,230,255)

	-- SPARK BURST (particles)
	local sparkPart = Instance.new("Part")
	sparkPart.Anchored=true; sparkPart.CanCollide=false; sparkPart.Transparency=1
	sparkPart.Size=Vector3.new(0.1,0.1,0.1); sparkPart.Position = pos + Vector3.new(0,0.5,0)
	pcall(function() sparkPart.CanQuery=false; sparkPart.CanTouch=false end)
	sparkPart.Parent = fx
	local sp = Instance.new("ParticleEmitter")
	sp.Texture = (SPARK_TEX ~= "" and SPARK_TEX ~= "rbxassetid://0") and SPARK_TEX or "rbxasset://textures/particles/sparkles_main.dds"
	sp.Color = ColorSequence.new(Color3.fromRGB(255,240,180))
	sp.LightEmission = 1; sp.LightInfluence = 0
	sp.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	sp.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	sp.Lifetime = NumberRange.new(0.3, 0.7)
	sp.Rate = 0
	sp.Speed = NumberRange.new(15, 40)
	sp.SpreadAngle = Vector2.new(180, 180)
	sp.Rotation = NumberRange.new(0, 360)
	sp.Parent = sparkPart
	sp:Emit(40)

	-- SMOKE
	local smokePart = Instance.new("Part")
	smokePart.Anchored=true; smokePart.CanCollide=false; smokePart.Transparency=1
	smokePart.Size=Vector3.new(0.1,0.1,0.1); smokePart.Position = pos + Vector3.new(0,1,0)
	pcall(function() smokePart.CanQuery=false; smokePart.CanTouch=false end)
	smokePart.Parent = fx
	local sm = Instance.new("ParticleEmitter")
	sm.Texture = (SMOKE_TEX ~= "" and SMOKE_TEX ~= "rbxassetid://0") and SMOKE_TEX or "rbxasset://textures/particles/smoke_main.dds"
	sm.Color = ColorSequence.new(Color3.fromRGB(90,90,100))
	sm.LightEmission = 0.05; sm.LightInfluence = 0.5
	sm.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2),
		NumberSequenceKeypoint.new(1, 8),
	})
	sm.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	sm.Lifetime = NumberRange.new(2, 4)
	sm.Rate = 0
	sm.Speed = NumberRange.new(3, 8)
	sm.SpreadAngle = Vector2.new(30, 30)
	sm.Acceleration = Vector3.new(0, 4, 0)
	sm.Parent = smokePart
	sm:Emit(15)

	-- SCORCH MARK (тёмный диск на земле)
	local scorch = Instance.new("Part")
	scorch.Anchored=true; scorch.CanCollide=false; scorch.CastShadow=false
	scorch.Material=Enum.Material.Slate; scorch.Color=Color3.fromRGB(20,20,25)
	scorch.Shape=Enum.PartType.Cylinder
	scorch.Size=Vector3.new(0.1, 8, 8)
	pcall(function() scorch.CanQuery=false; scorch.CanTouch=false end)
	scorch.CFrame = CFrame.new(pos) * CFrame.Angles(0,0,rad(90))
	scorch.Parent = fx

	-- анимация glow: пик -> угасание
	task.spawn(function()
		local t = 0
		while t < 0.4 do
			local dt = task.wait()
			t = t + dt
			local a = t / 0.4
			if glow.Parent then
				glow.Size = Vector3.new(6 + a*12, 6 + a*12, 6 + a*12)
				glow.Transparency = a
				pl.Brightness = 8 * (1 - a)
			end
		end
		if glow.Parent then glow:Destroy() end
	end)

	Debris:AddItem(sparkPart, 2)
	Debris:AddItem(smokePart, 6)
	Debris:AddItem(scorch, 30)
end

-- ГЛАВНАЯ ФУНКЦИЯ УДАРА
local function strikeLightning(groundPos)
	local cloudHeight = 250 + rnd()*150
	local cloudDrift = Vector3.new((rnd()*2-1)*80, 0, (rnd()*2-1)*80)
	local cloudPos = groundPos + Vector3.new(0, cloudHeight, 0) + cloudDrift

	-- "stepped leader" от облака вниз: несколько ступенек с паузами
	local tex = getBoltTex()
	local totalLen = (cloudPos - groundPos).Magnitude
	local segs = math.floor(totalLen / 15)
	segs = clamp(segs, 6, 24)

	-- downward leader
	local downPts = jaggedPath(cloudPos, groundPos, segs, 6)

	-- upward leader из земли навстречу (короткий, обычно 10-20% высоты)
	local upLen = totalLen * (0.10 + rnd()*0.10)
	local meetPt = groundPos + Vector3.new(0, upLen, 0) + Vector3.new((rnd()*2-1)*4, 0, (rnd()*2-1)*4)
	local upPts = jaggedPath(groundPos, meetPt, math.max(3, math.floor(upLen/8)), 3)

	-- рисуем downward leader (тусклый предварительный)
	local leaderParts = drawBolt(downPts, 2.5, 1.5, 0.6, tex, 0.7)
	task.wait(0.02)
	local upParts = drawBolt(upPts, 2, 1.2, 0.6, tex, 0.7)

	-- пауза перед return stroke
	task.wait(0.03)

	-- RETURN STROKE: мега-яркая версия всего канала снизу вверх
	local fullChannel = {}
	for _, p in ipairs(upPts) do table.insert(fullChannel, p) end
	for i = #downPts, 1, -1 do table.insert(fullChannel, downPts[i]) end
	local returnParts = drawBolt(fullChannel, 5, 3.5, 0.35, tex, 1)

	-- BRANCHES (несколько случайных ответвлений от главного канала)
	local nBranches = rnd(3, 6)
	local allBranchParts = {}
	for _ = 1, nBranches do
		local idx = rnd(2, #downPts - 2)
		local from = downPts[idx]
		local dir = Vector3.new((rnd()*2-1), -rnd()*0.5, (rnd()*2-1)).Unit
		local blen = 15 + rnd()*40
		local to = from + dir * blen
		local bp = jaggedPath(from, to, math.max(3, math.floor(blen/6)), 3)
		local parts = drawBolt(bp, 1.5, 0.4, 0.4, tex, 0.9)
		for _, p in ipairs(parts) do table.insert(allBranchParts, p) end
	end

	-- IMPACT
	makeImpact(groundPos)

	-- fade основного канала
	fadeBolt(returnParts, 0.3)
	fadeBolt(allBranchParts, 0.3)

	-- SCREEN FLASH
	local camPos = Camera.CFrame.Position
	local dist = (groundPos - camPos).Magnitude
	local proximity = clamp(1 - dist / 300, 0, 1)
	flashFrame.BackgroundTransparency = 0.1 + (1 - proximity) * 0.5
	local origBright = Lighting.Brightness
	Lighting.Brightness = origBright + 3 * (0.3 + proximity)
	task.delay(0.06, function() flashFrame.BackgroundTransparency = 0.5 + (1 - proximity) * 0.3 end)
	task.delay(0.15, function() flashFrame.BackgroundTransparency = 1; Lighting.Brightness = origBright end)

	-- ГРОМ с задержкой по расстоянию (30 studs = 1 метр приблизительно, скорость звука 343 m/s)
	-- Для игровой атмосферы упростим: 1 stud = 1 m, задержка = dist / 343 сек
	local thunderDelay = clamp(dist / 343, 0, 8)
	task.delay(thunderDelay, function()
		local s = Instance.new("Sound")
		s.SoundId = getThunderId()
		-- громкость по расстоянию (обратный квадрат урезанный)
		s.Volume = clamp(1.5 - dist/400, 0.15, 1.5)
		s.PlaybackSpeed = 0.9 + rnd()*0.2
		s.Parent = SoundService
		s:Play()
		Debris:AddItem(s, 15)
	end)
end

-- "Выстрелить" молнию рядом с игроком (или камерой если персонажа нет)
local function strikeNearPlayer(customPos)
	local targetPos
	if customPos then
		targetPos = customPos
	else
		local char = LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local origin = hrp and hrp.Position or Camera.CFrame.Position
		-- случайное направление вокруг игрока, расстояние в диапазоне [min,max]
		local angle = rnd() * pi * 2
		local dist = S.lightningMinDist + rnd() * (S.lightningMaxDist - S.lightningMinDist)
		targetPos = origin + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
		-- raycast вниз чтобы попасть в землю/крышу
		local ray = Workspace:Raycast(targetPos + Vector3.new(0, 200, 0), Vector3.new(0, -600, 0))
		if ray then targetPos = ray.Position end
	end
	strikeLightning(targetPos)
end

-- Авто-цикл: во время дождя/града кидает молнии с вероятностью S.lightningRate
task.spawn(function()
	while true do
		task.wait(3 + rnd() * 5)
		if S.lightning and (S.weather == "rain" or S.weather == "hail") then
			local chance = S.lightningRate * (S.weatherIntensity + 0.3)
			if rnd() < chance then
				strikeNearPlayer()
			end
		end
	end
end)

--==============================================================
-- ТОРНАДО (заглушка — пиши как хочешь, переделаю)
--==============================================================
local tornadoRoot
local function spawnTornado()
	if tornadoRoot then tornadoRoot:Destroy() end
	tornadoRoot = Instance.new("Model"); tornadoRoot.Name = "__Tornado"; tornadoRoot.Parent = fx
	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local origin = hrp and hrp.Position or Camera.CFrame.Position
	local base = origin + Vector3.new(0, 0, 0) + Vector3.new(60, 0, 60)
	for i = 0, 40 do
		local ring = Instance.new("Part")
		ring.Anchored=true; ring.CanCollide=false; ring.CastShadow=false
		ring.Material=Enum.Material.SmoothPlastic
		ring.Color = Color3.fromRGB(60,60,70)
		ring.Transparency = 0.4
		local w = 8 + i*0.6
		ring.Size = Vector3.new(w, 1, w)
		ring.Position = base + Vector3.new(0, i*3, 0)
		ring.Shape = Enum.PartType.Cylinder
		ring.CFrame = CFrame.new(ring.Position) * CFrame.Angles(0,0,rad(90))
		ring.Parent = tornadoRoot
	end
end
local function killTornado()
	if tornadoRoot then tornadoRoot:Destroy() tornadoRoot=nil end
end

--==============================================================
-- ГЛАВНЫЙ ЦИКЛ (шейдинг/светила/погода)
--==============================================================
local curPhase
local function applyPhase(name)
	if name == curPhase then return end
	curPhase = name
	local p = PHASES[name] or PHASES.day
	atm.Color = p.atm
	Lighting.OutdoorAmbient = p.ambient
	sunLight.Color = p.sun
	ccPhase.TintColor = p.tint
	ccPhase.Contrast = p.contrast
	ccPhase.Enabled = true
end

local t = 0
RunService.RenderStepped:Connect(function(dt)
	t += dt
	local camPos = Camera.CFrame.Position

	if S.dayNight then
		Lighting.ClockTime = (Lighting.ClockTime + dt * (24 / math.max(1, S.dayLength))) % 24
		S.timeOfDay = Lighting.ClockTime
	else
		Lighting.ClockTime = S.timeOfDay
	end
	local ct = Lighting.ClockTime
	local dayFactor = clamp(math.sin((ct/24)*pi*2 - pi/2)*0.5 + 0.5, 0, 1)
	applyPhase(phaseFromClock(ct))

	if clouds then
		clouds.Enabled = S.clouds
		if S.clouds then
			if S.cloudAnimate then
				clouds.Cover   = clamp(S.cloudCover   + 0.08*math.sin(t*0.03*S.cloudSpeed),   0, 1)
				clouds.Density = clamp(S.cloudDensity + 0.05*math.sin(t*0.02*S.cloudSpeed+1), 0, 1)
			else
				clouds.Cover = S.cloudCover; clouds.Density = S.cloudDensity
			end
			local cb = S.cloudColor * (0.45 + dayFactor*0.55)
			clouds.Color = Color3.fromRGB(255*cb, 255*cb, 255*cb)
		end
	end

	local sunDir  = Lighting:GetSunDirection()
	local moonDir = Lighting:GetMoonDirection()
	local sunPos  = camPos + sunDir  * CELESTIAL_DIST
	local moonPos = camPos + moonDir * CELESTIAL_DIST
	sunPart.CFrame  = CFrame.new(sunPos)
	moonPart.CFrame = CFrame.new(moonPos)
	setVisualCFrame(sunVisual,  CFrame.new(sunPos))
	setVisualCFrame(moonVisual, CFrame.new(moonPos))

	local sunVis  = clamp(dayFactor * 1.4, 0, 1)
	local moonVis = clamp((1-dayFactor) * 1.4, 0, 1)

	-- масштабируем модельки/шары по S.sunSize / S.moonSize (в единицах 350-baseline)
	local sunScale  = (S.sunSize  / 350) * (0.4 + sunVis  * 0.6) -- не даём совсем схлопнуться
	local moonScale = (S.moonSize / 350) * (0.4 + moonVis * 0.6)
	-- "далеко" — увеличиваем визуальный размер чтобы читалось на 8000 studs
	sunScale  = sunScale  * (CELESTIAL_DIST / 2500)
	moonScale = moonScale * (CELESTIAL_DIST / 2500)
	setVisualScale(sunVisual,  sunScale)
	setVisualScale(moonVisual, moonScale)

	setVisualTransparency(sunVisual,  1 - sunVis)
	setVisualTransparency(moonVisual, 1 - moonVis)

	local coverNow = (S.clouds and clouds) and clouds.Cover or 0
	local cloudBlock = 1 - coverNow*0.85
	sunLight.Brightness  = S.sunBright  * sunVis  * cloudBlock
	moonLight.Brightness = S.moonBright * moonVis * cloudBlock
	sunLight.Range = S.sunRange; moonLight.Range = S.sunRange
	sunLight.Enabled  = sunVis  > 0.02
	moonLight.Enabled = moonVis > 0.02

	Lighting.Brightness = 0.5 + dayFactor * S.maxBrightness
	atm.Density = S.atmosphere and S.atmDensity or 0
	atm.Haze    = S.atmHaze
	atm.Glare   = 0.2 + dayFactor * 0.5
	bloom.Enabled = S.bloom
	bloom.Intensity = 1.0 + dayFactor * 0.5
	ccFx.Enabled = S.sharpen
	ccFx.Contrast   = S.sharpenAmt
	ccFx.Saturation = S.sharpenAmt * 0.5
	blurFx.Enabled = S.blur
	blurFx.Size    = S.blur and S.blurAmt or 0
	rays.Enabled   = S.rays
	rays.Intensity = S.rays and (0.05 + dayFactor*0.22 + math.sin(t*1.5)*0.02) or 0
	rays.Spread    = 0.8 + dayFactor*0.4

	weatherPart.Position = camPos + Vector3.new(0, 60, 0)
	if emitter.Enabled and S.weather ~= "none" then
		emitter.Rate = (WEATHER_RATE[S.weather] or 0) * S.weatherIntensity
	end
end)

--==============================================================
-- FREECAM (springs)
--==============================================================
local Spring = {}; Spring.__index = Spring
function Spring.new(freq, pos) return setmetatable({f=freq, p=pos, v=pos*0}, Spring) end
function Spring:Update(dt, goal)
	local f = self.f * 2 * pi
	local p0, v0 = self.p, self.v
	local offset = goal - p0
	local decay = exp(-f*dt)
	local p1 = goal + (v0*dt - offset*(f*dt + 1))*decay
	local v1 = (f*dt*(offset*f - v0) + v0)*decay
	self.p, self.v = p1, v1
	return p1
end
function Spring:Reset(pos) self.p, self.v = pos, pos*0 end

local camPos2, camRot, camRoll, rollGoal, fovGoal, savedFov = Vector3.new(), Vector2.new(), 0, 0, 70, 70
local mouseDelta = Vector2.new()
local velSpring, rollSpring, fovSpring = Spring.new(6, Vector3.new()), Spring.new(5, 0), Spring.new(5, 0)
local PAN_SENS = 0.0042
local FREECAM_BIND = "AtmosFreecam"
local function down(k) return UserInputService:IsKeyDown(k) and 1 or 0 end

local function stepFreecam(dt)
	camRot = Vector2.new(
		clamp(camRot.X - mouseDelta.Y * PAN_SENS * S.sens, -rad(89), rad(89)),
		camRot.Y - mouseDelta.X * PAN_SENS * S.sens)
	mouseDelta = Vector2.new()
	rollGoal = rollGoal + (down(Enum.KeyCode.Z) - down(Enum.KeyCode.C)) * dt * rad(70)
	camRoll = rollSpring:Update(dt, rollGoal)
	local fov = fovSpring:Update(dt, fovGoal)
	local dir = Vector3.new(
		down(Enum.KeyCode.D) - down(Enum.KeyCode.A),
		down(Enum.KeyCode.E) - down(Enum.KeyCode.Q),
		down(Enum.KeyCode.S) - down(Enum.KeyCode.W))
	local sm = velSpring:Update(dt, dir)
	local speed = S.freeCamSpeed * (down(Enum.KeyCode.LeftShift)==1 and 3 or 1) * (down(Enum.KeyCode.LeftControl)==1 and 0.3 or 1)
	local cf = CFrame.new(camPos2) * CFrame.fromEulerAnglesYXZ(camRot.X, camRot.Y, camRoll)
	camPos2 = camPos2 + cf:VectorToWorldSpace(sm) * speed * dt
	Camera.CFrame = CFrame.new(camPos2) * CFrame.fromEulerAnglesYXZ(camRot.X, camRot.Y, camRoll)
	Camera.FieldOfView = fov
end

local function setFreecam(on)
	S.freeCam = on
	if on then
		local cf = Camera.CFrame
		camPos2 = cf.Position
		local rx, ry = cf:ToEulerAnglesYXZ()
		camRot = Vector2.new(rx, ry)
		rollGoal = 0; camRoll = 0; rollSpring:Reset(0)
		savedFov = Camera.FieldOfView
		fovGoal = savedFov; fovSpring:Reset(savedFov)
		velSpring:Reset(Vector3.new())
		Camera.CameraType = Enum.CameraType.Scriptable
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		RunService:BindToRenderStep(FREECAM_BIND, Enum.RenderPriority.Camera.Value + 1, stepFreecam)
	else
		pcall(function() RunService:UnbindFromRenderStep(FREECAM_BIND) end)
		Camera.CameraType = Enum.CameraType.Custom
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		Camera.FieldOfView = savedFov
	end
end

UserInputService.InputChanged:Connect(function(input)
	if not S.freeCam then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		mouseDelta = mouseDelta + Vector2.new(input.Delta.X, input.Delta.Y)
	elseif input.UserInputType == Enum.UserInputType.MouseWheel then
		fovGoal = clamp(fovGoal - input.Position.Z * 6, 10, 120)
	end
end)

--==============================================================
-- GUI
--==============================================================
local gui = Instance.new("ScreenGui")
gui.Name="AtmosSettings"; gui.ResetOnSpawn=false; gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
local parented = pcall(function() gui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
if not parented or not gui.Parent then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

local function rounded(o,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r or 8); c.Parent=o; return o end
local function pad(o,n) local p=Instance.new("UIPadding"); p.PaddingLeft=UDim.new(0,n); p.PaddingRight=UDim.new(0,n); p.Parent=o; return o end

local frame = rounded(Instance.new("Frame"))
frame.Size=UDim2.fromOffset(340,380); frame.Position=UDim2.new(0,20,0.5,-180)
frame.BackgroundColor3=Color3.fromRGB(18,20,28); frame.BackgroundTransparency=0.05
frame.BorderSizePixel=0; frame.Active=true; frame.Draggable=true; frame.Parent=gui
local stroke=Instance.new("UIStroke"); stroke.Color=Color3.fromRGB(60,70,100); stroke.Thickness=1; stroke.Parent=frame

local title=Instance.new("TextLabel")
title.Size=UDim2.new(1,0,0,36); title.BackgroundTransparency=1; title.Text="⚡ Atmosphere v8"
title.TextColor3=Color3.fromRGB(235,235,245); title.Font=Enum.Font.GothamBold; title.TextSize=15; title.Parent=frame

local tabBar=Instance.new("ScrollingFrame")
tabBar.Position=UDim2.new(0,8,0,38); tabBar.Size=UDim2.new(1,-16,0,30); tabBar.BackgroundTransparency=1
tabBar.BorderSizePixel=0; tabBar.ScrollBarThickness=3; tabBar.ScrollingDirection=Enum.ScrollingDirection.X
tabBar.AutomaticCanvasSize=Enum.AutomaticSize.X; tabBar.CanvasSize=UDim2.new(); tabBar.Parent=frame
local tabLay=Instance.new("UIListLayout"); tabLay.FillDirection=Enum.FillDirection.Horizontal
tabLay.Padding=UDim.new(0,4); tabLay.Parent=tabBar

local pages={}
local function showTab(target)
	for _, p in ipairs(pages) do
		p.page.Visible = (p.page == target.page)
		p.btn.BackgroundColor3 = (p.page == target.page) and Color3.fromRGB(70,110,235) or Color3.fromRGB(34,38,52)
	end
end
local function makeTab(name)
	local btn=rounded(Instance.new("TextButton"),6)
	btn.Size=UDim2.new(0,0,1,0); btn.AutomaticSize=Enum.AutomaticSize.X
	btn.BackgroundColor3=Color3.fromRGB(34,38,52); btn.Text=name; btn.Font=Enum.Font.GothamMedium
	btn.TextSize=11; btn.TextColor3=Color3.fromRGB(225,225,235); btn.Parent=tabBar
	pad(btn,7)
	local page=Instance.new("ScrollingFrame")
	page.Position=UDim2.new(0,8,0,72); page.Size=UDim2.new(1,-16,1,-80); page.BackgroundTransparency=1
	page.BorderSizePixel=0; page.ScrollBarThickness=4; page.CanvasSize=UDim2.new()
	page.AutomaticCanvasSize=Enum.AutomaticSize.Y; page.Visible=false; page.Parent=frame
	local lay=Instance.new("UIListLayout"); lay.Padding=UDim.new(0,7); lay.Parent=page
	local entry={btn=btn, page=page}
	table.insert(pages, entry)
	btn.MouseButton1Click:Connect(function() showTab(entry) end)
	return page
end

local function makeToggle(parent, label, key, onToggle)
	local row=rounded(Instance.new("TextButton"),6)
	row.Size=UDim2.new(1,0,0,32); row.BackgroundColor3=Color3.fromRGB(34,38,52); row.Text=""; row.Parent=parent
	local lbl=Instance.new("TextLabel")
	lbl.BackgroundTransparency=1; lbl.Position=UDim2.new(0,10,0,0); lbl.Size=UDim2.new(1,-60,1,0)
	lbl.TextXAlignment=Enum.TextXAlignment.Left; lbl.Text=label; lbl.Font=Enum.Font.Gotham; lbl.TextSize=14
	lbl.TextColor3=Color3.fromRGB(220,220,230); lbl.Parent=row
	local knob=rounded(Instance.new("Frame"),10); knob.Size=UDim2.fromOffset(38,18); knob.Position=UDim2.new(1,-48,0.5,-9); knob.Parent=row
	local dot=rounded(Instance.new("Frame"),8); dot.Size=UDim2.fromOffset(14,14); dot.BackgroundColor3=Color3.fromRGB(245,245,245); dot.Parent=knob
	local function render()
		knob.BackgroundColor3 = S[key] and Color3.fromRGB(80,180,120) or Color3.fromRGB(70,70,80)
		dot.Position = S[key] and UDim2.new(1,-16,0.5,-7) or UDim2.new(0,2,0.5,-7)
	end
	render()
	row.MouseButton1Click:Connect(function() S[key]=not S[key]; render(); if onToggle then onToggle(S[key]) end end)
end
local function makeSlider(parent, label, key, mn, mx)
	local row=rounded(Instance.new("Frame"),6)
	row.Size=UDim2.new(1,0,0,46); row.BackgroundColor3=Color3.fromRGB(34,38,52); row.Parent=parent
	local lbl=Instance.new("TextLabel")
	lbl.BackgroundTransparency=1; lbl.Position=UDim2.new(0,10,0,2); lbl.Size=UDim2.new(1,-20,0,18)
	lbl.TextXAlignment=Enum.TextXAlignment.Left; lbl.Font=Enum.Font.Gotham; lbl.TextSize=13
	lbl.TextColor3=Color3.fromRGB(220,220,230); lbl.Text=label..": "..string.format("%.2f", S[key]); lbl.Parent=row
	local bar=rounded(Instance.new("Frame"),4); bar.Position=UDim2.new(0,10,0,28); bar.Size=UDim2.new(1,-20,0,8)
	bar.BackgroundColor3=Color3.fromRGB(60,64,80); bar.Parent=row
	local fill=rounded(Instance.new("Frame"),4); fill.BackgroundColor3=Color3.fromRGB(80,150,235)
	fill.Size=UDim2.new((S[key]-mn)/(mx-mn),0,1,0); fill.Parent=bar
	local drag=false
	local function set(x)
		local rel=clamp((x-bar.AbsolutePosition.X)/bar.AbsoluteSize.X,0,1)
		fill.Size=UDim2.new(rel,0,1,0)
		S[key]=mn+(mx-mn)*rel
		lbl.Text=label..": "..string.format("%.2f", S[key])
	end
	bar.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then drag=true; set(i.Position.X) end end)
	UserInputService.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then drag=false end end)
	UserInputService.InputChanged:Connect(function(i) if drag and i.UserInputType==Enum.UserInputType.MouseMovement then set(i.Position.X) end end)
end
local function makeButton(parent, label, cb)
	local b = rounded(Instance.new("TextButton"), 6)
	b.Size = UDim2.new(1, 0, 0, 30); b.BackgroundColor3 = Color3.fromRGB(34,38,52)
	b.Text = label; b.Font = Enum.Font.GothamMedium; b.TextSize = 13
	b.TextColor3 = Color3.fromRGB(225,225,235); b.Parent = parent
	b.MouseButton1Click:Connect(cb)
	return b
end
local function makeLabel(parent, text)
	local l=rounded(Instance.new("TextLabel"),6)
	l.Size=UDim2.new(1,0,0,0); l.AutomaticSize=Enum.AutomaticSize.Y
	l.BackgroundColor3=Color3.fromRGB(28,32,44); l.BackgroundTransparency=0.15
	l.Text=text; l.Font=Enum.Font.Gotham; l.TextSize=12; l.TextWrapped=true
	l.TextColor3=Color3.fromRGB(200,205,220); l.TextXAlignment=Enum.TextXAlignment.Left; l.Parent=parent
	local p=Instance.new("UIPadding")
	p.PaddingLeft=UDim.new(0,8); p.PaddingRight=UDim.new(0,8); p.PaddingTop=UDim.new(0,6); p.PaddingBottom=UDim.new(0,6); p.Parent=l
	return l
end

-- Облака
local pC = makeTab("Облака")
makeToggle(pC, "Облака", "clouds")
makeToggle(pC, "Анимация", "cloudAnimate")
makeSlider(pC, "Покрытие", "cloudCover", 0, 1)
makeSlider(pC, "Плотность", "cloudDensity", 0, 1)
makeSlider(pC, "Цвет", "cloudColor", 0.2, 1)
makeSlider(pC, "Скорость", "cloudSpeed", 0, 4)

-- День
local pD = makeTab("День")
makeToggle(pD, "Смена дня/ночи", "dayNight")
makeToggle(pD, "Атмосфера", "atmosphere")
makeToggle(pD, "Bloom", "bloom")
makeToggle(pD, "Лучи солнца", "rays")
makeSlider(pD, "Время суток", "timeOfDay", 0, 24)
makeSlider(pD, "Длина дня (сек)", "dayLength", 30, 600)
makeSlider(pD, "Яркость", "maxBrightness", 0, 6)
makeSlider(pD, "Плотность атм.", "atmDensity", 0, 1)
makeSlider(pD, "Дымка", "atmHaze", 0, 3)

-- Светила
local pS = makeTab("Светила")
makeLabel(pS, "Sun/Moon = модели из Store (8430326250 / 8430423571). Через game:GetObjects, если executor даёт доступ. Дистанция 8000 studs.")
makeSlider(pS, "Размер солнца", "sunSize", 50, 1500)
makeSlider(pS, "Яркость солнца", "sunBright", 0, 8)
makeSlider(pS, "Размер луны", "moonSize", 50, 1500)
makeSlider(pS, "Яркость луны", "moonBright", 0, 8)

-- Эффекты
local pFx = makeTab("Эффекты")
makeToggle(pFx, "Резкость", "sharpen")
makeSlider(pFx, "Сила резкости", "sharpenAmt", 0, 1)
makeToggle(pFx, "Размытие", "blur")
makeSlider(pFx, "Сила размытия", "blurAmt", 0, 40)

-- Погода
local pW = makeTab("Погода")
makeButton(pW, "☀ Ясно",  function() S.weather="none"; applyWeather() end)
makeButton(pW, "🌧 Дождь", function() S.weather="rain"; applyWeather() end)
makeButton(pW, "❄ Снег",  function() S.weather="snow"; applyWeather() end)
makeButton(pW, "🌨 Град",  function() S.weather="hail"; applyWeather() end)
makeSlider(pW, "Интенсивность", "weatherIntensity", 0, 1)

-- Молнии
local pL = makeTab("Молнии")
makeLabel(pL, "Молнии бьют РЯДОМ с игроком (не с камерой). На месте удара — искры, дым, ожог + УДАРНАЯ ВОЛНА с искажением света когда проходит через камеру.\nТекстура beam: 73663492833517. Shockwave flipbook: 70564074541084.")
makeToggle(pL, "Молнии в грозу (авто)", "lightning")
makeSlider(pL, "Частота", "lightningRate", 0, 1)
makeSlider(pL, "Мин. дистанция", "lightningMinDist", 10, 200)
makeSlider(pL, "Макс. дистанция", "lightningMaxDist", 30, 400)
makeButton(pL, "⚡ Молния возле меня", function() strikeNearPlayer() end)
makeButton(pL, "⚡⚡⚡ ЗАЛП (5 молний)", function()
	task.spawn(function()
		for i=1,5 do
			strikeNearPlayer()
			task.wait(0.15 + rnd()*0.4)
		end
	end)
end)

-- Торнадо
local pT = makeTab("Торнадо")
makeLabel(pT, "Сейчас заглушка (столб из колец рядом с игроком). Опиши как хочешь — сделаю: воронка с частицами, засасывание, движение по пути, дамаг и т.д.")
makeButton(pT, "🌪 Заспавнить торнадо", function() spawnTornado() end)
makeButton(pT, "🗑 Убрать торнадо", function() killTornado() end)

-- Камера
local pCam = makeTab("Камера")
makeLabel(pCam, "Shift+P — фрикам\nWASD — движение, E/Q — вверх/вниз\nZ/C — наклон, колесо — зум\nShift быстрее, Ctrl медленнее\nX — скрыть GUI")
makeSlider(pCam, "Скорость", "freeCamSpeed", 20, 400)
makeSlider(pCam, "Чувствительность", "sens", 0.2, 3)

showTab(pages[1])

--==============================================================
-- X: скрыть GUI + курсор
--==============================================================
local guiHidden = false
local savedGuis = {}
local function setGuiHidden(hide)
	guiHidden = hide
	pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, not hide) end)
	UserInputService.MouseIconEnabled = not hide
	local pg = LocalPlayer:FindFirstChild("PlayerGui")
	if hide then
		savedGuis = {}
		if pg then
			for _, g in ipairs(pg:GetChildren()) do
				if g:IsA("ScreenGui") and g ~= gui and g ~= flashGui and g.Enabled then
					table.insert(savedGuis, g); g.Enabled = false
				end
			end
		end
		gui.Enabled = false
	else
		for _, g in ipairs(savedGuis) do if g and g.Parent then g.Enabled = true end end
		gui.Enabled = true
	end
end

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.P and UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
		setFreecam(not S.freeCam)
	elseif input.KeyCode == Enum.KeyCode.X then
		setGuiHidden(not guiHidden)
	elseif input.KeyCode == Enum.KeyCode.RightShift then
		frame.Visible = not frame.Visible
	end
end)

print("[Atmosphere v9] OK — Sun/Moon Store models + lightning + shockwave готовы")
end)

if not ok then
	warn("[Atmosphere v9] ОШИБКА: " .. tostring(err))
	pcall(function()
		game:GetService("StarterGui"):SetCore("SendNotification", {Title="Atmosphere v9 ERROR", Text=tostring(err), Duration=8})
	end)
end
