# Atmosphere / Shaders v9 (Solara / Executor)

Roblox-скрипт для инжекта через executor (Solara и т.п.). Даёт кастомную атмосферу, солнце/луну из Store, молнии рядом с игроком и ударные волны с искажением света.

## Хоткеи
- **Shift+P** — включить/выключить фрикам (WASD движение, E/Q вверх/вниз, Z/C наклон, колесо зум, Shift быстрее, Ctrl медленнее)
- **X** — скрыть весь UI + курсор
- **RightShift** — свернуть/развернуть панель настроек

## Что в v9 нового
1. **Солнце и Луна** — реальные модельки из Store:
   - Sun: `rbxassetid://8430326250`
   - Moon: `rbxassetid://8430423571`
   - Грузятся через `game:GetObjects` (executor-only). Если провалилось — fallback на Neon Ball.
   - Дистанция от камеры = **8000 studs** ("далеко" как ты просил). Визуально размер компенсирован автоматически.
2. **Молнии** — используют текстуру `rbxassetid://73663492833517` (lightingbeam из Store).
3. **Ударные волны** — flipbook `rbxassetid://70564074541084` (4x4 grid, 16 кадров). Каждая молния = shockwave 55 studs.
4. **Fake Schlieren distortion** — когда фронт ударной волны проходит через камеру:
   - Blur ramp up до 24
   - ColorCorrection: Contrast/Saturation/TintColor wobble
   - Camera shake через `Humanoid.CameraOffset:Lerp(...)`

## Что осталось воткнуть
В начале файла есть слоты для своих asset ID:
```lua
local FLASH_TEX  = "rbxassetid://0"  -- твой flash.png
local SPARK_TEX  = "rbxassetid://0"  -- spark.png
local SMOKE_TEX  = "rbxassetid://0"  -- smoke.png
local DEBRIS_TEX = "rbxassetid://0"  -- debris.png
local THUNDER_SOUNDS = {
    "rbxassetid://0", -- 4bd08c8067970b7.mp3
    "rbxassetid://0", -- ozarnikru-raskat-groma.mp3
    "rbxassetid://0", -- fonoteca-raskat-groma.mp3
    "rbxassetid://0", -- zvuki_-_zvuk_groma.mp3
    "rbxassetid://0", -- raskaty_groma.mp3
}
```
Залей свои PNG (bolt_1..4, flash, spark, smoke, debris) и mp3 звуков грома в Roblox → получи id → впиши сюда. До этого работают fallback'и Roblox.

## Физика молнии (из транскрипта)
- **Stepped downward leader** от облака (250-400 studs высоты) вниз ступеньками
- **Upward leader** из земли навстречу (10-20% высоты)
- **Return stroke** — мега-яркий полный канал после соединения
- **Branches** — 3-6 случайных ответвлений
- **Impact FX** — spark burst (40 particles), smoke, scorch mark, shockwave
- **Thunder delay** = `distance / 343` секунд (скорость звука ≈ 343 m/s, 1 stud ≈ 1 m)
- **Screen flash** — Frame overlay + Lighting.Brightness bump, ослабляется по расстоянию

## Использование
Скопируй содержимое `atmosphere_v9.lua` в свой executor и запусти. Появится нотификация + панель настроек слева.

Вкладка **Молнии** → кнопки:
- `⚡ Молния возле меня` — одна молния
- `⚡⚡⚡ ЗАЛП (5 молний)` — 5 подряд с рандомными паузами

В грозу (Погода → Дождь/Град) молнии стреляют автоматически с частотой `lightningRate`.
