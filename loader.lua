--=======================================================================
-- SMAZ STUDIO - LOADER (Silent Engine UI)
-- Качает и запускает ЛОГИКУ и ГУИШКУ ОТДЕЛЬНЫМИ файлами.
-- Разделено, чтобы каждый файл был отдельным chunk-ом и не превышал
-- лимит 200 локальных переменных на скрипт.
--=======================================================================
local base = "https://raw.githubusercontent.com/druk1489/shaders-smaz/main/"
local files = {
    "atmosphere_v9.lua",    -- ядро атмосферы + API SMAZ_ATMOS
    "tornado_v10.lua",      -- торнадо SMAZ_TORNADO
    "rain_v11.lua",         -- дождь SMAZ_RAIN
    "lightning_v12.lua",    -- молнии SMAZ_LIGHTNING
    "reflections_v1.lua",   -- отражения SMAZ_REFL
    "presets_v1.lua",       -- пресеты SMAZ_PRESETS
    "control_panel.lua",    -- гуишка Silent Engine UI
}
local loaded = 0
local failed = 0
for _, name in ipairs(files) do
    local ok, err = pcall(function()
        local src = game:HttpGet(base .. name, true)
        local fn, compileErr = loadstring(src, name)
        if not fn then error(compileErr or "compile failed") end
        fn()
    end)
    if ok then
        loaded = loaded + 1
    else
        failed = failed + 1
        warn("[SMAZ LOADER] файл НЕ загрузился: " .. name .. " -> " .. tostring(err))
    end
end
print(("[SMAZ LOADER] готово: %d/%d (%d ошибок)"):format(loaded, #files, failed))