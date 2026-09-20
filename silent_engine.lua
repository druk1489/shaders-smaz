--======================================================================
-- SMAZ STUDIO (SILENT ENGINE UI) - единый скрипт
-- Всё в одном: ядро Atmosphere + Tornado + Rain + Lightning + Reflections
-- + Presets + Control Panel в стиле Silent Engine UI.
-- Без лоадера и отдельных скриптов. Запуск:
-- loadstring(game:HttpGet("https://raw.githubusercontent.com/druk1489/shaders-smaz/main/silent_engine.lua"))()
-- Хоткеи: Shift+P - фрикам; RightControl (переназначается) - панель.
-- Настройки НЕ применяются при входе (blur/bloom/лучи/погода/модули - выкл).
--======================================================================

--############### MODULE: atmosphere_v9.lua ###############
--==============================================================
-- ATMOSPHERE / SHADERS v10 (SILENT ENGINE CORE)
-- Без собственной GUI: только ядро + API. Панель — Silent Engine.
-- Shift+P = фрикам (один хоткей).
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
	StarterGui:SetCore("SendNotification", {Title="Atmosphere SL (Silent Engine)", Text="Панель: SMAZ Studio — фрикам Shift+P", Duration=4})
end)

--==============================================================
-- НАСТРОЙКИ
--==============================================================
local S = {
	clouds=true, cloudAnimate=true, cloudCover=0.6, cloudDensity=0.55, cloudColor=0.9, cloudSpeed=0.5,
	rays=false, bloom=false, atmosphere=true,
	bloomIntensity=0, raysIntensity=0, raysSpread=0,
	dayNight=true, dayLength=240, timeOfDay=12,
	sunSize=350, sunBright=2, sunRange=60,
	moonSize=450, moonBright=1,
	maxBrightness=2.5, atmDensity=0.32, atmHaze=1.4,
	sharpen=false, sharpenAmt=0.2, blur=false, blurAmt=12, blurMode="global", blurMaxDist=250,
	weather="none", weatherIntensity=0.6,
	lightning=false, lightningRate=0.5,
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
	bloom.Intensity = (S.bloomIntensity and S.bloomIntensity > 0) and S.bloomIntensity or (1.0 + dayFactor * 0.5)
	ccFx.Enabled = S.sharpen
	ccFx.Contrast   = S.sharpenAmt
	ccFx.Saturation = S.sharpenAmt * 0.5
	if S.blur then
		local bsize = S.blurAmt
		if S.blurMode == "distance" then
			local cam = Camera
			local prm = RaycastParams.new()
			prm.FilterType = Enum.RaycastFilterType.Exclude
			prm.FilterDescendantsInstances = { cam }
			local hit = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * S.blurMaxDist, prm)
			local d = hit and hit.Distance or S.blurMaxDist
			bsize = S.blurAmt * math.clamp(d / math.max(1, S.blurMaxDist), 0, 1)
		end
		blurFx.Enabled = true
		blurFx.Size    = bsize
	else
		blurFx.Enabled = false
	end
	rays.Enabled   = S.rays
	rays.Intensity = (S.raysIntensity and S.raysIntensity > 0) and S.raysIntensity or (0.05 + dayFactor*0.22 + math.sin(t*1.5)*0.02)
	rays.Spread    = (S.raysSpread and S.raysSpread > 0) and S.raysSpread or (0.8 + dayFactor*0.4)

	weatherPart.Position = camPos + Vector3.new(0, 60, 0)
	if emitter.Enabled and S.weather ~= "none" then
		emitter.Rate = (WEATHER_RATE[S.weather] or 0) * S.weatherIntensity
	end
end)

--==============================================================
-- FREECAM (версия из Mythos admin — Quenty springs, стабильная)
-- Shift+P вкл/выкл; WASD движение, E/Q вверх/вниз,
-- удержание ПКМ + мышь = обзор, колесо = зум,
-- Shift медленно, Ctrl быстро.
--==============================================================
local FREECAM_BIND = "AtmosFreecam"

local FC_Spring = {}; FC_Spring.__index = FC_Spring
function FC_Spring.new(stiffness, dampingCoeff, dampingRatio, initialPos)
	local self = setmetatable({}, FC_Spring)
	dampingRatio = dampingRatio or 1
	local m = dampingCoeff * dampingCoeff / (4 * stiffness * dampingRatio * dampingRatio)
	self.k = stiffness / m
	self.d = -dampingCoeff / m
	self.x = initialPos
	self.t = initialPos
	self.v = initialPos * 0
	return self
end
function FC_Spring:Update(dt)
	local t, k, d, x0, v0 = self.t, self.k, self.d, self.x, self.v
	local a0 = k * (t - x0) + v0 * d
	local v1 = v0 + a0 * (dt / 2)
	local a1 = k * (t - (x0 + v0 * (dt / 2))) + v1 * d
	local v2 = v0 + a1 * (dt / 2)
	local a2 = k * (t - (x0 + v1 * (dt / 2))) + v2 * d
	local v3 = v0 + a2 * dt
	local x4 = x0 + (v0 + 2 * (v1 + v2) + v3) * (dt / 6)
	self.x, self.v = x4, v0 + (a0 + 2 * (a1 + a2) + k * (t - (x0 + v2 * dt)) + v3 * d) * (dt / 6)
	return x4
end
function FC_Spring:Reset(pos)
	self.x, self.v = pos, pos * 0
	self.t = pos
end

local FC = {
	rot = Vector2.new(),
	pan = Vector2.new(),
	pos = Vector3.new(),
	vel = FC_Spring.new(7 / 9, 1 / 3, 1, Vector3.new()),
	rotS = FC_Spring.new(7 / 9, 1 / 3, 1, Vector2.new()),
	fovS = FC_Spring.new(2, 1 / 3, 1, 70),
	rateFov = 0,
	savedFov = 70,
	savedCamType = nil,
	conns = {},
}
local FC_Clamp = function(x, mn, mx) return x < mn and mn or x > mx and mx or x end
local FC_Keys = {
	left = {"A"}, right = {"D"}, forward = {"W"},
	backward = {"S"}, up = {"Q"}, down = {"E"},
}
local function FC_KeyDown(list)
	for _, k in ipairs(list) do
		local kc = Enum.KeyCode[k]
		if kc and UserInputService:IsKeyDown(kc) then return true end
	end
	return false
end

local function FC_Step(dt)
	local cam = Camera
	if not cam then return end
	local kx = (FC_KeyDown(FC_Keys.right) and 1 or 0) - (FC_KeyDown(FC_Keys.left) and 1 or 0)
	local ky = (FC_KeyDown(FC_Keys.up) and 1 or 0) - (FC_KeyDown(FC_Keys.down) and 1 or 0)
	local kz = (FC_KeyDown(FC_Keys.backward) and 1 or 0) - (FC_KeyDown(FC_Keys.forward) and 1 or 0)
	local km = kx * kx + ky * ky + kz * kz
	if km > 1e-15 then
		local slow = 1
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
			slow = 1 / 4
		elseif UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
			slow = 3
		end
		km = slow / math.sqrt(km)
		kx = kx * km; ky = ky * km; kz = kz * km
	end

	FC.vel.t = Vector3.new(kx, ky, kz) * (S.freeCamSpeed or 140)
	FC.rotS.t = FC.pan
	FC.fovS.t = FC_Clamp(FC.fovS.t + dt * FC.rateFov * (-330), 5, 120)

	local fov = FC.fovS:Update(dt)
	local dPos = FC.vel:Update(dt) * Vector3.new(1, 0.75, 1)
	local dRot = FC.rotS:Update(dt) * (Vector2.new(0.85, 1) / 128) * (math.tan(fov * math.pi / 360) / math.tan(35 * math.pi / 180)) * (S.sens or 1)

	FC.rateFov = 0
	FC.pan = Vector2.new()
	FC.rot = FC.rot + dRot
	FC.rot = Vector2.new(FC_Clamp(FC.rot.X, -1.5, 1.5), FC.rot.Y)

	local c = CFrame.new(FC.pos) * CFrame.Angles(0, FC.rot.Y, 0) * CFrame.Angles(FC.rot.X, 0, 0) * CFrame.new(dPos)
	FC.pos = c.p
	cam.CFrame = c
	cam.Focus = c * CFrame.new(0, 0, -16)
	cam.FieldOfView = fov
end

-- колесо мыши = зум
local function FC_ProcessInput(input)
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		FC.rateFov = input.Position.Z
	end
end
table.insert(FC.conns, UserInputService.InputChanged:Connect(FC_ProcessInput))

-- удержание ПКМ = вращение камеры
local function FC_OnInput(input, processed)
	if processed or input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
	local conn = UserInputService.InputChanged:Connect(function(i, ip)
		if not ip and i.UserInputType == Enum.UserInputType.MouseMovement then
			local d = i.Delta
			FC.pan = FC.pan + Vector2.new(-d.Y, -d.X)
		end
	end)
	repeat
		input = UserInputService.InputEnded:Wait()
	until input.UserInputType == Enum.UserInputType.MouseButton2 or not S.freeCam
	FC.pan = Vector2.new()
	conn:Disconnect()
	if S.freeCam then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
end
table.insert(FC.conns, UserInputService.InputBegan:Connect(function(input, proc)
	if S.freeCam then FC_OnInput(input, proc) end
end))

local function setFreecam(on)
	S.freeCam = on
	if on then
		local cam = Camera
		local cf = cam.CFrame
		local lookVector = cf.lookVector.unit
		FC.rot = Vector2.new(math.asin(lookVector.Y), math.atan2(-lookVector.Z, lookVector.X) - math.pi / 2)
		FC.pos = cf.p
		FC.savedFov = cam.FieldOfView
		FC.fovS = FC_Spring.new(2, 1 / 3, 1, cam.FieldOfView)
		FC.vel:Reset(Vector3.new())
		FC.rotS:Reset(Vector2.new())
		FC.pan = Vector2.new()
		FC.rateFov = 0
		FC.savedCamType = cam.CameraType
		cam.CameraType = Enum.CameraType.Scriptable
		UserInputService.MouseIconEnabled = true
		RunService:BindToRenderStep(FREECAM_BIND, Enum.RenderPriority.Camera.Value, function(dt)
			FC_Step(math.min(dt, 0.1))
		end)
	else
		pcall(function() RunService:UnbindFromRenderStep(FREECAM_BIND) end)
		local cam = Camera
		pcall(function()
			cam.CameraType = FC.savedCamType or Enum.CameraType.Custom
			cam.FieldOfView = FC.savedFov
		end)
		cam.CameraType = FC.savedCamType or Enum.CameraType.Custom
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
end

local silent_input = UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.P and UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
		setFreecam(not S.freeCam)
	end
end)

print("[Atmosphere SL] OK — ядро без GUI (Silent Engine панель отдельно)")
-- Экспорт API для Control Panel и внешних скриптов
local genv = getgenv or function() return _G end
genv().SMAZ_ATMOS = {
	settings = S,
	get = function(k) return S[k] end,
	set = function(k, v)
		if k == "freeCam" then setFreecam(not not v) return S.freeCam end
		if S[k] ~= nil then S[k] = v end
		return S[k]
	end,
	getBlurMode = function() return S.blurMode end,
	setBlurMode = function(m) if m == "global" or m == "distance" then S.blurMode = m end end,
	setBlur = function(v) S.blur = not not v; end,
	isFreecam = function() return S.freeCam end,
	setFreecam = function(v) setFreecam(not not v) end,
	setGuiHidden = function() end,
	weather = {
		set = function(w) S.weather = w; applyWeather() end,
		get = function() return S.weather end,
		setIntensity = function(v) S.weatherIntensity = math.clamp(v, 0, 1) end,
	},
}
print("[Atmosphere SL] API SMAZ_ATMOS экспортирован в getgenv")
end)

if not ok then
	warn("[Atmosphere v9] ОШИБКА: " .. tostring(err))
	pcall(function()
		game:GetService("StarterGui"):SetCore("SendNotification", {Title="Atmosphere v9 ERROR", Text=tostring(err), Duration=8})
	end)
end

--############### MODULE: tornado_v10.lua ###############
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

--############### MODULE: rain_v11.lua ###############
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
	enabled = false, rain3D = true, screenDrops = true,
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

--############### MODULE: lightning_v12.lua ###############
-- Lightning v13 - no hotkeys, autoOn=false by default, SMAZ_LIGHTNING API

if getgenv and getgenv().__LIGHTNING_V12_LOADED then
	if getgenv().__LIGHTNING_V12_UNLOAD then pcall(getgenv().__LIGHTNING_V12_UNLOAD) end
end
if getgenv then getgenv().__LIGHTNING_V12_LOADED = true end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local BOLT_TEX = "rbxassetid://73663492833517"

local CFG = {
	GRID_W = 10, GRID_L = 10, GRID_H = 20, CELL = 12,
	leaderStepInterval = 0.02, branchProb = 0.22, maxLeaderSteps = 45,
	streamerCount = 5, streamerStartHeight = 4,
	returnStrokeDuration = 0.10, returnStrokeGlowDuration = 0.30,
	autoOn = false,   -- DEFAULT OFF
	autoStrikeMin = 6, autoStrikeMax = 22,
	edgeDistortDuration = 0.35,
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
	bb.Adornee = part; bb.Size = UDim2.new(size, 0, size, 0)
	bb.LightInfluence = 0; bb.AlwaysOnTop = false; bb.Parent = part
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

local function playEdgeDistortion()
	local pgui = player:FindFirstChildOfClass("PlayerGui")
	if not pgui then return end
	local g = Instance.new("ScreenGui")
	g.Name = "LightningV12_Edge"
	g.ResetOnSpawn = false; g.IgnoreGuiInset = true; g.DisplayOrder = 200
	g.Parent = pgui
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = Color3.fromRGB(190, 210, 255)
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
	local frame2 = frame:Clone(); frame2.Parent = g
	local grad2 = frame2:FindFirstChildOfClass("UIGradient")
	if grad2 then grad2.Rotation = 90 end
	task.spawn(function()
		local t0 = tick()
		while tick() - t0 < CFG.edgeDistortDuration do
			local p = (tick() - t0) / CFG.edgeDistortDuration
			local env = math.sin(p * math.pi)
			local wob = math.sin(p * 40) * 0.05 * env
			frame.Position = UDim2.new(0, math.floor(wob * 30), 0, math.floor(math.cos(p * 35) * env * 20))
			frame2.Position = UDim2.new(0, math.floor(-wob * 30), 0, math.floor(-math.cos(p * 35) * env * 20))
			frame.BackgroundTransparency = 0.75 + (1 - env) * 0.25
			frame2.BackgroundTransparency = 0.85 + (1 - env) * 0.15
			RunService.Heartbeat:Wait()
		end
		g:Destroy()
	end)
end

local function doStrike()
	local pp = playerPos()
	local groundY = groundYAt(pp.X, pp.Z)
	local ox = pp.X - CFG.GRID_W * CFG.CELL * 0.5
	local oz = pp.Z - CFG.GRID_L * CFG.CELL * 0.5
	local visited = {}; local frontier = {}; local groundTips = {}
	local sx = rng:NextInteger(0, CFG.GRID_W - 1)
	local sz = rng:NextInteger(0, CFG.GRID_L - 1)
	local sy = CFG.GRID_H - 1
	local startCell = {x = sx, y = sy, z = sz, parent = nil}
	visited[key(sx, sy, sz)] = startCell
	table.insert(frontier, startCell)
	local strikeFolder = Instance.new("Folder")
	strikeFolder.Name = "Strike"; strikeFolder.Parent = root
	local leaderVis = {}
	local function drawCell(cell, size, transp)
		local pos = cellCenter(ox, groundY, oz, cell.x, cell.y, cell.z)
		local part, img = makeBillboard(pos, size or 3, transp or 0.75)
		part.Parent = strikeFolder
		leaderVis[key(cell.x, cell.y, cell.z)] = {part = part, img = img, cell = cell}
	end
	drawCell(startCell, 3.5, 0.7)
	local streamers = {}; local streamerVis = {}
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
							visited[k] = newCell; drawCell(newCell, 3, 0.78)
							table.insert(newFrontier, newCell)
							if ny <= 0 then table.insert(groundTips, newCell) end
						end
					end
				end
			end
			frontier = newFrontier; steps = steps + 1
			if #streamers == 0 then
				local close = false
				for _, c in ipairs(frontier) do if c.y <= CFG.streamerStartHeight then close = true; break end end
				if close then
					for s = 1, CFG.streamerCount do
						local ssx = rng:NextInteger(0, CFG.GRID_W - 1); local ssz = rng:NextInteger(0, CFG.GRID_L - 1)
						local sc = {x = ssx, y = 0, z = ssz, parent = nil, isStreamer = true}
						table.insert(streamers, sc)
						local pos = cellCenter(ox, groundY, oz, ssx, 0, ssz)
						local part, img = makeBillboard(pos, 2.5, 0.55); part.Parent = strikeFolder
						streamerVis[key(ssx, 0, ssz)] = {part = part, img = img, cell = sc}
					end
				end
			end
			local grown = {}
			for _, sc in ipairs(streamers) do
				local nx = sc.x + rng:NextInteger(-1, 1); local ny = sc.y + 1; local nz = sc.z + rng:NextInteger(-1, 1)
				if nx >= 0 and nx < CFG.GRID_W and ny < CFG.GRID_H and nz >= 0 and nz < CFG.GRID_L then
					local k = key(nx, ny, nz)
					local newSC = {x = nx, y = ny, z = nz, parent = sc, isStreamer = true}
					if visited[k] then connectionLeader = visited[k]; connectionStreamer = newSC; break
					elseif not streamerVis[k] then
						table.insert(grown, newSC)
						local pos = cellCenter(ox, groundY, oz, nx, ny, nz)
						local part, img = makeBillboard(pos, 2.5, 0.6); part.Parent = strikeFolder
						streamerVis[k] = {part = part, img = img, cell = newSC}
					end
				end
			end
			for _, g in ipairs(grown) do table.insert(streamers, g) end
			task.wait(CFG.leaderStepInterval)
		end
		if not connectionLeader then for _, tip in ipairs(groundTips) do connectionLeader = tip; break end end
		if not connectionLeader then
			for _, v in pairs(leaderVis) do
				task.spawn(function()
					for i = 1, 20 do v.img.ImageTransparency = math.min(1, v.img.ImageTransparency + 0.05); task.wait(0.02) end
				end)
			end
			task.wait(0.5); strikeFolder:Destroy(); return
		end
		local path = {}
		local cur = connectionLeader
		while cur do table.insert(path, 1, cur); cur = cur.parent end
		if connectionStreamer then
			local spath = {}; local scur = connectionStreamer
			while scur do table.insert(spath, 1, scur); scur = scur.parent end
			for i = #spath, 1, -1 do table.insert(path, 1, spath[i]) end
		end
		local oldAmbient = Lighting.Ambient; local oldOutdoor = Lighting.OutdoorAmbient
		pcall(function() Lighting.Ambient = Color3.fromRGB(230, 235, 255); Lighting.OutdoorAmbient = Color3.fromRGB(210, 220, 250) end)
		pcall(playEdgeDistortion)
		local beams = {}
		for i = 1, #path - 1 do
			local c1 = path[i]; local c2 = path[i + 1]
			local p1 = cellCenter(ox, groundY, oz, c1.x, c1.y, c1.z)
			local p2 = cellCenter(ox, groundY, oz, c2.x, c2.y, c2.z)
			local b = makeBeam(p1, p2, 3.2, 0)
			b.a1.Parent = strikeFolder; b.a2.Parent = strikeFolder
			table.insert(beams, b)
		end
		local pathBillboards = {}
		for _, c in ipairs(path) do
			local pos = cellCenter(ox, groundY, oz, c.x, c.y, c.z)
			local part, img = makeBillboard(pos, 6, 0.05); part.Parent = strikeFolder
			img.ImageColor3 = Color3.fromRGB(255, 255, 255)
			table.insert(pathBillboards, img)
		end
		task.wait(CFG.returnStrokeDuration)
		local steps2 = 15
		for i = 1, steps2 do
			local t = i / steps2
			for _, b in ipairs(beams) do
				b.beam.Transparency = NumberSequence.new(t)
				b.beam.Width0 = 3.2 * (1 - t * 0.4); b.beam.Width1 = 3.2 * (1 - t * 0.4)
			end
			for _, img in ipairs(pathBillboards) do img.ImageTransparency = math.min(1, 0.05 + t * 0.95) end
			for _, v in pairs(leaderVis) do v.img.ImageTransparency = math.min(1, v.img.ImageTransparency + 0.05) end
			for _, v in pairs(streamerVis) do v.img.ImageTransparency = math.min(1, v.img.ImageTransparency + 0.05) end
			if i == 2 then pcall(function() Lighting.Ambient = oldAmbient; Lighting.OutdoorAmbient = oldOutdoor end) end
			task.wait(CFG.returnStrokeGlowDuration / steps2)
		end
		task.wait(0.1); strikeFolder:Destroy()
	end)
end

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

if getgenv then
	getgenv().SMAZ_LIGHTNING = {
		CFG = CFG,
		strike = function() task.spawn(doStrike) end,
		setAuto = function(v)
			CFG.autoOn = v
			if v then startAuto() end
		end,
		isAuto = function() return CFG.autoOn end,
	}
	getgenv().__LIGHTNING_V12_UNLOAD = function()
		CFG.autoOn = false
		if root then root:Destroy() end
		local pgui = player:FindFirstChildOfClass("PlayerGui")
		if pgui then local g = pgui:FindFirstChild("LightningV12_Edge"); if g then g:Destroy() end end
		getgenv().__LIGHTNING_V12_LOADED = nil; getgenv().__LIGHTNING_V12_UNLOAD = nil
		getgenv().SMAZ_LIGHTNING = nil
	end
end

print("[Lightning v13] Loaded (auto OFF), API: getgenv().SMAZ_LIGHTNING")

--############### MODULE: reflections_v1.lua ###############
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
	enabled = false,
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

--############### MODULE: presets_v1.lua ###############
-- Presets v1 - 20 lighting/graphics presets (adapted from ShaderUtilityV5), exposes SMAZ_PRESETS API

if getgenv and getgenv().__PRESETS_V1_LOADED then
	if getgenv().__PRESETS_V1_UNLOAD then pcall(getgenv().__PRESETS_V1_UNLOAD) end
end
if getgenv then getgenv().__PRESETS_V1_LOADED = true end

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local Terrain = Workspace:FindFirstChildOfClass("Terrain")

local function safe(fn) pcall(fn) end

local function rgb(r, g, b)
	return Color3.fromRGB(
		math.clamp(math.floor(r + 0.5), 0, 255),
		math.clamp(math.floor(g + 0.5), 0, 255),
		math.clamp(math.floor(b + 0.5), 0, 255)
	)
end

local created = {}

local function getEffect(name, className)
	local obj = Lighting:FindFirstChild(name)
	if not obj then
		obj = Instance.new(className)
		obj.Name = name
		obj.Parent = Lighting
		table.insert(created, obj)
	end
	return obj
end

local ColorCorrection = getEffect("SMAZ_P_ColorCorrection", "ColorCorrectionEffect")
local Bloom = getEffect("SMAZ_P_Bloom", "BloomEffect")
local SunRays = getEffect("SMAZ_P_SunRays", "SunRaysEffect")
local Blur = getEffect("SMAZ_P_Blur", "BlurEffect")
local DOF = getEffect("SMAZ_P_DepthOfField", "DepthOfFieldEffect")
local Atmosphere = getEffect("SMAZ_P_Atmosphere", "Atmosphere")
local Sky = getEffect("SMAZ_P_Sky", "Sky")

local Clouds
if Terrain then
	Clouds = Terrain:FindFirstChild("SMAZ_P_Clouds")
	if not Clouds then
		Clouds = Instance.new("Clouds")
		Clouds.Name = "SMAZ_P_Clouds"
		Clouds.Parent = Terrain
		table.insert(created, Clouds)
	end
end

local Values = {
	-- color
	CCBrightness = 0,
	CCContrast = 0.14,
	CCSaturation = 0.05,
	TintR = 255, TintG = 255, TintB = 255,

	-- lighting
	LightingBrightness = 2,
	Exposure = 0,
	ClockTime = 14.5,
	GeographicLatitude = 41.7,
	EnvironmentDiffuse = 0.55,
	EnvironmentSpecular = 0.75,

	AmbientR = 85, AmbientG = 85, AmbientB = 95,
	OutdoorR = 155, OutdoorG = 155, OutdoorB = 170,

	ColorShiftTopR = 255, ColorShiftTopG = 245, ColorShiftTopB = 230,
	ColorShiftBottomR = 0, ColorShiftBottomG = 0, ColorShiftBottomB = 0,

	FogR = 190, FogG = 205, FogB = 230,
	FogStart = 0, FogEnd = 100000,

	-- shadows
	GlobalShadows = true,
	AllPartShadows = true,
	ShadowSoftness = 0.35,
	ShadowAmbientPower = 0.55,
	ShadowContrastBoost = 0.05,

	-- effects
	BloomEnabled = true, BloomIntensity = 0.35, BloomSize = 28, BloomThreshold = 1.1,
	SunRaysEnabled = true, SunIntensity = 0.08, SunSpread = 0.65,
	BlurEnabled = true, BlurSize = 0,
	DOFEnabled = true, DOFFarIntensity = 0.12, DOFFocusDistance = 80, DOFInFocusRadius = 60, DOFNearIntensity = 0.03,

	-- atmosphere
	AtmosphereDensity = 0.22, AtmosphereOffset = 0.15, AtmosphereHaze = 0.8, AtmosphereGlare = 0.15,
	AtmosphereColorR = 200, AtmosphereColorG = 210, AtmosphereColorB = 255,
	AtmosphereDecayR = 100, AtmosphereDecayG = 110, AtmosphereDecayB = 130,

	-- water
	WaterR = 20, WaterG = 110, WaterB = 170,
	WaterTransparency = 0.25, WaterReflectance = 0.45, WaterWaveSize = 0.18, WaterWaveSpeed = 12,

	-- wind
	WindX = 0, WindY = 0, WindZ = 0,

	-- clouds
	CloudsEnabled = true, CloudCover = 0.45, CloudDensity = 0.35,
	CloudR = 240, CloudG = 245, CloudB = 255,

	-- sky
	SunSize = 11, MoonSize = 11, StarCount = 1200,

	-- camera
	FieldOfView = 70,
}

local Defaults = {}
for k, v in pairs(Values) do Defaults[k] = v end

local Presets = {
	Realistic = {
		CCBrightness = 0.02, CCContrast = 0.22, CCSaturation = 0.08,
		LightingBrightness = 2.2, Exposure = 0, ClockTime = 15.2,
		ShadowSoftness = 0.28, ShadowAmbientPower = 0.55, ShadowContrastBoost = 0.06,
		EnvironmentDiffuse = 0.55, EnvironmentSpecular = 0.85,
		BloomEnabled = true, BloomIntensity = 0.35, BloomSize = 30, BloomThreshold = 1.1,
		SunRaysEnabled = true, SunIntensity = 0.08,
		AtmosphereDensity = 0.22, AtmosphereHaze = 0.8,
		CloudCover = 0.45, CloudDensity = 0.35,
	},

	UltraRealistic = {
		CCBrightness = 0.015, CCContrast = 0.28, CCSaturation = 0.12,
		LightingBrightness = 2.4, Exposure = -0.02, ClockTime = 15.7,
		ShadowSoftness = 0.38, ShadowAmbientPower = 0.48, ShadowContrastBoost = 0.09,
		EnvironmentDiffuse = 0.48, EnvironmentSpecular = 0.95,
		BloomEnabled = true, BloomIntensity = 0.42, BloomSize = 34, BloomThreshold = 1.05,
		SunRaysEnabled = true, SunIntensity = 0.1, SunSpread = 0.7,
		AtmosphereDensity = 0.24, AtmosphereHaze = 1, AtmosphereGlare = 0.18,
		WaterReflectance = 0.55, WaterTransparency = 0.22,
		CloudCover = 0.5, CloudDensity = 0.42,
	},

	Cinematic = {
		CCBrightness = -0.03, CCContrast = 0.38, CCSaturation = -0.04,
		LightingBrightness = 1.6, Exposure = -0.08, ClockTime = 18.2,
		ShadowSoftness = 0.55, ShadowAmbientPower = 0.42, ShadowContrastBoost = 0.18,
		EnvironmentDiffuse = 0.35, EnvironmentSpecular = 1,
		BloomEnabled = true, BloomIntensity = 0.65, BloomSize = 44, BloomThreshold = 0.9,
		SunRaysEnabled = true, SunIntensity = 0.15, SunSpread = 0.82,
		AtmosphereDensity = 0.36, AtmosphereHaze = 1.55,
		DOFFarIntensity = 0.25, DOFNearIntensity = 0.08,
		CloudCover = 0.58, CloudDensity = 0.48,
	},

	GoldenHour = {
		CCBrightness = 0.03, CCContrast = 0.3, CCSaturation = 0.16,
		TintR = 255, TintG = 230, TintB = 200,
		LightingBrightness = 1.8, Exposure = -0.03, ClockTime = 17.8,
		ShadowSoftness = 0.6, ShadowAmbientPower = 0.45, ShadowContrastBoost = 0.14,
		BloomEnabled = true, BloomIntensity = 0.55, BloomSize = 42, BloomThreshold = 0.95,
		SunRaysEnabled = true, SunIntensity = 0.18, SunSpread = 0.9,
		AtmosphereDensity = 0.32, AtmosphereHaze = 1.4, AtmosphereGlare = 0.35,
		ColorShiftTopR = 255, ColorShiftTopG = 210, ColorShiftTopB = 160,
		CloudCover = 0.52, CloudDensity = 0.38,
	},

	Morning = {
		CCBrightness = 0.04, CCContrast = 0.16, CCSaturation = 0.1,
		TintR = 245, TintG = 250, TintB = 255,
		LightingBrightness = 2.5, Exposure = 0.03, ClockTime = 7.4,
		ShadowSoftness = 0.45, ShadowAmbientPower = 0.62,
		BloomEnabled = true, BloomIntensity = 0.28, BloomSize = 28,
		SunRaysEnabled = true, SunIntensity = 0.08,
		AtmosphereDensity = 0.2, AtmosphereHaze = 0.85,
		CloudCover = 0.35, CloudDensity = 0.25,
	},

	Night = {
		CCBrightness = -0.08, CCContrast = 0.32, CCSaturation = -0.15,
		TintR = 185, TintG = 205, TintB = 255,
		LightingBrightness = 0.8, Exposure = -0.22, ClockTime = 0,
		ShadowSoftness = 0.7, ShadowAmbientPower = 0.35,
		BloomEnabled = true, BloomIntensity = 0.8, BloomSize = 38, BloomThreshold = 0.78,
		SunRaysEnabled = false, SunIntensity = 0,
		AtmosphereDensity = 0.5, AtmosphereHaze = 2.25,
		CloudCover = 0.25, CloudDensity = 0.2,
	},

	NeonNight = {
		CCBrightness = -0.04, CCContrast = 0.45, CCSaturation = 0.3,
		TintR = 205, TintG = 215, TintB = 255,
		LightingBrightness = 1, Exposure = -0.12, ClockTime = 0.4,
		ShadowSoftness = 0.5, ShadowAmbientPower = 0.32, ShadowContrastBoost = 0.2,
		BloomEnabled = true, BloomIntensity = 1.15, BloomSize = 52, BloomThreshold = 0.65,
		SunRaysEnabled = false,
		AtmosphereDensity = 0.38, AtmosphereHaze = 1.8,
		CloudCover = 0.2, CloudDensity = 0.15,
	},

	Horror = {
		CCBrightness = -0.13, CCContrast = 0.5, CCSaturation = -0.4,
		TintR = 210, TintG = 225, TintB = 255,
		LightingBrightness = 0.65, Exposure = -0.28, ClockTime = 23.5,
		ShadowSoftness = 0.85, ShadowAmbientPower = 0.25, ShadowContrastBoost = 0.28,
		BloomEnabled = true, BloomIntensity = 0.2,
		BlurEnabled = true, BlurSize = 0.7,
		AtmosphereDensity = 0.65, AtmosphereHaze = 3.2,
		WindX = 18, WindZ = -12,
		CloudCover = 0.75, CloudDensity = 0.7,
	},

	Foggy = {
		CCBrightness = -0.02, CCContrast = 0.18, CCSaturation = -0.12,
		LightingBrightness = 1.35, Exposure = -0.05, ClockTime = 12.5,
		ShadowSoftness = 0.8, ShadowAmbientPower = 0.65,
		AtmosphereDensity = 0.75, AtmosphereHaze = 4.2, AtmosphereGlare = 0.08,
		FogStart = 15, FogEnd = 450,
		CloudCover = 0.95, CloudDensity = 0.85,
		CloudR = 205, CloudG = 210, CloudB = 220,
	},

	Rainy = {
		CCBrightness = -0.04, CCContrast = 0.24, CCSaturation = -0.18,
		TintR = 210, TintG = 225, TintB = 255,
		LightingBrightness = 1.2, Exposure = -0.1, ClockTime = 13,
		ShadowSoftness = 0.9, ShadowAmbientPower = 0.55,
		BloomEnabled = true, BloomIntensity = 0.4, BloomSize = 30,
		AtmosphereDensity = 0.55, AtmosphereHaze = 2.8,
		WaterReflectance = 0.75, WaterTransparency = 0.18,
		WaterWaveSize = 0.35, WaterWaveSpeed = 28,
		CloudCover = 1, CloudDensity = 0.9,
		WindX = 22, WindZ = -18,
	},

	WarmSoft = {
		CCBrightness = 0.03, CCContrast = 0.18, CCSaturation = 0.12,
		TintR = 255, TintG = 238, TintB = 220,
		LightingBrightness = 2.15, Exposure = 0.02, ClockTime = 16.2,
		ShadowSoftness = 0.75, ShadowAmbientPower = 0.58,
		BloomIntensity = 0.38, BloomSize = 36,
		AtmosphereDensity = 0.25, AtmosphereHaze = 1.1,
		CloudCover = 0.42, CloudDensity = 0.28,
	},

	ColdBlue = {
		CCBrightness = 0, CCContrast = 0.25, CCSaturation = -0.05,
		TintR = 205, TintG = 225, TintB = 255,
		LightingBrightness = 1.85, Exposure = -0.04, ClockTime = 12,
		ShadowSoftness = 0.45, ShadowAmbientPower = 0.5,
		AtmosphereDensity = 0.3, AtmosphereHaze = 1.35,
		CloudCover = 0.65, CloudDensity = 0.5,
	},

	Clean = {
		CCBrightness = 0.01, CCContrast = 0.12, CCSaturation = 0.04,
		TintR = 255, TintG = 255, TintB = 255,
		LightingBrightness = 2.1, Exposure = 0, ClockTime = 14,
		ShadowSoftness = 0.25, ShadowAmbientPower = 0.7, ShadowContrastBoost = 0.02,
		BloomEnabled = true, BloomIntensity = 0.12,
		SunRaysEnabled = true, SunIntensity = 0.03,
		BlurEnabled = false, DOFEnabled = false,
		AtmosphereDensity = 0.12, AtmosphereHaze = 0.25,
		CloudCover = 0.15, CloudDensity = 0.1,
	},

	Colorful = {
		CCBrightness = 0.04, CCContrast = 0.22, CCSaturation = 0.45,
		LightingBrightness = 2.25, Exposure = 0.04, ClockTime = 13.5,
		ShadowSoftness = 0.35, ShadowAmbientPower = 0.6,
		BloomEnabled = true, BloomIntensity = 0.5, BloomSize = 34,
		AtmosphereDensity = 0.18, AtmosphereHaze = 0.6,
		CloudCover = 0.3, CloudDensity = 0.2,
	},

	BlackWhite = {
		CCBrightness = 0, CCContrast = 0.42, CCSaturation = -1,
		TintR = 245, TintG = 245, TintB = 245,
		LightingBrightness = 1.8, Exposure = -0.03, ClockTime = 13,
		ShadowSoftness = 0.4, ShadowAmbientPower = 0.45, ShadowContrastBoost = 0.18,
		BloomIntensity = 0.18,
		AtmosphereDensity = 0.2, AtmosphereHaze = 0.8,
	},

	Desert = {
		CCBrightness = 0.04, CCContrast = 0.3, CCSaturation = 0.18,
		TintR = 255, TintG = 225, TintB = 180,
		LightingBrightness = 2.7, Exposure = 0.06, ClockTime = 13.2,
		ShadowSoftness = 0.22, ShadowAmbientPower = 0.62,
		AtmosphereDensity = 0.18, AtmosphereHaze = 1.25,
		FogR = 230, FogG = 205, FogB = 165,
		CloudCover = 0.08, CloudDensity = 0.05,
	},

	Winter = {
		CCBrightness = 0.03, CCContrast = 0.2, CCSaturation = -0.18,
		TintR = 220, TintG = 235, TintB = 255,
		LightingBrightness = 2.25, Exposure = 0.02, ClockTime = 11.5,
		ShadowSoftness = 0.5, ShadowAmbientPower = 0.58,
		AtmosphereDensity = 0.32, AtmosphereHaze = 1.5,
		FogR = 220, FogG = 230, FogB = 245,
		CloudCover = 0.7, CloudDensity = 0.55,
	},

	Dreamy = {
		CCBrightness = 0.06, CCContrast = 0.12, CCSaturation = 0.18,
		TintR = 255, TintG = 230, TintB = 255,
		LightingBrightness = 2, Exposure = 0.08, ClockTime = 16.8,
		ShadowSoftness = 0.9, ShadowAmbientPower = 0.72,
		BloomEnabled = true, BloomIntensity = 0.9, BloomSize = 70, BloomThreshold = 0.75,
		BlurEnabled = true, BlurSize = 0.35,
		DOFEnabled = true, DOFFarIntensity = 0.22, DOFNearIntensity = 0.08,
		AtmosphereDensity = 0.28, AtmosphereHaze = 1.4,
	},

	FPS = {
		CCBrightness = 0, CCContrast = 0.08, CCSaturation = 0.02,
		LightingBrightness = 2, Exposure = 0,
		GlobalShadows = false, AllPartShadows = false,
		ShadowSoftness = 0, ShadowAmbientPower = 0.9, ShadowContrastBoost = 0,
		BloomEnabled = false, SunRaysEnabled = false,
		BlurEnabled = false, DOFEnabled = false,
		AtmosphereDensity = 0.06, AtmosphereHaze = 0.1,
		CloudCover = 0, CloudDensity = 0,
	},

	LowEndClean = {
		CCBrightness = 0, CCContrast = 0.1, CCSaturation = 0.03,
		LightingBrightness = 2, Exposure = 0,
		GlobalShadows = true, AllPartShadows = false,
		ShadowSoftness = 0.15, ShadowAmbientPower = 0.8,
		BloomEnabled = false, SunRaysEnabled = false,
		BlurEnabled = false, DOFEnabled = false,
		AtmosphereDensity = 0.1, AtmosphereHaze = 0.2,
		CloudCover = 0.1, CloudDensity = 0.05,
	},
}

local PRESET_ORDER = {
	"Realistic", "UltraRealistic", "Cinematic", "GoldenHour", "Morning",
	"Night", "NeonNight", "Horror", "Dreamy", "BlackWhite",
	"Foggy", "Rainy", "Winter", "Desert",
	"Clean", "Colorful", "WarmSoft", "ColdBlue",
	"FPS", "LowEndClean",
}

local PRETTY = {
	Realistic = "Realistic", UltraRealistic = "Ultra Realistic", Cinematic = "Cinematic",
	GoldenHour = "Golden Hour", Morning = "Morning",
	Night = "Night", NeonNight = "Neon Night", Horror = "Horror", Dreamy = "Dreamy",
	BlackWhite = "Black & White",
	Foggy = "Foggy", Rainy = "Rainy", Winter = "Winter", Desert = "Desert",
	Clean = "Clean", Colorful = "Colorful", WarmSoft = "Warm Soft", ColdBlue = "Cold Blue",
	FPS = "FPS / Performance", LowEndClean = "Low End Clean",
}

local current = "Default"

local function apply()
	ColorCorrection.Enabled = true
	ColorCorrection.Brightness = Values.CCBrightness
	ColorCorrection.Contrast = Values.CCContrast + Values.ShadowContrastBoost
	ColorCorrection.Saturation = Values.CCSaturation
	ColorCorrection.TintColor = rgb(Values.TintR, Values.TintG, Values.TintB)

	Lighting.Brightness = Values.LightingBrightness
	Lighting.ExposureCompensation = Values.Exposure
	Lighting.ClockTime = Values.ClockTime
	Lighting.GeographicLatitude = Values.GeographicLatitude
	Lighting.EnvironmentDiffuseScale = Values.EnvironmentDiffuse
	Lighting.EnvironmentSpecularScale = Values.EnvironmentSpecular
	Lighting.GlobalShadows = Values.GlobalShadows
	Lighting.ShadowSoftness = Values.ShadowSoftness
	Lighting.Ambient = rgb(
		Values.AmbientR * Values.ShadowAmbientPower,
		Values.AmbientG * Values.ShadowAmbientPower,
		Values.AmbientB * Values.ShadowAmbientPower
	)
	Lighting.OutdoorAmbient = rgb(Values.OutdoorR, Values.OutdoorG, Values.OutdoorB)
	Lighting.ColorShift_Top = rgb(Values.ColorShiftTopR, Values.ColorShiftTopG, Values.ColorShiftTopB)
	Lighting.ColorShift_Bottom = rgb(Values.ColorShiftBottomR, Values.ColorShiftBottomG, Values.ColorShiftBottomB)
	Lighting.FogColor = rgb(Values.FogR, Values.FogG, Values.FogB)
	Lighting.FogStart = Values.FogStart
	Lighting.FogEnd = Values.FogEnd

	Bloom.Enabled = Values.BloomEnabled
	Bloom.Intensity = Values.BloomIntensity
	Bloom.Size = Values.BloomSize
	Bloom.Threshold = Values.BloomThreshold

	SunRays.Enabled = Values.SunRaysEnabled
	SunRays.Intensity = Values.SunIntensity
	SunRays.Spread = Values.SunSpread

	Blur.Enabled = Values.BlurEnabled
	Blur.Size = Values.BlurSize

	DOF.Enabled = Values.DOFEnabled
	DOF.FarIntensity = Values.DOFFarIntensity
	DOF.FocusDistance = Values.DOFFocusDistance
	DOF.InFocusRadius = Values.DOFInFocusRadius
	DOF.NearIntensity = Values.DOFNearIntensity

	Atmosphere.Density = Values.AtmosphereDensity
	Atmosphere.Offset = Values.AtmosphereOffset
	Atmosphere.Haze = Values.AtmosphereHaze
	Atmosphere.Glare = Values.AtmosphereGlare
	Atmosphere.Color = rgb(Values.AtmosphereColorR, Values.AtmosphereColorG, Values.AtmosphereColorB)
	Atmosphere.Decay = rgb(Values.AtmosphereDecayR, Values.AtmosphereDecayG, Values.AtmosphereDecayB)

	if Terrain then
		Terrain.WaterColor = rgb(Values.WaterR, Values.WaterG, Values.WaterB)
		Terrain.WaterTransparency = Values.WaterTransparency
		Terrain.WaterReflectance = Values.WaterReflectance
		Terrain.WaterWaveSize = Values.WaterWaveSize
		Terrain.WaterWaveSpeed = Values.WaterWaveSpeed
	end

	safe(function()
		Workspace.GlobalWind = Vector3.new(Values.WindX, Values.WindY, Values.WindZ)
	end)

	if Clouds then
		safe(function() Clouds.Enabled = Values.CloudsEnabled end)
		Clouds.Cover = Values.CloudCover
		Clouds.Density = Values.CloudDensity
		Clouds.Color = rgb(Values.CloudR, Values.CloudG, Values.CloudB)
	end

	Sky.SunAngularSize = Values.SunSize
	Sky.MoonAngularSize = Values.MoonSize
	Sky.StarCount = Values.StarCount

	if Workspace.CurrentCamera then
		Workspace.CurrentCamera.FieldOfView = Values.FieldOfView
	end

	for _, obj in ipairs(Workspace:GetDescendants()) do
		if obj:IsA("BasePart") then
			safe(function() obj.CastShadow = Values.AllPartShadows end)
		end
	end
end

local function applyPreset(name)
	local p = Presets[name]
	if not p then return false end
	for k, v in pairs(Defaults) do Values[k] = v end
	for k, v in pairs(p) do
		if Values[k] ~= nil then Values[k] = v end
	end
	current = name
	apply()
	return true
end

if getgenv then
	getgenv().SMAZ_PRESETS = {
		Values = Values,
		list = function() return PRESET_ORDER end,
		pretty = function(n) return PRETTY[n] or n end,
		apply = applyPreset,
		get = function(k) return Values[k] end,
		set = function(k, v)
			if Values[k] ~= nil then Values[k] = v; current = "Custom" end
		end,
		commit = apply,
		reset = function()
			for k, v in pairs(Defaults) do Values[k] = v end
			current = "Default"
			apply()
		end,
		futureLighting = function()
			safe(function() Lighting.Technology = Enum.Technology.Future end)
		end,
		current = function() return current end,
	}
	getgenv().__PRESETS_V1_UNLOAD = function()
		for _, obj in ipairs(created) do pcall(function() obj:Destroy() end) end
		getgenv().__PRESETS_V1_LOADED = nil
		getgenv().__PRESETS_V1_UNLOAD = nil
		getgenv().SMAZ_PRESETS = nil
	end
end

print("[Presets v1] Loaded, API: getgenv().SMAZ_PRESETS")
--############### MODULE: control_panel.lua ###############
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
local function getOrCreate(name, className)
	local e = Lighting:FindFirstChild(name)
	if e and e:IsA(className) then return e end
	if e then pcall(function() e:Destroy() end) end
	return Instance.new(className, Lighting)
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
			prm.FilterDescendantsInstances = { cam }
			local hit = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * sBlur.maxDist, prm)
			local d = hit and hit.Distance or sBlur.maxDist
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
	if ATMOS then ATMOS.set("rays", v) else pcall(function() sunFx.Enabled = v end) end
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
mkInfoCard(pSet, "Хоткеи: " .. tostring(menuBindKey) .. " — показать/скрыть панель. В атмосфере: Shift+P — фрикам.")
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
			prm.FilterDescendantsInstances = { cam }
			local hit = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * 600, prm)
			pcall(function() dofFx.FocusDistance = hit and hit.Distance or 600 end)
		end
	end
	if camBreath.on then
		local cam = workspace.CurrentCamera
		if cam then
			pcall(function() cam.FieldOfView = camFov.manual + camBreath.amp * math.sin(tick() * camBreath.speed) end)
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