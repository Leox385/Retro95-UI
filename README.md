# Retro95 UI

A **Windows 95/98** style interface library for Roblox executors with a Drawing API (Luau).
Lightweight: it only redraws when something changes. Works with Matcha.

## Loading the library

Paste this at the top of your script. It downloads the latest version from GitHub and, if something goes wrong, tells you exactly what:

```lua
local URL = "https://raw.githubusercontent.com/Leox385/Retro95-UI/main/Retro95.lua"

local src
if httpget then src = httpget(URL) else src = game:HttpGet(URL) end
if type(src) ~= "string" or #src < 1000 then
    warn("[Retro95] Could not download the library: " .. URL)
    return
end
if src:sub(1, 1) == "<" then
    warn("[Retro95] The URL returned a web page instead of code. Use the Raw link.")
    return
end

loadstring(src)()
local Retro = _G.Retro95
if not Retro then
    warn("[Retro95] The library did not load. Check the red errors above in the console.")
    return
end
```

### Using a local file instead of GitHub

Put `Retro95.lua` directly in your executor's workspace folder (for Matcha: `C:\matcha\workspace\`, not a subfolder) and replace the download with:

```lua
if not isfile("Retro95.lua") then
    warn("[Retro95] Retro95.lua is missing from the executor's workspace folder")
    return
end
local src = readfile("Retro95.lua")
```

## "Failed to load Retro95 UI library" error

That message means `_G.Retro95` was still empty after loading. Common causes:

- **The file is not in the `workspace` folder** of the person running the script (everyone has their own). Use the GitHub loader above.
- **The file was saved incorrectly**: as `Retro95.lua.txt`, by copying the GitHub page instead of the **Raw** button, or with the code cut off. Look for a red error right before it in the console.
- **`game:HttpGet` was used in Matcha**, which is not supported there: use `httpget`.

## Matcha notes

- `loadstring(...)()` **does not return values** in Matcha, so the library is read from `_G.Retro95`.
- The official HTTP function is `httpget(url)`; `game:HttpGet` is not guaranteed. The loader above uses `httpget` and falls back to `game:HttpGet` on other executors.
- Don't name your variable `UI` without `local`: Matcha already has a global `UI` (its own menu) and you would overwrite it.
- Matcha **cannot read the mouse wheel**. To scroll a long tab, hold the click anywhere in the content and **drag** up or down (moving more than 6 px does not count as a click on the control). On executors that expose the wheel, the wheel works too.
- Keys typed into an `Input` also reach the game (Matcha is external and cannot block them).
- Matcha's font (ProggyClean) has no accented characters: keep labels in plain ASCII.
- `task.delay` and `task.defer` do nothing in Matcha: use `task.spawn(function() task.wait(n) ... end)`.
- `error()` only prints in Matcha; to raise a catchable error use `assert(false, "message")`.

## Creating the window

```lua
local win = Retro:CreateWindow({
    Title = "My Script",       -- title bar text
    Author = "your name",      -- shown in Help > About
    Theme = "Windows 98",      -- see the theme list below
    ToggleKey = "F10",         -- show/hide key
    Size = { 600, 440 },       -- width, height
    Status = "Ready",          -- status bar text
    TreeWidth = 150,           -- side panel width
    MenuBar = true,            -- false to remove the menu bar
})
```

## Sections and tabs

**Sections** are the folders in the side panel; **tabs** are the pages inside each folder.

```lua
local general = win:Section("General")            -- folder
local main    = general:Tab("Main")               -- page
local visual  = general:Tab({ Title = "Visuals", Columns = 2 })  -- two-column page

local settings = win:Section({ Title = "Settings", Collapsed = true }):Tab("Config")

-- shortcut without a section (creates a "Pages" folder)
local extra = win:AddTab("Extra")
```

## Controls

All of them accept `Flag` (to save/read the value), `Callback` and `Description` (text shown in the status bar on hover).

```lua
main:Section("Movement")     -- header with an etched line
main:Divider()               -- separator line
main:Space(10)               -- empty space in pixels

main:Toggle({ Title = "Speed", Default = false, Flag = "speed",
    Callback = function(v) print(v) end })

main:Slider({ Title = "WalkSpeed", Min = 16, Max = 200, Default = 16, Step = 1, Suffix = " st",
    Flag = "ws", Callback = function(v) end })

main:Button({ Title = "Run", Style = "primary",   -- "primary", "danger" or nothing
    Callback = function() end })

main:Dropdown({ Title = "Mode", Options = { "A", "B", "C" }, Default = "A", Flag = "mode",
    Callback = function(v) end })

main:Dropdown({ Title = "Targets", Options = { "Players", "NPCs" }, Multi = true,
    Default = { "NPCs" }, Flag = "targets", Callback = function(selected) end })

main:Keybind({ Title = "Fly", Default = "F", Mode = "toggle",  -- toggle, hold, click, always
    Flag = "fly", OnTriggered = function(active, key) end })

main:Colorpicker({ Title = "Color", Default = Color3.fromRGB(255, 0, 0), Flag = "color",
    Callback = function(c) end })

main:Input({ Title = "Name", Placeholder = "type here...", MaxLength = 64, Flag = "name",
    Callback = function(text) end })

local bar = main:Progressbar({ Title = "Loading", Default = 0 })
bar:SetProgress(0.5)   -- from 0 to 1

main:Paragraph("Long text that wraps to the window width automatically.")
```

### Control methods

```lua
local t = main:Toggle({ Title = "Example", Flag = "ex" })
t:Set(true)                 -- change the value (fires the Callback)
t:Set(true, true)           -- change the value without firing the Callback
t:Get()                     -- read the value
t:SetTitle("New name")
t:SetDescription("Status bar help text")
t:SetVisible(false)
t:OnChanged(function(v) end)
t:Destroy()

dropdown:SetOptions({ "X", "Y", "Z" })   -- dropdowns only
button:Fire()                             -- buttons only
keybind:IsEnabled()                       -- keybinds only
tab:Select()                              -- open that tab
tab:SetColumns(2)
```

## Flags, themes and config

```lua
Retro:Get("ws")                       -- current value by Flag
Retro:Set("ws", 50)                   -- change it from code
Retro:Watch("ws", function(v) end)    -- listen for changes

Retro:GetThemes()  -- Windows 98, Windows 95, Desert, Eggplant, Marine, Rainy Day, Brick, High Contrast
Retro:SetTheme("Desert")

Retro:SaveConfig("myconfig.json")
Retro:LoadConfig("myconfig.json")
```

## Window, menus and extras

```lua
win:AddMenu("File", {
    { Title = "Save", Shortcut = "Ctrl+S", Callback = function() Retro:SaveConfig("cfg.json") end },
    "-",   -- separator
    { Title = "Close", Callback = function() Retro:Destroy() end },
})

Retro:Notify({ Title = "Hello", Content = "Message", Type = "success", Duration = 4 })
-- Type: "info", "success", "warning", "error"

win:Watermark({ Title = "My Script" })   -- box with FPS and time in the top-left corner

win:SetTitle("Another title")
win:SetStatus("Ready")
win:Minimize() ; win:Restore() ; win:Maximize() ; win:Toggle()
win:SetSize(700, 500)
win:SetToggleKey("RightShift")
Retro:Destroy()   -- removes everything
```

## Full example

See [`example.lua`](example.lua).
