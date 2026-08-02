-- Loader v4 - kills failing sound spam, loads modules + unified control panel
-- One-liner: loadstring(game:HttpGet("https://raw.githubusercontent.com/druk1489/shaders-smaz/main/loader.lua"))()

local StarterGui = game:GetService("StarterGui")

local REPO_USER = "druk1489"
local REPO_NAME = "shaders-smaz"
local BRANCH = "main"

-- IDs of broken sound assets that spam "Failed to load sound" errors.
-- Add more here if new ones appear.
local BLOCKED_SOUND_IDS = { "1839825074" }

local function isBlocked(id)
	if typeof(id) ~= "string" then return false end
	for _, bad in ipairs(BLOCKED_SOUND_IDS) do
		if id:find(bad, 1, true) then return true end
	end
	return false
end

-- Kill sounds spawning with blocked IDs (past + future).
local function scrub()
	for _, obj in ipairs(game:GetDescendants()) do
		if obj:IsA("Sound") and isBlocked(obj.SoundId) then
			obj:Stop(); obj:Destroy()
		end
	end
end
pcall(scrub)

game.DescendantAdded:Connect(function(obj)
	if obj:IsA("Sound") then
		task.defer(function()
			if obj and obj.Parent and isBlocked(obj.SoundId) then
				pcall(function() obj:Stop(); obj:Destroy() end)
			end
		end)
	end
end)

local MODULES = {
	{name = "Atmosphere v9", file = "atmosphere_v9.lua"},
	{name = "Tornado v13", file = "tornado_v10.lua"},
	{name = "Rain v13", file = "rain_v11.lua"},
	{name = "Lightning v13", file = "lightning_v12.lua"},
	{name = "Control Panel", file = "control_panel.lua"},
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
	for _, url in ipairs(urls) do
		local ok, src = pcall(function() return game:HttpGet(url, true) end)
		if ok and src and #src > 100 then return src, url end
	end
	return nil
end

notify("Loader v4", "Starting...", 2)
print("[Loader v4] loading " .. #MODULES .. " modules; blocked sounds: " .. table.concat(BLOCKED_SOUND_IDS, ", "))

local loaded = 0
for _, mod in ipairs(MODULES) do
	local src = fetch(mod.file)
	if not src then
		warn("[Loader v4] fetch FAIL: " .. mod.file)
		notify("Loader v4", mod.name .. ": fetch fail", 4)
	else
		local fn, err = loadstring(src, mod.name)
		if not fn then
			warn("[Loader v4] compile FAIL " .. mod.name .. ": " .. tostring(err))
			notify("Loader v4", mod.name .. ": compile fail", 4)
		else
			local ok, runErr = pcall(fn)
			if not ok then
				warn("[Loader v4] runtime FAIL " .. mod.name .. ": " .. tostring(runErr))
				notify("Loader v4", mod.name .. ": runtime fail", 4)
			else
				print("[Loader v4] OK " .. mod.name)
				loaded = loaded + 1
			end
		end
	end
	-- Extra scrub after each module in case it spawned sounds during init
	pcall(scrub)
	task.wait(0.15)
end

notify("Loader v4", "Loaded " .. loaded .. "/" .. #MODULES .. ". Panel top-right", 5)
print("[Loader v4] Done: " .. loaded .. "/" .. #MODULES)
