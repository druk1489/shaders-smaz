--==============================================================
-- ATMOSPHERE / SHADERS v9 — LOADER
--
-- Запуск одной строкой в executor'е:
--   loadstring(game:HttpGet("https://raw.githubusercontent.com/druk1489/shaders-smaz/main/loader.lua"))()
--
-- Что делает:
--   1. Скачивает atmosphere_v9.lua из гита (всегда свежая версия)
--   2. Компилит в функцию через loadstring
--   3. Запускает
--   4. Ловит любые ошибки и пишет в warn/notification
--==============================================================

local REPO   = "druk1489/shaders-smaz"
local BRANCH = "main"
local FILE   = "atmosphere_v9.lua"
local LABEL  = "Atmosphere v9"

-- главный URL + зеркало на случай если raw.githubusercontent.com заблокирован
-- (многие executor'ы проксируют через свой CDN, но HttpGet обычно работает напрямую)
local URLS = {
	("https://raw.githubusercontent.com/%s/%s/%s"):format(REPO, BRANCH, FILE),
	-- cache-бастер на случай CDN-кэша:
	("https://raw.githubusercontent.com/%s/%s/%s?cb=%d"):format(REPO, BRANCH, FILE, tick()),
	-- альтернатива (github-зеркало cdn.jsdelivr.net):
	("https://cdn.jsdelivr.net/gh/%s@%s/%s"):format(REPO, BRANCH, FILE),
}

local StarterGui = game:GetService("StarterGui")
local function notify(title, text, dur)
	pcall(function()
		StarterGui:SetCore("SendNotification", {Title = title, Text = text, Duration = dur or 4})
	end)
end

notify(LABEL, "Загружаю скрипт…", 3)

-- Пробуем каждый URL по очереди
local src, lastErr
for i, url in ipairs(URLS) do
	local ok, res = pcall(function()
		return game:HttpGet(url, true)
	end)
	if ok and type(res) == "string" and #res > 200 then
		src = res
		break
	else
		lastErr = tostring(res)
		warn(("[%s loader] URL #%d failed: %s"):format(LABEL, i, lastErr))
	end
end

if not src then
	local msg = "Не смог скачать скрипт: " .. tostring(lastErr)
	warn("[" .. LABEL .. " loader] " .. msg)
	notify(LABEL .. " ERROR", msg, 8)
	return
end

-- Компилим скрипт
local fn, compileErr = loadstring(src, "=" .. FILE)
if not fn then
	local msg = "loadstring failed: " .. tostring(compileErr)
	warn("[" .. LABEL .. " loader] " .. msg)
	notify(LABEL .. " ERROR", msg, 8)
	return
end

-- Запускаем в защищённом pcall'е
local runOk, runErr = pcall(fn)
if not runOk then
	local msg = "runtime error: " .. tostring(runErr)
	warn("[" .. LABEL .. " loader] " .. msg)
	notify(LABEL .. " ERROR", msg, 8)
	return
end

notify(LABEL, "Готово! Shift+P = фрикам, X = скрыть, RightShift = панель", 5)
