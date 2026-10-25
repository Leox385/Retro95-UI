-- Retro95 UI usage example
-- Matcha drops loadstring return values, so the library is read from _G.Retro95.
-- httpget is Matcha's official HTTP function; game:HttpGet is a fallback for other executors.
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

local win = Retro:CreateWindow({
    Title = "My Script - Retro95",
    Author = "Leox385",
    Theme = "Windows 98",      -- Retro:GetThemes() lists them all
    ToggleKey = "F10",
    Size = { 620, 460 },
    Status = "Ready",
})

win:Watermark({ Title = "Retro95" })

-- Custom menu in the menu bar (placed before "Help")
win:AddMenu("File", {
    { Title = "Save config", Shortcut = "Ctrl+S", Callback = function() Retro:SaveConfig("retro95.json") end },
    { Title = "Load config", Callback = function() Retro:LoadConfig("retro95.json") end },
    "-",
    { Title = "Unload", Callback = function() Retro:Destroy() end },
})

local general = win:Section("General")
local main = general:Tab("Main")
local visuals = general:Tab({ Title = "Visuals", Columns = 2 })
local config = win:Section("Settings"):Tab("Config")

main:Section("Movement")
main:Toggle({ Title = "Speed", Flag = "speed_on", Description = "Enables the speed multiplier",
    Callback = function(v) print("speed", v) end })
main:Slider({ Title = "WalkSpeed", Min = 16, Max = 200, Default = 16, Suffix = " st", Flag = "ws",
    Callback = function(v) print("ws", v) end })
main:Slider({ Title = "Smoothing", Min = 0, Max = 1, Step = 0.05, Default = 0.5, Flag = "smooth" })
main:Keybind({ Title = "Fly", Default = "F", Mode = "toggle", Flag = "fly_key",
    OnTriggered = function(on) print("fly", on) end })
main:Divider()
main:Dropdown({ Title = "Mode", Options = { "Normal", "Fast", "Stealth" }, Default = "Normal", Flag = "mode" })
main:Dropdown({ Title = "Targets", Options = { "Players", "NPCs", "Chests" }, Multi = true, Default = { "NPCs" }, Flag = "targets" })
main:Input({ Title = "Name", Placeholder = "type a name...", Flag = "name",
    Callback = function(t) print("name", t) end })
local progress = main:Progressbar({ Title = "Loading data" })
main:Button({ Title = "Run", Style = "primary", Callback = function()
    Retro:Notify({ Title = "Done", Content = "The action ran successfully.", Type = "success" })
end })
main:Button({ Title = "Reset everything", Style = "danger", Callback = function()
    Retro:Notify({ Title = "Warning", Content = "This resets every value.", Type = "warning" })
end })

visuals:Toggle({ Title = "ESP", Flag = "esp" })
visuals:Toggle({ Title = "Names", Flag = "names" })
visuals:Colorpicker({ Title = "ESP color", Flag = "esp_color" })
visuals:Colorpicker({ Title = "Text color", Flag = "txt_color" })
visuals:Paragraph("Visual options are laid out in two columns. This paragraph spans the full width and wraps to the window size.")

config:Section("Appearance")
config:Dropdown({ Title = "Theme", Options = Retro:GetThemes(), Default = "Windows 98",
    Callback = function(name) Retro:SetTheme(name) end })
config:Button({ Title = "About", Callback = function()
    Retro:Notify({ Title = "Retro95", Content = "Version " .. Retro.Version, Type = "info" })
end })

Retro:Watch("ws", function(v) print("WalkSpeed changed to", v) end)

task.spawn(function()
    for i = 0, 100, 5 do
        progress:SetProgress(i / 100)
        task.wait(0.15)
    end
end)
