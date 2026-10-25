# Retro95 UI

Librería de interfaz estilo **Windows 95/98** para executors de Roblox con Drawing API (Luau).
Ligera: solo redibuja cuando algo cambia.

## Cargar la librería

Copia esto al principio de tu script. Descarga la última versión desde GitHub y, si algo falla, te dice exactamente qué:

```lua
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
```

### Usar el archivo local en vez de GitHub

Pon `Retro95.lua` directamente en la carpeta del executor (en Matcha: `C:\matcha\workspace\`, no en una subcarpeta) y cambia la descarga por:

```lua
if not isfile("Retro95.lua") then
    warn("[Retro95] Falta Retro95.lua en la carpeta workspace del executor")
    return
end
local src = readfile("Retro95.lua")
```

## Error "Failed to load Retro95 UI library"

Ese mensaje significa que `_G.Retro95` quedó vacío después de cargar. Causas típicas:

- **No está el archivo en la carpeta `workspace`** de quien ejecuta el script (cada persona tiene la suya). Usa el cargador de GitHub de arriba.
- **El archivo se guardó mal**: como `Retro95.lua.txt`, copiando la página de GitHub en vez del botón **Raw**, o con el código cortado. Busca un error en rojo justo antes en la consola.
- **Se usó `game:HttpGet` en Matcha**, que no está soportado: usa `httpget`.

## Notas para Matcha

- `loadstring(...)()` **no devuelve valores** en Matcha: por eso la librería se lee de `_G.Retro95`.
- La función HTTP oficial es `httpget(url)`; `game:HttpGet` no está garantizado. El cargador de arriba usa `httpget` y cae a `game:HttpGet` en otros executors.
- No llames a tu variable `UI` sin `local`: Matcha ya tiene un global `UI` (su menú propio) y lo pisarías.
- Matcha **no deja leer la rueda del ratón**. Para bajar o subir en una pestaña larga, mantén el clic en cualquier parte del contenido y **arrastra** arriba o abajo (si mueves más de 6 px, no cuenta como clic sobre el control). En executors que sí exponen la rueda, la rueda también funciona.
- Las teclas que escribes en un `Input` también le llegan al juego (Matcha es externo y no puede bloquearlas).
- La fuente de Matcha (ProggyClean) no tiene tildes ni ñ: escribe los textos sin acentos (`"Configuracion"`, `"Rapido"`).
- `task.delay` y `task.defer` no hacen nada en Matcha: usa `task.spawn(function() task.wait(n) ... end)`.
- `error()` en Matcha solo imprime; para lanzar un error capturable usa `assert(false, "mensaje")`.

## Crear la ventana

```lua
local win = Retro:CreateWindow({
    Title = "Mi Script",       -- texto de la barra de título
    Author = "tu nombre",      -- se muestra en Help > About
    Theme = "Windows 98",      -- ver lista de temas abajo
    ToggleKey = "F10",         -- tecla para mostrar/ocultar
    Size = { 600, 440 },       -- ancho, alto
    Status = "Listo",          -- texto de la barra de estado
    TreeWidth = 150,           -- ancho del panel lateral
    MenuBar = true,            -- false para quitar la barra de menús
})
```

## Secciones y pestañas

Las **secciones** son las carpetas del panel lateral; las **pestañas** son las páginas dentro de cada carpeta.

```lua
local general = win:Section("General")            -- carpeta
local main    = general:Tab("Principal")          -- página
local visual  = general:Tab({ Title = "Visuales", Columns = 2 })  -- página a 2 columnas

local ajustes = win:Section({ Title = "Ajustes", Collapsed = true }):Tab("Config")

-- atajo sin sección (crea la carpeta "Pages")
local extra = win:AddTab("Extra")
```

## Controles

Todos aceptan `Flag` (para guardar/leer el valor), `Callback` y `Description` (texto que sale en la barra de estado al pasar el ratón).

```lua
main:Section("Movimiento")   -- título con línea grabada
main:Divider()               -- línea separadora
main:Space(10)               -- espacio vacío en píxeles

main:Toggle({ Title = "Velocidad", Default = false, Flag = "speed",
    Callback = function(v) print(v) end })

main:Slider({ Title = "WalkSpeed", Min = 16, Max = 200, Default = 16, Step = 1, Suffix = " st",
    Flag = "ws", Callback = function(v) end })

main:Button({ Title = "Ejecutar", Style = "primary",   -- "primary", "danger" o nada
    Callback = function() end })

main:Dropdown({ Title = "Modo", Options = { "A", "B", "C" }, Default = "A", Flag = "mode",
    Callback = function(v) end })

main:Dropdown({ Title = "Objetivos", Options = { "Jugadores", "NPCs" }, Multi = true,
    Default = { "NPCs" }, Flag = "targets", Callback = function(tabla) end })

main:Keybind({ Title = "Volar", Default = "F", Mode = "toggle",  -- toggle, hold, click, always
    Flag = "fly", OnTriggered = function(activo, tecla) end })

main:Colorpicker({ Title = "Color", Default = Color3.fromRGB(255, 0, 0), Flag = "color",
    Callback = function(c) end })

main:Input({ Title = "Nombre", Placeholder = "escribe...", MaxLength = 64, Flag = "name",
    Callback = function(texto) end })

local barra = main:Progressbar({ Title = "Cargando", Default = 0 })
barra:SetProgress(0.5)   -- de 0 a 1

main:Paragraph("Texto largo que se ajusta solo al ancho de la ventana.")
```

### Métodos de cada control

```lua
local t = main:Toggle({ Title = "Ejemplo", Flag = "ej" })
t:Set(true)                 -- cambia el valor (dispara el Callback)
t:Set(true, true)           -- cambia el valor sin disparar el Callback
t:Get()                     -- lee el valor
t:SetTitle("Nuevo nombre")
t:SetDescription("Ayuda en la barra de estado")
t:SetVisible(false)
t:OnChanged(function(v) end)
t:Destroy()

dropdown:SetOptions({ "X", "Y", "Z" })   -- solo dropdowns
boton:Fire()                              -- solo botones
keybind:IsEnabled()                       -- solo keybinds
pestaña:Select()                          -- abre esa pestaña
pestaña:SetColumns(2)
```

## Flags, temas y configuración

```lua
Retro:Get("ws")                       -- valor actual por Flag
Retro:Set("ws", 50)                   -- cambiarlo desde código
Retro:Watch("ws", function(v) end)    -- escuchar cambios

Retro:GetThemes()  -- Windows 98, Windows 95, Desert, Eggplant, Marine, Rainy Day, Brick, High Contrast
Retro:SetTheme("Desert")

Retro:SaveConfig("miconfig.json")
Retro:LoadConfig("miconfig.json")
```

## Ventana, menús y extras

```lua
win:AddMenu("File", {
    { Title = "Guardar", Shortcut = "Ctrl+S", Callback = function() Retro:SaveConfig("cfg.json") end },
    "-",   -- separador
    { Title = "Cerrar", Callback = function() Retro:Destroy() end },
})

Retro:Notify({ Title = "Hola", Content = "Mensaje", Type = "success", Duration = 4 })
-- Type: "info", "success", "warning", "error"

win:Watermark({ Title = "Mi Script" })   -- caja con FPS y hora arriba a la izquierda

win:SetTitle("Otro título")
win:SetStatus("Listo")
win:Minimize() ; win:Restore() ; win:Maximize() ; win:Toggle()
win:SetSize(700, 500)
win:SetToggleKey("RightShift")
Retro:Destroy()   -- borra todo
```

## Ejemplo completo

Mira [`ejemplo.lua`](ejemplo.lua).
