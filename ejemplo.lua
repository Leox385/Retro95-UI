-- Ejemplo de uso de Retro95 UI
-- Matcha descarta los return de loadstring, por eso la librería se lee de _G.Retro95.
-- httpget es la función HTTP oficial de Matcha; game:HttpGet queda de respaldo para otros executors.
local URL = "https://raw.githubusercontent.com/Leox385/Retro95-UI/main/Retro95.lua"

local src
if httpget then src = httpget(URL) else src = game:HttpGet(URL) end
if type(src) ~= "string" or #src < 1000 then
    warn("[Retro95] No se pudo descargar la libreria: " .. URL)
    return
end
if src:sub(1, 1) == "<" then
    warn("[Retro95] La URL devuelve una pagina web, no el codigo. Usa el enlace Raw.")
    return
end

loadstring(src)()
local Retro = _G.Retro95
if not Retro then
    warn("[Retro95] La libreria no se cargo. Mira los errores en rojo de arriba en la consola.")
    return
end

local win = Retro:CreateWindow({
    Title = "Mi Script - Retro95",
    Author = "leo",
    Theme = "Windows 98",      -- Retro:GetThemes() para ver todos
    ToggleKey = "F10",
    Size = { 620, 460 },
    Status = "Listo",
})

win:Watermark({ Title = "Retro95" })

-- Menú propio en la barra de menús (antes de "Help")
win:AddMenu("File", {
    { Title = "Save config", Shortcut = "Ctrl+S", Callback = function() Retro:SaveConfig("retro95.json") end },
    { Title = "Load config", Callback = function() Retro:LoadConfig("retro95.json") end },
    "-",
    { Title = "Unload", Callback = function() Retro:Destroy() end },
})

local general = win:Section("General")
local main = general:Tab("Principal")
local visuals = general:Tab({ Title = "Visuales", Columns = 2 })
local config = win:Section("Configuracion"):Tab("Ajustes")

main:Section("Movimiento")
main:Toggle({ Title = "Velocidad", Flag = "speed_on", Description = "Activa el multiplicador de velocidad",
    Callback = function(v) print("speed", v) end })
main:Slider({ Title = "WalkSpeed", Min = 16, Max = 200, Default = 16, Suffix = " st", Flag = "ws",
    Callback = function(v) print("ws", v) end })
main:Slider({ Title = "Suavizado", Min = 0, Max = 1, Step = 0.05, Default = 0.5, Flag = "smooth" })
main:Keybind({ Title = "Volar", Default = "F", Mode = "toggle", Flag = "fly_key",
    OnTriggered = function(on) print("fly", on) end })
main:Divider()
main:Dropdown({ Title = "Modo", Options = { "Normal", "Rapido", "Sigiloso" }, Default = "Normal", Flag = "mode" })
main:Dropdown({ Title = "Objetivos", Options = { "Jugadores", "NPCs", "Cofres" }, Multi = true, Default = { "NPCs" }, Flag = "targets" })
main:Input({ Title = "Nombre", Placeholder = "escribe un nombre...", Flag = "name",
    Callback = function(t) print("name", t) end })
local prog = main:Progressbar({ Title = "Cargando datos" })
main:Button({ Title = "Ejecutar", Style = "primary", Callback = function()
    Retro:Notify({ Title = "Hecho", Content = "La accion se ejecuto correctamente.", Type = "success" })
end })
main:Button({ Title = "Reiniciar todo", Style = "danger", Callback = function()
    Retro:Notify({ Title = "Atencion", Content = "Esto reinicia todos los valores.", Type = "warning" })
end })

visuals:Toggle({ Title = "ESP", Flag = "esp" })
visuals:Toggle({ Title = "Nombres", Flag = "names" })
visuals:Colorpicker({ Title = "Color ESP", Flag = "esp_color" })
visuals:Colorpicker({ Title = "Color texto", Flag = "txt_color" })
visuals:Paragraph("Las opciones visuales se dibujan en dos columnas. Este parrafo ocupa todo el ancho y se ajusta solo al tamano de la ventana.")

config:Section("Apariencia")
config:Dropdown({ Title = "Tema", Options = Retro:GetThemes(), Default = "Windows 98",
    Callback = function(name) Retro:SetTheme(name) end })
config:Button({ Title = "Acerca de", Callback = function()
    Retro:Notify({ Title = "Retro95", Content = "Version " .. Retro.Version, Type = "info" })
end })

Retro:Watch("ws", function(v) print("WalkSpeed cambio a", v) end)

task.spawn(function()
    for i = 0, 100, 5 do
        prog:SetProgress(i / 100)
        task.wait(0.15)
    end
end)
