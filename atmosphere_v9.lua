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
	clouds=false, cloudAnimate=true, cloudCover=0.6, cloudDensity=0.55, cloudColor=0.9, cloudSpeed=0.5,
	rays=false, bloom=false, atmosphere=false,
	bloomIntensity=0, raysIntensity=0, raysSpread=0,
	dayNight=false, dayLength=240, timeOfDay=12, timeFollow=false,
	sunSize=350, sunBright=2, sunRange=60,
	moonSize=450, moonBright=1,
	sunTexOn=true, sunTex="rbxasset://sky/sun.jpg",
	moonTexOn=true, moonTex="rbxasset://sky/moon.jpg", texSize=512,
	skyOn=false, skyTex="",
	shine=false, shineStrength=0.35, waterMirror=false,
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
if S.atmosphere then
	for _, v in ipairs(Lighting:GetChildren()) do
		if v:IsA("Sky") then pcall(function() v.CelestialBodiesShown=false; v.SunAngularSize=0; v.MoonAngularSize=0 end) end
	end
end

local atm = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
atm.Density = S.atmosphere and S.atmDensity or 0; atm.Offset = 0.25; atm.Glare = S.atmosphere and 0.3 or 0; atm.Parent = Lighting
local rays = Lighting:FindFirstChildOfClass("SunRaysEffect") or Instance.new("SunRaysEffect")
rays.Enabled = false; rays.Intensity = 0.2; rays.Spread = 1; rays.Parent = Lighting
local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
bloom.Enabled = false; bloom.Intensity = 1.2; bloom.Size = 24; bloom.Threshold = 1.05; bloom.Parent = Lighting
local ccFx = Lighting:FindFirstChild("__AtmosCC") or Instance.new("ColorCorrectionEffect")
ccFx.Name = "__AtmosCC"; ccFx.Enabled = false; ccFx.Parent = Lighting
local ccPhase = Lighting:FindFirstChild("__AtmosPhaseCC") or Instance.new("ColorCorrectionEffect")
ccPhase.Name = "__AtmosPhaseCC"; ccPhase.Enabled = false; ccPhase.Parent = Lighting
local blurFx = Lighting:FindFirstChild("__AtmosBlur") or Instance.new("BlurEffect")
blurFx.Name = "__AtmosBlur"; blurFx.Size = 0; blurFx.Enabled = false; blurFx.Parent = Lighting

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

	-- слой 2: спрайт-текстура. BillboardGui всегда смотрит в камеру и
	-- работает без game:GetObjects (который в половине игр/экзекьюторов падает).
	-- Создаём всегда (дешево), вкл/выкл и картинку решает главный цикл.
	local bb = Instance.new("BillboardGui")
	bb.Name = name.."_Sprite"; bb.Size = UDim2.fromOffset(512, 512); bb.AlwaysOnTop = false
	pcall(function() bb.LightInfluence = 0 end)
	bb.Enabled = false; bb.Parent = root
	local img = Instance.new("ImageLabel")
	img.Name = "TexImg"; img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1); img.Image = ""; img.Parent = bb

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

	return root, light, visual, bb, img
end

local sunPart,  sunLight,  sunVisual,  sunBb,  sunImg  = makeCelestial("Sun",  Color3.fromRGB(255,240,200), SUN_ASSET,  350)
local moonPart, moonLight, moonVisual, moonBb, moonImg = makeCelestial("Moon", Color3.fromRGB(200,215,255), MOON_ASSET, 350)
local lastSunTex, lastMoonTex = "", "" -- кеш: Image трогаем только при смене

--==============================================================
-- ОТРАЖЕНИЯ-ЛАЙТ (PBR shine): дешёвая и ВИДИМАЯ везде альтернатива
-- планарным клонам (reflections_v1: клоны под НЕпрозрачным полом
-- скрыты глубиной — работают только на стекле/воде).
-- Здесь: Future + env-карты (PBR-блики) + Reflectance скайбокса
-- на партах + зеркальная вода. Всё обратимо через бэкапы.
--==============================================================
local shineBackup = {} -- [BasePart] = старый Reflectance
local shineConn = nil
local shineEnv = nil
local shineWater = nil
local function shineApplyPart(part)
	if not part:IsA("BasePart") then return end
	if part:IsDescendantOf(fx) then return end -- своё (светила/погода) не трогаем
	if shineBackup[part] ~= nil then
		pcall(function() part.Reflectance = S.shineStrength end)
		return
	end
	shineBackup[part] = part.Reflectance
	pcall(function() part.Reflectance = S.shineStrength end)
end
local function shineSweep()
	pcall(function()
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d:IsA("BasePart") then shineApplyPart(d) end
		end
	end)
end
local function shineWaterApply()
	if S.shine and S.waterMirror and Terrain then
		if shineWater == nil then
			shineWater = {}
			pcall(function()
				shineWater.refl = Terrain.WaterReflectance
				shineWater.trans = Terrain.WaterTransparency
				shineWater.wave = Terrain.WaterWaveSize
			end)
		end
		pcall(function()
			Terrain.WaterReflectance = 1
			Terrain.WaterTransparency = 0.15
			Terrain.WaterWaveSize = 0.1 -- гладь = чётче отражение
		end)
	else
		if shineWater and Terrain then
			pcall(function()
				if shineWater.refl ~= nil then Terrain.WaterReflectance = shineWater.refl end
				if shineWater.trans ~= nil then Terrain.WaterTransparency = shineWater.trans end
				if shineWater.wave ~= nil then Terrain.WaterWaveSize = shineWater.wave end
			end)
			shineWater = nil
		end
	end
end
local function shineOn()
	if shineEnv == nil then
		shineEnv = {}
		pcall(function() shineEnv.diffuse = Lighting.EnvironmentDiffuseScale end)
		pcall(function() shineEnv.spec = Lighting.EnvironmentSpecularScale end)
	end
	pcall(function() Lighting.EnvironmentDiffuseScale = 1 end)
	pcall(function() Lighting.EnvironmentSpecularScale = 1 end)
	pcall(function() Lighting.Technology = Enum.Technology.Future end) -- на части карт ошибка, ок
	shineWaterApply()
	shineSweep()
	if not shineConn then
		shineConn = Workspace.DescendantAdded:Connect(function(d)
			if S.shine then task.defer(function() shineApplyPart(d) end) end
		end)
	end
end
local function shineOff()
	if shineConn then pcall(function() shineConn:Disconnect() end) shineConn = nil end
	for part, r in pairs(shineBackup) do
		pcall(function() if part and part.Parent then part.Reflectance = r end end)
	end
	shineBackup = {}
	if shineEnv then
		pcall(function()
			if shineEnv.diffuse then Lighting.EnvironmentDiffuseScale = shineEnv.diffuse end
			if shineEnv.spec then Lighting.EnvironmentSpecularScale = shineEnv.spec end
		end)
		shineEnv = nil
	end
	shineWaterApply() -- S.shine уже false -> воду вернёт из бэкапа
end

--==============================================================
-- СКАЙБОКС: свой ID на все 6 граней. Оригинал карты — в бэкап,
-- при выкл возвращается. Ждёт твои ID (поле в АТМОСФЕРА → Светила).
--==============================================================
local SKY_FACES = {"SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp"}
local skyBackup = nil
local function skyApply()
	local sk = Lighting:FindFirstChildOfClass("Sky")
	if not sk then return end
	if S.skyOn and S.skyTex ~= "" then
		if skyBackup == nil then
			skyBackup = {}
			for _, f in ipairs(SKY_FACES) do
				pcall(function() skyBackup[f] = sk[f] end)
			end
		end
		for _, f in ipairs(SKY_FACES) do
			pcall(function() sk[f] = S.skyTex end)
		end
	else
		if skyBackup then
			for _, f in ipairs(SKY_FACES) do
				pcall(function() if skyBackup[f] ~= nil then sk[f] = skyBackup[f] end end)
			end
			skyBackup = nil
		end
	end
end

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
shockBlur.Name = "__ShockBlur"; shockBlur.Size = 0; shockBlur.Enabled = false; shockBlur.Parent = Lighting
local shockCC = Lighting:FindFirstChild("__ShockCC") or Instance.new("ColorCorrectionEffect")
shockCC.Name = "__ShockCC"; shockCC.Enabled = false; shockCC.Saturation = 0; shockCC.Contrast = 0; shockCC.TintColor = Color3.new(1,1,1)
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
local clkAcc, clkLast, clkFight, clkMsg = nil, nil, 0, false -- состояние войны за время (локали, не в S!)
RunService.RenderStepped:Connect(function(dt)
	t += dt
	local camPos = Camera.CFrame.Position

	if S.dayNight and not S.timeFollow then
		-- свой аккумулятор вместо read-modify-write: иначе с игрой,
		-- которая тоже пишет время, получается дёрганье солнца
		clkAcc = (clkAcc or Lighting.ClockTime) + dt * (24 / math.max(1, S.dayLength))
		if clkAcc >= 24 then clkAcc = clkAcc - 24 end
		local cur = Lighting.ClockTime
		if clkLast ~= nil and math.abs(cur - clkLast) > 0.05 then
			-- время ушло не туда, куда мы ставили = параллельно пишет игра
			clkFight = clkFight + 1
			clkAcc = cur -- подстраиваемся, чтобы при уступке не было прыжка
			if clkFight >= 30 and not clkMsg then
				S.timeFollow = true -- игра держит время каждый кадр: уступаем
				clkMsg = true
				pcall(function()
					StarterGui:SetCore("SendNotification", {Title="SMAZ время", Text="Игра держит своё время — уступил. Выкл/вкл день, чтобы вернуть.", Duration=6})
				end)
			end
		else
			clkFight = 0
		end
		if not S.timeFollow then
			Lighting.ClockTime = clkAcc
			clkLast = clkAcc
			S.timeOfDay = clkAcc
		end
	end
	local ct = Lighting.ClockTime
	local dayFactor = clamp(math.sin((ct/24)*pi*2 - pi/2)*0.5 + 0.5, 0, 1)
	if S.atmosphere or S.dayNight then
		applyPhase(phaseFromClock(ct))
	elseif ccPhase.Enabled then
		ccPhase.Enabled = false
	end

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

	-- слой 2: спрайты. Один виден за раз: спрайт вкл -> прячем visual (модель/шар),
	-- иначе спрайт выкл и visual как раньше. Поэтому текстуры есть ВСЕГДА,
	-- даже когда game:GetObjects падает.
	if S.sunTexOn and S.sunTex ~= "" then
		if lastSunTex ~= S.sunTex then sunImg.Image = S.sunTex; lastSunTex = S.sunTex end
		setVisualTransparency(sunVisual, 1)
		sunBb.Enabled = true
		sunBb.Size = UDim2.fromOffset(S.texSize, S.texSize)
		sunImg.ImageTransparency = 1 - sunVis
	else
		sunBb.Enabled = false
		if lastSunTex ~= "" then lastSunTex = "" end
	end
	if S.moonTexOn and S.moonTex ~= "" then
		if lastMoonTex ~= S.moonTex then moonImg.Image = S.moonTex; lastMoonTex = S.moonTex end
		setVisualTransparency(moonVisual, 1)
		moonBb.Enabled = true
		moonBb.Size = UDim2.fromOffset(S.texSize, S.texSize)
		moonImg.ImageTransparency = 1 - moonVis
	else
		moonBb.Enabled = false
		if lastMoonTex ~= "" then lastMoonTex = "" end
	end

	local coverNow = (S.clouds and clouds) and clouds.Cover or 0
	local cloudBlock = 1 - coverNow*0.85
	sunLight.Enabled  = S.atmosphere and sunVis > 0.02
	moonLight.Enabled = S.atmosphere and moonVis > 0.02
	if S.atmosphere then
		sunLight.Brightness  = S.sunBright  * sunVis  * cloudBlock
		moonLight.Brightness = S.moonBright * moonVis * cloudBlock
		sunLight.Range = S.sunRange; moonLight.Range = S.sunRange
	end

	if S.atmosphere or S.dayNight then
		Lighting.Brightness = 0.5 + dayFactor * S.maxBrightness
	end
	atm.Density = S.atmosphere and S.atmDensity or 0
	if S.atmosphere then
		atm.Haze  = S.atmHaze
		atm.Glare = 0.2 + dayFactor * 0.5
	end
	bloom.Enabled = S.bloom
	bloom.Intensity = (S.bloomIntensity and S.bloomIntensity > 0) and S.bloomIntensity or (1.0 + dayFactor * 0.5)
	if not S.bloom then
		-- чужие Bloom (карта/пресеты/панель) тоже гасим, иначе "не вырубается"
		for _, e in ipairs(Lighting:GetChildren()) do
			if e:IsA("BloomEffect") and e ~= bloom then pcall(function() e.Enabled = false end) end
		end
	end
	ccFx.Enabled = S.sharpen
	ccFx.Contrast   = S.sharpenAmt
	ccFx.Saturation = S.sharpenAmt * 0.5
	if S.blur then
		local bsize = S.blurAmt
		if S.blurMode == "distance" then
			local cam = Camera
			local prm = RaycastParams.new()
			prm.FilterType = Enum.RaycastFilterType.Exclude
			-- ФИКС: свой персонаж в игноре, иначе луч бьёт в затылок/торс
			-- при ходьбе и фокус/блюр скачет
			local excl = { cam }
			local lp = Players.LocalPlayer
			local ch = lp and lp.Character or nil
			if ch then excl[#excl + 1] = ch end
			prm.FilterDescendantsInstances = excl
			prm.IgnoreWater = true
			local hit = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * S.blurMaxDist, prm)
			local d = hit and hit.Distance or S.blurMaxDist
			if d < 12 then d = S.blurMaxDist end -- всё равно задел своё -> считаем как небо
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
	if not S.rays then
		-- чужие SunRays (карта/пресеты/__PanelSunRays) + скрипты, что их включают:
		-- душим каждый кадр, иначе "лучи не вырубаются"
		for _, e in ipairs(Lighting:GetChildren()) do
			if e:IsA("SunRaysEffect") and e ~= rays then pcall(function() e.Enabled = false end) end
		end
	end

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
		if k == "dayNight" then
			S.dayNight = not not v
			if S.dayNight then S.timeFollow = false; clkAcc = nil; clkLast = nil; clkFight = 0; clkMsg = false end
			return S.dayNight
		end
		if k == "skyOn" then S.skyOn = not not v; skyApply() return S.skyOn end
		if k == "skyTex" then S.skyTex = tostring(v or ""); skyApply() return S.skyTex end
		if k == "shine" then S.shine = not not v; if S.shine then shineOn() else shineOff() end return S.shine end
		if k == "waterMirror" then S.waterMirror = not not v; shineWaterApply() return S.waterMirror end
		if k == "shineStrength" then
			S.shineStrength = math.clamp(tonumber(v) or 0.35, 0, 1)
			if S.shine then
				for part, _ in pairs(shineBackup) do
					pcall(function() if part and part.Parent then part.Reflectance = S.shineStrength end end)
				end
			end
			return S.shineStrength
		end
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
