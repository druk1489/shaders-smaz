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
		-- Effects are NOT parented until a preset is applied, so nothing
		-- gets enabled/applied just by loading the module.
		if obj:IsA("PostEffect") then obj.Enabled = false end
		if obj:IsA("Atmosphere") then obj.Density = 0 end
		if obj:IsA("Sky") then
			obj.CelestialBodiesShown = false
			obj.SunAngularSize = 0
			obj.MoonAngularSize = 0
			obj.StarCount = 0
		end
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
		Clouds.Enabled = false
		Clouds.Cover = 0
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
	for _, o in ipairs(created) do
		if o:IsA("PostEffect") or o:IsA("Atmosphere") or o:IsA("Sky") then
			pcall(function() o.Parent = Lighting end)
		end
	end
	if Clouds then pcall(function() Clouds.Parent = Terrain end) end

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
