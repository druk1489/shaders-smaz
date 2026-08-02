--==============================================================
-- SHADERS-SMAZ LOADER
--
-- Одна строка запуска в executor'е:
--   loadstring(game:HttpGet("https://raw.githubusercontent.com/druk1489/shaders-smaz/main/loader.lua"))()
--
-- Загружает по очереди:
--   1. atmosphere_v9.lua (солнце, луна, молнии, погода, шейдеры)
--   2. tornado_v10.lua   (мульти-торнадо, Rankine vortex, merge/split)
--
-- Каждый скрипт запускается в pcall — падение одного не убивает другой.
--==============================================================

local REPO = "druk1489/shaders-smaz"
local BRANCH = "main"

local MODULES = {
	{name = "Atmosphere v9", file = "atmosphere_v9.lua"},
	{name = "Tornado v10",   file = "tornado_v10.lua"},
}

local StarterGui = game:GetService("StarterGui")
local function notify(title, text, dur)
	pcall(function()
		StarterGui:SetCore("SendNotification", {Title = title, Text = text, Duration = dur or 4})
	end)
end

local function urlsFor(file)
	return {
		("https://raw.githubusercontent.com/%s/%s/%s"):format(REPO, BRANCH, file),
		("https://raw.githubusercontent.com/%s/%s/%s?cb=%d"):format(REPO, BRANCH, file, tick()),
		("https://cdn.jsdelivr.net/gh/%s@%s/%s"):format(REPO, BRANCH, file),
	}
end

local function fetch(urls, label)
	local lastErr
	for i, url in ipairs(urls) do
		local ok, res = pcall(function() return game:HttpGet(url, true) end)
		if ok and type(res) == "string" and #res > 200 then
			return res
		end
		lastErr = tostring(res)
		warn(("[%s loader] URL #%d failed: %s"):format(label, i, lastErr))
	end
	return nil, lastErr
end

local function run(mod)
	notify(mod.name, "Загружаю…", 3)
	local src, err = fetch(urlsFor(mod.file), mod.name)
	if not src then
		notify(mod.name .. " ERROR", "Не скачал: " .. tostring(err), 8)
		return false
	end
	local fn, ce = loadstring(src, "=" .. mod.file)
	if not fn then
		notify(mod.name .. " ERROR", "loadstring: " .. tostring(ce), 8)
		return false
	end
	local ok, re = pcall(fn)
	if not ok then
		notify(mod.name .. " ERROR", "runtime: " .. tostring(re), 8)
		return false
	end
	return true
end

local loadedCount = 0
for _, mod in ipairs(MODULES) do
	if run(mod) then loadedCount = loadedCount + 1 end
end

notify("Shaders-Smaz", ("Готово: %d/%d модулей"):format(loadedCount, #MODULES), 5)
print(("[Shaders-Smaz] %d/%d модулей загружено"):format(loadedCount, #MODULES))
