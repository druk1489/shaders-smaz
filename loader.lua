-- Loader v3 - loads atmosphere_v9, tornado_v12, rain_v12, lightning_v12
-- Usage: loadstring(game:HttpGet("https://raw.githubusercontent.com/druk1489/shaders-smaz/main/loader.lua"))()

local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")

local REPO_USER = "druk1489"
local REPO_NAME = "shaders-smaz"
local BRANCH = "main"

local MODULES = {
	{name = "Atmosphere v9", file = "atmosphere_v9.lua"},
	{name = "Tornado v12", file = "tornado_v10.lua"},
	{name = "Rain v12", file = "rain_v11.lua"},
	{name = "Lightning v12", file = "lightning_v12.lua"},
}

local function notify(title, text, dur)
	pcall(function() StarterGui:SetCore("SendNotification", {Title = title, Text = text, Duration = dur or 3}) end)
end

local function fetch(file)
	local urls = {
		"https://raw.githubusercontent.com/" .. REPO_USER .. "/" .. REPO_NAME .. "/" .. BRANCH .. "/" .. file,
		"https://raw.githubusercontent.com/" .. REPO_USER .. "/" .. REPO_NAME .. "/" .. BRANCH .. "/" .. file .. "?t=" .. tostring(tick()),
		"https://cdn.jsdelivr.net/gh/" .. REPO_USER .. "/" .. REPO_NAME .. "@" .. BRANCH .. "/" .. file,
	}
	for i, url in ipairs(urls) do
		local ok, src = pcall(function() return game:HttpGet(url, true) end)
		if ok and src and #src > 100 then return src, url end
	end
	return nil
end

notify("Loader v3", "Loading " .. #MODULES .. " modules...", 3)
print("[Loader v3] Starting sequential module load")

local loaded = 0
for _, mod in ipairs(MODULES) do
	print("[Loader v3] fetching " .. mod.file)
	local src, url = fetch(mod.file)
	if not src then
		warn("[Loader v3] FAIL fetch: " .. mod.file)
		notify("Loader v3", mod.name .. ": fetch failed", 4)
	else
		local fn, err = loadstring(src, mod.name)
		if not fn then
			warn("[Loader v3] FAIL compile " .. mod.name .. ": " .. tostring(err))
			notify("Loader v3", mod.name .. ": compile fail", 4)
		else
			local ok, runErr = pcall(fn)
			if not ok then
				warn("[Loader v3] FAIL run " .. mod.name .. ": " .. tostring(runErr))
				notify("Loader v3", mod.name .. ": runtime error", 4)
			else
				print("[Loader v3] OK " .. mod.name)
				loaded = loaded + 1
			end
		end
	end
	task.wait(0.15)
end

notify("Loader v3", "Loaded " .. loaded .. "/" .. #MODULES .. " modules", 5)
print("[Loader v3] Done: " .. loaded .. "/" .. #MODULES)
