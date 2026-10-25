--[[
    Retro95 UI  v1.0.0
    Windows 95/98 style interface library for executors with a Drawing API (Luau).

    Same usage as Astra/Kirin:
        loadstring(httpget("https://raw.githubusercontent.com/Leox385/Retro95-UI/main/Retro95.lua"))()
        local Retro = _G.Retro95   -- Matcha drops loadstring return values
        local win = Retro:CreateWindow({ Title = "My Script", Theme = "Windows 98", ToggleKey = "F10" })
        local tab = win:Section("General"):Tab("Main")
        tab:Toggle({ Title = "Enabled", Flag = "on", Callback = function(v) end })

    Lightweight by design:
      * only redraws when something changes (mouse, click, keyboard, API, or every 0.5 s for the clock/caret)
      * no particles, no animated transparency, no glows
      * 3D bevels built from stacked squares (pixel-crisp and cheap)
]]

local typeOf = typeof or type
local function safeGet(object, key)
    if object == nil then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
    return nil
end
local function service(name)
    local ok, value = pcall(function() return game:GetService(name) end)
    if ok then return value end
    return nil
end
local function report(message)
    local out = warn or print
    if type(out) == "function" then pcall(out, "[Retro95] " .. tostring(message)) end
end
if not Drawing or type(safeGet(Drawing, "new")) ~= "function" or not Vector2 or not Color3 then
    report("Unsupported runtime: Drawing.new, Vector2 and Color3 are required")
    return nil
end
local taskHost = task or {}
local spawnHost = taskHost.spawn or spawn
local waitHost = taskHost.wait or wait
if type(spawnHost) ~= "function" or type(waitHost) ~= "function" then
    report("Unsupported runtime: spawn/wait is unavailable")
    return nil
end
local clock = (os and os.clock) or tick
if type(clock) ~= "function" then report("A compatible clock is required"); return nil end
local unpackf = table.unpack or unpack
local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local runtimeAlive = true

local function background(fn)
    spawnHost(function()
        waitHost()
        if runtimeAlive then fn() end
    end)
end

local RunService, Players, UserInputService = service("RunService"), service("Players"), service("UserInputService")
local mouse = nil
local viewport = Vector2.new(1280, 720)
local function refreshRuntime()
    local lp = safeGet(Players, "LocalPlayer")
    if not mouse and lp then pcall(function() mouse = lp:GetMouse() end) end
    local cam = safeGet(workspace, "CurrentCamera")
    local size = safeGet(cam, "ViewportSize") or safeGet(Drawing, "Viewport")
    if size and size.X and size.Y and size.X > 0 and size.Y > 0 then viewport = size end
end
refreshRuntime()

local function connectOptional(signal, callback)
    if not signal or type(safeGet(signal, "Connect")) ~= "function" then return nil end
    local ok, connection = pcall(function() return signal:Connect(callback) end)
    if ok then return connection end
    return nil
end
local function connectFrame(callback)
    for _, name in ipairs({ "RenderStepped", "Heartbeat" }) do
        local connection = connectOptional(safeGet(RunService, name), callback)
        if connection then return connection end
    end
    local active = true
    background(function()
        local last = clock()
        while active and runtimeAlive do
            local now = clock()
            callback(max(0.001, now - last))
            last = now
            waitHost()
        end
    end)
    return { Disconnect = function() active = false end }
end
local function finite(value, fallback)
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n == -math.huge then return fallback end
    return n
end
local function normalizeKey(value)
    if type(value) == "number" then return max(0, min(255, floor(finite(value, 0)))) end
    local name = type(value) == "string" and value or safeGet(value, "Name")
    if not name then return 0 end
    name = string.lower(name)
    local map = { none = 0, space = 32, tab = 9, enter = 13, ["return"] = 13, backspace = 8,
        esc = 27, escape = 27, shift = 16, leftshift = 16, rightshift = 16, ctrl = 17, leftcontrol = 17,
        rightcontrol = 17, alt = 18, leftalt = 18, rightalt = 18, pageup = 33, pagedown = 34,
        left = 37, up = 38, right = 39, down = 40, insert = 45, delete = 46, home = 36, ["end"] = 35,
        zero = 48, one = 49, two = 50, three = 51, four = 52, five = 53, six = 54, seven = 55, eight = 56, nine = 57,
        m1 = 1, mousebutton1 = 1, m2 = 2, mousebutton2 = 2, mousebutton3 = 4 }
    if map[name] then return map[name] end
    if #name == 1 then return string.byte(string.upper(name)) end
    local f = tonumber(name:match("^f(%d+)$"))
    if f and f >= 1 and f <= 12 then return 111 + f end
    return 0
end
local function colorValid(value)
    return value ~= nil and finite(safeGet(value, "R")) ~= nil and finite(safeGet(value, "G")) ~= nil and finite(safeGet(value, "B")) ~= nil
end
local function utf8Prefix(text, length)
    length = max(0, min(#text, length))
    if length < #text then
        local nextByte = string.byte(text, length + 1)
        while length > 0 and nextByte and nextByte >= 128 and nextByte < 192 do
            length = length - 1
            nextByte = string.byte(text, length + 1)
        end
    end
    return string.sub(text, 1, length)
end

if type(_G.__Retro95Cleanup) == "function" then pcall(_G.__Retro95Cleanup) end

-- ── Drawing capabilities ────────────────────────────────────────────────
local function probe(kind, prop, val)
    local d
    local ok = pcall(function() d = Drawing.new(kind); d[prop] = val end)
    if d then pcall(function() d:Remove() end) end
    return ok
end
local HAS_FONTSIZE = probe("Text", "FontSize", 13)
local HAS_Z = probe("Square", "ZIndex", 1)
-- Real or estimated TextBounds: Matcha reports 7 px per character regardless of font or size,
-- so if "iiii" measures the same as "WWWW" a fixed per-character width is used
local HAS_BOUNDS, CHAR_W = false, 6.5
do
    local d
    local ok, narrow, wide = pcall(function()
        d = Drawing.new("Text")
        if HAS_FONTSIZE then d.FontSize = 13 else d.Size = 13 end
        d.Text = "iiiiiiiiii"
        local a = d.TextBounds
        d.Text = "WWWWWWWWWW"
        return a, d.TextBounds
    end)
    local nx, wx = finite(safeGet(narrow, "X"), 0), finite(safeGet(wide, "X"), 0)
    if ok and wx > 5 then
        if nx == wx then CHAR_W = wx / 10 else HAS_BOUNDS = true end
    end
    if d then pcall(function() d:Remove() end) end
end
local FONTS = (typeOf(Drawing.Fonts) == "table") and Drawing.Fonts or {}
local F_UI = FONTS.UI or 0
local F_SYS = FONTS.SystemBold or FONTS.System or 1

-- ── Utilities ───────────────────────────────────────────────────────────
local function clamp(v, a, b)
    if v < a then return a elseif v > b then return b end
    return v
end
local function lerp(a, b, t) return a + (b - a) * t end
local function V(x, y) return Vector2.new(x, y) end
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local function mixC(a, b, t)
    if t <= 0 then return a elseif t >= 1 then return b end
    return Color3.fromRGB(
        floor((a.R + (b.R - a.R) * t) * 255 + 0.5),
        floor((a.G + (b.G - a.G) * t) * 255 + 0.5),
        floor((a.B + (b.B - a.B) * t) * 255 + 0.5))
end
local function colorEq(a, b)
    return abs(a.R - b.R) < 0.01 and abs(a.G - b.G) < 0.01 and abs(a.B - b.B) < 0.01
end
local function toHex(c)
    return string.format("#%02X%02X%02X", floor(c.R * 255 + 0.5), floor(c.G * 255 + 0.5), floor(c.B * 255 + 0.5))
end
local function inRect(px, py, x, y, w, h)
    return px >= x and px < x + w and py >= y and py < y + h
end
local function fmtNum(v, step)
    if step and step % 1 ~= 0 then
        return string.format((step < 0.1) and "%.2f" or "%.1f", v)
    end
    return tostring(floor(v + 0.5))
end
local function wrapText(str, maxChars)
    local out = {}
    for para in (str .. "\n"):gmatch("(.-)\n") do
        local cur = ""
        for word in para:gmatch("%S+") do
            if cur == "" then
                cur = word
            elseif #cur + 1 + #word <= maxChars then
                cur = cur .. " " .. word
            else
                out[#out + 1] = cur
                cur = word
            end
        end
        out[#out + 1] = cur
    end
    if #out == 0 then out[1] = "" end
    return table.concat(out, "\n"), #out
end
local function sameValue(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k, v in pairs(b) do if a[k] ~= v then return false end end
    return true
end
local function fire(cb, ...)
    if type(cb) ~= "function" then return end
    local args, count = { ... }, select("#", ...)
    background(function()
        local ok, err = pcall(cb, unpackf(args, 1, count))
        if not ok then report("Callback: " .. tostring(err)) end
    end)
end

-- ── Drawing proxy: only writes to the engine when a value changes ──────
local function newDraw(kind, props)
    local raw = Drawing.new(kind)
    assert(raw, "Retro95: Drawing.new failed for " .. tostring(kind))
    local cache, removed, measured, unsupported = {}, false, nil, {}
    local proxy = setmetatable({}, {
        __index = function(_, key)
            if key == "Remove" then
                return function()
                    if not removed then removed = true; pcall(function() raw:Remove() end) end
                end
            end
            if key == "TextBounds" then
                if not measured then measured = safeGet(raw, "TextBounds") end
                return measured
            end
            local c = cache[key]
            if c ~= nil then return c end
            return safeGet(raw, key)
        end,
        __newindex = function(_, key, value)
            if removed then return end
            local old = cache[key]
            if old == value then return end
            if old ~= nil and value ~= nil then
                if key == "Position" or key == "Size" or key == "From" or key == "To" then
                    if type(value) ~= "number" and old.X == value.X and old.Y == value.Y then return end
                elseif key == "Color" then
                    if old.R == value.R and old.G == value.G and old.B == value.B then return end
                end
            end
            local target = key
            if kind == "Text" and key == "Size" and HAS_FONTSIZE then target = "FontSize" end
            if unsupported[target] then return end
            local ok = pcall(function() raw[target] = value end)
            if not ok then unsupported[target] = true; return end
            cache[key] = value
            if key == "Text" or key == "Size" or key == "Font" then measured = nil end
        end,
    })
    for k, v in pairs(props or {}) do proxy[k] = v end
    return proxy
end
local function kill(d)
    pcall(function()
        d.Visible = false
        d:Remove()
    end)
end
local function textW(d, size)
    if HAS_BOUNDS then
        local b = d.TextBounds
        if b and b.X > 1 then return b.X end
    end
    return #tostring(d.Text or "") * CHAR_W * (size or 13) / 13
end
local function hideAll(list) for _, d in ipairs(list) do d.Visible = false end end
local function fitInto(d, full, room, st)
    room = max(0, floor(room))
    if st.fw == room and st.ft == full then return end
    st.fw, st.ft = room, full
    d.Text = full
    if textW(d, 13) <= room then return end
    local lo, hi = 0, #full
    while lo < hi do
        local mid = floor((lo + hi + 1) / 2)
        d.Text = utf8Prefix(full, mid) .. "..."
        if textW(d, 13) <= room then lo = mid else hi = mid - 1 end
    end
    d.Text = lo > 0 and (utf8Prefix(full, lo) .. "...") or ""
end

-- ── Classic themes ──────────────────────────────────────────────────────
local WHITE, BLACK = rgb(255, 255, 255), rgb(0, 0, 0)
local FOLDER, FOLDER_DK, ICON_BAR = rgb(255, 232, 120), rgb(128, 128, 0), rgb(0, 128, 128)
local function makeTheme(name, face, lt, sh, t1, t2, extra)
    local T = { Name = name, Face = face, Hi = WHITE, Lt = lt, Sh = sh, Dk = BLACK,
        Win = WHITE, Text = BLACK, Gray = sh, T1 = t1, T2 = t2, TText = WHITE,
        Sel = t1, SelText = WHITE, Info = rgb(255, 255, 225), Danger = rgb(128, 0, 0) }
    if extra then for k, v in pairs(extra) do T[k] = v end end
    T.Track = mixC(T.Hi, T.Face, 0.5)
    return T
end
local Themes, THEME_ORDER = {}, {}
local function addTheme(T) Themes[T.Name] = T; THEME_ORDER[#THEME_ORDER + 1] = T.Name end
addTheme(makeTheme("Windows 98", rgb(192, 192, 192), rgb(223, 223, 223), rgb(128, 128, 128), rgb(0, 0, 128), rgb(16, 132, 208)))
addTheme(makeTheme("Windows 95", rgb(192, 192, 192), rgb(223, 223, 223), rgb(128, 128, 128), rgb(0, 0, 128), rgb(0, 0, 128)))
addTheme(makeTheme("Desert", rgb(213, 204, 187), rgb(234, 230, 221), rgb(162, 141, 104), rgb(0, 128, 128), rgb(80, 176, 176)))
addTheme(makeTheme("Eggplant", rgb(144, 176, 168), rgb(200, 216, 212), rgb(88, 128, 120), rgb(64, 0, 64), rgb(140, 80, 140)))
addTheme(makeTheme("Marine", rgb(136, 192, 184), rgb(196, 224, 220), rgb(72, 128, 120), rgb(0, 0, 128), rgb(40, 120, 168)))
addTheme(makeTheme("Rainy Day", rgb(128, 152, 176), rgb(184, 200, 216), rgb(72, 88, 112), rgb(79, 101, 125), rgb(140, 165, 195), { Hi = rgb(214, 224, 236) }))
addTheme(makeTheme("Brick", rgb(194, 191, 165), rgb(225, 224, 210), rgb(141, 137, 97), rgb(128, 0, 0), rgb(192, 72, 48)))
addTheme(makeTheme("High Contrast", BLACK, rgb(192, 192, 192), rgb(128, 128, 128), rgb(128, 0, 128), rgb(128, 0, 128),
    { Dk = WHITE, Win = BLACK, Text = WHITE, Gray = rgb(0, 255, 0), Info = BLACK, Danger = rgb(255, 80, 80) }))

local VK_NAMES = {
    [0x01] = "M1", [0x02] = "M2", [0x04] = "M3", [0x05] = "M4", [0x06] = "M5",
    [0x08] = "Back", [0x09] = "Tab", [0x0D] = "Enter", [0x10] = "Shift", [0x11] = "Ctrl", [0x12] = "Alt",
    [0x14] = "Caps", [0x1B] = "Esc", [0x20] = "Space", [0x21] = "PgUp", [0x22] = "PgDn", [0x23] = "End", [0x24] = "Home",
    [0x25] = "Left", [0x26] = "Up", [0x27] = "Right", [0x28] = "Down", [0x2D] = "Ins", [0x2E] = "Del",
    [0xA0] = "LShift", [0xA1] = "RShift", [0xA2] = "LCtrl", [0xA3] = "RCtrl", [0xA4] = "LAlt", [0xA5] = "RAlt",
}
for i = 0x41, 0x5A do VK_NAMES[i] = string.char(i) end
for i = 0x30, 0x39 do VK_NAMES[i] = string.char(i) end
for i = 1, 12 do VK_NAMES[0x6F + i] = "F" .. i end
local function getKeyName(vk)
    if not vk or vk == 0 then return "None" end
    return VK_NAMES[vk] or string.format("0x%X", vk)
end

-- ── 3D primitives ───────────────────────────────────────────────────────
local function rect(s, x, y, w, h, color, v)
    if v and w > 0 and h > 0 then
        s.Position = V(floor(x), floor(y)); s.Size = V(floor(w), floor(h)); s.Color = color; s.Visible = true
    else
        s.Visible = false
    end
end
local function mkBevel(create)
    local b = {}
    for i = 1, 5 do b[i] = create("Square", { Filled = true }) end
    return b
end
local function mkSquares(create, n)
    local t = {}
    for i = 1, n do t[i] = create("Square", { Filled = true }) end
    return t
end
local function mkText(create, size, font, extra)
    local p = { Text = "", Size = size or 13, Font = font or F_UI, Outline = false }
    if extra then for k, v in pairs(extra) do p[k] = v end end
    return create("Text", p)
end
-- layers: outer bottom-right, outer top-left, inner bottom-right, inner top-left
local function bevelColors(T, kind, face)
    if kind == "window" then return T.Dk, T.Lt, T.Sh, T.Hi
    elseif kind == "field" then return T.Hi, T.Sh, T.Lt, T.Dk
    elseif kind == "pressed" then return T.Hi, T.Dk, T.Lt, T.Sh
    elseif kind == "thin" then return T.Hi, T.Sh, face, face
    elseif kind == "thinUp" then return T.Sh, T.Hi, face, face
    end
    return T.Dk, T.Hi, T.Sh, T.Lt
end
local function paintBevel(b, x, y, w, h, kind, face, v, T)
    if not v or w < 3 or h < 3 then
        for i = 1, 5 do b[i].Visible = false end
        return
    end
    x, y, w, h = floor(x), floor(y), floor(w), floor(h)
    local c1, c2, c3, c4 = bevelColors(T, kind, face)
    rect(b[1], x, y, w, h, c1, true)
    rect(b[2], x, y, w - 1, h - 1, c2, true)
    rect(b[3], x + 1, y + 1, w - 2, h - 2, c3, true)
    rect(b[4], x + 1, y + 1, w - 3, h - 3, c4, true)
    rect(b[5], x + 2, y + 2, w - 4, h - 4, face, true)
end
-- 7 px arrow made of 4 pixel rows
local function paintArrow(a, cx, cy, dir, color, v)
    cx, cy = floor(cx), floor(cy)
    for i = 1, 4 do
        local len = 9 - i * 2
        local half = (len - 1) / 2
        local s = a[i]
        if dir == "down" then rect(s, cx - half, cy - 2 + i - 1, len, 1, color, v)
        elseif dir == "up" then rect(s, cx - half, cy + 1 - (i - 1), len, 1, color, v)
        elseif dir == "right" then rect(s, cx - 2 + i - 1, cy - half, 1, len, color, v)
        else rect(s, cx + 1 - (i - 1), cy - half, 1, len, color, v) end
    end
end
-- Win95 check mark: 7 columns of 1x3 px
local CHECK = { 2, 3, 4, 3, 2, 1, 0 }
local function paintCheck(c, x, y, color, v)
    for i = 1, 7 do rect(c[i], x + i - 1, y + CHECK[i], 1, 3, color, v) end
end

-- ── Global input ────────────────────────────────────────────────────────
local function isMouseDown()
    if type(isrbxactive) == "function" then
        local ok, a = pcall(isrbxactive)
        if ok and a == false then return false end
    end
    if type(ismouse1pressed) == "function" then
        local ok, r = pcall(ismouse1pressed)
        if ok then return r == true end
    end
    if type(iskeypressed) == "function" then
        local ok, r = pcall(iskeypressed, 0x01)
        if ok then return r == true end
    end
    if UserInputService then
        local ok, r = pcall(function() return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) end)
        return ok and r == true
    end
    return false
end
local function mousePos()
    if mouse then return mouse.X, mouse.Y end
    if UserInputService then
        local ok, p = pcall(function() return UserInputService:GetMouseLocation() end)
        if ok and p then return p.X, p.Y end
    end
    return -1, -1
end

-- ── Library ─────────────────────────────────────────────────────────────
local Retro = { Version = "1.0.0", Flags = {}, _controls = {}, _watchers = {}, _alive = true, _windows = {}, _theme = Themes["Windows 98"] }
local epoch = 0
local function markDirty() epoch = epoch + 1 end

local function notifyWatchers(flag, value)
    local list = Retro._watchers[flag]
    if not list then return end
    for _, e in ipairs(list) do if e.live then fire(e.callback, value) end end
end
local function commit(el, value, silent)
    el.value = value
    markDirty()
    if el.flag ~= nil then
        Retro.Flags[el.flag] = value
        if not silent then notifyWatchers(el.flag, value) end
    end
    if not silent then fire(el.callback, value) end
end
local function normalize(el, v)
    local t = el.type
    if t == "toggle" then return v == true
    elseif t == "slider" then
        v = finite(v, el.value or el.min)
        local n = clamp(el.min + floor((v - el.min) / el.step + 0.5) * el.step, el.min, el.max)
        if el.step % 1 ~= 0 then n = tonumber(string.format("%.4f", n)) end
        return n
    elseif t == "input" then return string.sub(tostring(v == nil and "" or v), 1, el.maxLen or 256)
    elseif t == "keybind" then return normalizeKey(v)
    elseif t == "colorpicker" then
        if colorValid(v) then return v end
        return nil
    elseif t == "progressbar" then return clamp(finite(v, el.value or 0), 0, 1)
    elseif t == "dropdown" then
        if el.multi then
            local s = {}
            if type(v) == "table" then
                for _, o in ipairs(el.options) do if v[o] == true then s[o] = true end end
                for _, e in ipairs(v) do
                    for _, o in ipairs(el.options) do if o == tostring(e) then s[o] = true end end
                end
            end
            return s
        end
        if v == nil then return nil end
        v = tostring(v)
        for _, o in ipairs(el.options) do if o == v then return o end end
        return nil
    end
    return v
end

function Retro:Set(flag, value, silent)
    local c = self._controls[flag]
    if c and not c.el.destroyed then c.handle:Set(value, silent); return end
    self.Flags[flag] = value
    markDirty()
    if not silent then notifyWatchers(flag, value) end
end
function Retro:Get(flag) return self.Flags[flag] end
function Retro:Watch(flag, cb)
    assert(type(cb) == "function", "Retro95: Watch needs a function")
    local list = self._watchers[flag] or {}
    self._watchers[flag] = list
    local entry = { callback = cb, live = true }
    list[#list + 1] = entry
    return { Disconnect = function() entry.live = false end }
end
function Retro:GetThemes()
    local list = {}
    for i, n in ipairs(THEME_ORDER) do list[i] = n end
    return list
end
function Retro:SetTheme(name)
    local t = Themes[name]
    if not t then return false end
    self._theme = t
    markDirty()
    return true
end
function Retro:SetTransparency() return self end
function Retro:SetLayout() return self end
function Retro:GetCapabilities()
    return {
        Drawing = true, ZIndex = HAS_Z, TextBounds = HAS_BOUNDS,
        KeyPolling = type(iskeypressed) == "function",
        MousePolling = type(ismouse1pressed) == "function" or type(iskeypressed) == "function",
        FileRead = type(readfile) == "function", FileWrite = type(writefile) == "function",
    }
end
function Retro:ExportConfig()
    local result = { Version = 1, Values = {} }
    for flag, c in pairs(self._controls) do
        local el = c.el
        if not el.destroyed and el.value ~= nil and el.type ~= "button" then
            local value = el.value
            if el.type == "colorpicker" then value = { R = value.R, G = value.G, B = value.B } end
            result.Values[flag] = { Type = el.type, Value = value }
        end
    end
    local http = service("HttpService")
    local ok, json = pcall(function() return http:JSONEncode(result) end)
    if not ok then return nil, "JSONEncode is unavailable" end
    return json
end
function Retro:ImportConfig(json, silent)
    local http = service("HttpService")
    local ok, data = pcall(function() return http:JSONDecode(json) end)
    if not ok or type(data) ~= "table" or data.Version ~= 1 or type(data.Values) ~= "table" then
        return false, "Invalid JSON configuration or unsupported version"
    end
    local applied = 0
    for flag, entry in pairs(data.Values) do
        local c = self._controls[flag]
        if c and not c.el.destroyed and type(entry) == "table" and entry.Type == c.el.type then
            local value = entry.Value
            if c.el.type == "colorpicker" and type(value) == "table" and colorValid(value) then value = Color3.new(value.R, value.G, value.B) end
            if pcall(function() c.handle:Set(value, silent ~= false) end) then applied = applied + 1 end
        end
    end
    return true, applied
end
function Retro:SaveConfig(path)
    if type(writefile) ~= "function" then return false, "writefile is unavailable" end
    local json, err = self:ExportConfig()
    if not json then return false, err end
    return pcall(writefile, path, json)
end
function Retro:LoadConfig(path, silent)
    if type(readfile) ~= "function" then return false, "readfile is unavailable" end
    local ok, json = pcall(readfile, path)
    if not ok then return false, tostring(json) end
    return self:ImportConfig(json, silent)
end

-- ── Notifications: small dialog boxes in the bottom-right corner ────────
local notifs, notifConn, nPrev = {}, nil, false
local NW = 270
local NOTE_KIND = {
    info = { c = rgb(0, 0, 200), g = "i", gc = WHITE },
    warning = { c = rgb(255, 220, 0), g = "!", gc = BLACK },
    error = { c = rgb(220, 0, 0), g = "x", gc = WHITE },
    success = { c = rgb(0, 140, 0), g = "", gc = WHITE },
}
local function killNotif(n) for _, d in ipairs(n.all) do kill(d) end end
local function notifStep()
    local T = Retro._theme
    local vp = viewport
    local now = clock()
    local mx, my = mousePos()
    local down = isMouseDown()
    local click = down and not nPrev
    nPrev = down
    local by = vp.Y - 10
    for i = #notifs, 1, -1 do
        local n = notifs[i]
        if n.closed or now - n.t0 >= n.dur then
            killNotif(n)
            table.remove(notifs, i)
        else
            local p = clamp((now - n.t0) / 0.18, 0, 1)
            p = 1 - (1 - p) ^ 3
            local x = floor(vp.X - (NW + 10) * p)
            local y = floor(by - n.h)
            by = y - 6
            local k = NOTE_KIND[n.kind]
            paintBevel(n.b, x, y, NW, n.h, "window", T.Face, true, T)
            rect(n.bar, x + 3, y + 3, NW - 6, 18, T.T1, true)
            n.title.Position = V(x + 7, y + 5); n.title.Color = T.TText; n.title.Visible = true
            local cbx, cby = x + NW - 21, y + 5
            local chot = inRect(mx, my, cbx, cby, 16, 14)
            if click and chot then n.closed = true end
            paintBevel(n.cb, cbx, cby, 16, 14, (chot and down) and "pressed" or "button", T.Face, true, T)
            n.x1.From = V(cbx + 4, cby + 3); n.x1.To = V(cbx + 11, cby + 10); n.x1.Color = T.Text; n.x1.Visible = true
            n.x2.From = V(cbx + 11, cby + 3); n.x2.To = V(cbx + 4, cby + 10); n.x2.Color = T.Text; n.x2.Visible = true
            local icx, icy = x + 24, y + 44
            n.ring.Position = V(icx, icy); n.ring.Color = BLACK; n.ring.Visible = true
            n.disc.Position = V(icx, icy); n.disc.Color = k.c; n.disc.Visible = true
            n.glyph.Position = V(icx, icy - 9); n.glyph.Color = k.gc; n.glyph.Visible = k.g ~= ""
            local ok = n.kind == "success"
            n.k1.From = V(icx - 6, icy); n.k1.To = V(icx - 2, icy + 5); n.k1.Color = WHITE; n.k1.Visible = ok
            n.k2.From = V(icx - 2, icy + 5); n.k2.To = V(icx + 7, icy - 5); n.k2.Color = WHITE; n.k2.Visible = ok
            n.body.Position = V(x + 48, y + 30); n.body.Color = T.Text; n.body.Visible = true
        end
    end
end
function Retro:Notify(cfg)
    if not self._alive then return end
    cfg = cfg or {}
    local kind = string.lower(tostring(cfg.Type or "info"))
    if not NOTE_KIND[kind] then kind = "info" end
    local body, lines = wrapText(tostring(cfg.Content or ""), 34)
    local n = { t0 = clock(), dur = max(0.5, finite(cfg.Duration, 4)), kind = kind, all = {}, h = max(76, 40 + lines * 14 + 10) }
    local function mk(k, p)
        p = p or {}
        p.Visible = false
        if HAS_Z then p.ZIndex = 10 end
        local d = newDraw(k, p)
        n.all[#n.all + 1] = d
        return d
    end
    n.b = mkBevel(mk)
    n.bar = mk("Square", { Filled = true })
    n.title = mkText(mk, 13, F_SYS, { Text = tostring(cfg.Title or "Notice") })
    n.cb = mkBevel(mk)
    n.x1 = mk("Line", { Thickness = 2 }); n.x2 = mk("Line", { Thickness = 2 })
    n.ring = mk("Circle", { Filled = true, NumSides = 24, Radius = 13 })
    n.disc = mk("Circle", { Filled = true, NumSides = 24, Radius = 12 })
    n.glyph = mkText(mk, 18, F_SYS, { Text = NOTE_KIND[kind].g, Center = true })
    n.k1 = mk("Line", { Thickness = 2 }); n.k2 = mk("Line", { Thickness = 2 })
    n.body = mkText(mk, 13, F_UI, { Text = body })
    notifs[#notifs + 1] = n
    while #notifs > 6 do killNotif(table.remove(notifs, 1)) end
    if not notifConn then
        notifConn = connectFrame(function()
            if not Retro._alive or #notifs == 0 then
                local old = notifConn
                notifConn = nil
                if old then pcall(function() old:Disconnect() end) end
                return
            end
            local ok, err = pcall(notifStep)
            if not ok then report("Notify: " .. tostring(err)) end
        end)
    end
end

-- ── Window ──────────────────────────────────────────────────────────────
local TITLE_H, STATUS_H, ROW_H = 18, 18, 18
local MINI_W, MINI_H = 180, 30
local POP_N, SLICES, CHUNKS = 12, 10, 40
local CAP_ID = { "cap1", "cap2", "cap3" }
local TYPE_KEYS = {}
for i = 0x41, 0x5A do TYPE_KEYS[#TYPE_KEYS + 1] = i end
for i = 0x30, 0x39 do TYPE_KEYS[#TYPE_KEYS + 1] = i end
for _, k in ipairs({ 0x20, 0x08, 0x0D, 0x1B, 0xBD, 0xBE, 0xBC, 0xBF, 0xBA }) do TYPE_KEYS[#TYPE_KEYS + 1] = k end
local SHIFT_DIGITS = { ["1"] = "!", ["2"] = "@", ["3"] = "#", ["4"] = "$", ["5"] = "%", ["6"] = "^", ["7"] = "&", ["8"] = "*", ["9"] = "(", ["0"] = ")" }
local PUNCT = { [0x20] = " ", [0xBD] = "-", [0xBE] = ".", [0xBC] = ",", [0xBF] = "/", [0xBA] = ";" }
local BASE_H = { header = 24, toggle = 22, slider = 48, button = 24, dropdown = 44, keybind = 26,
    colorpicker = 26, input = 44, progressbar = 42, divider = 12 }
local FULL = { header = true, paragraph = true, divider = true, space = true }
local NO_VALUE = { button = true, header = true, paragraph = true, divider = true, space = true }
local DEFAULT_PALETTE = {
    rgb(0, 0, 0), rgb(128, 0, 0), rgb(0, 128, 0), rgb(128, 128, 0), rgb(0, 0, 128), rgb(128, 0, 128), rgb(0, 128, 128), rgb(128, 128, 128),
    rgb(192, 192, 192), rgb(255, 0, 0), rgb(0, 255, 0), rgb(255, 255, 0), rgb(0, 0, 255), rgb(255, 0, 255), rgb(0, 255, 255), rgb(255, 255, 255),
}

function Retro:CreateWindow(cfg)
    assert(self._alive, "Retro95: the library was destroyed, load it again")
    refreshRuntime()
    cfg = cfg or {}
    if cfg.Theme and Themes[cfg.Theme] then Retro._theme = Themes[cfg.Theme] end
    local title = tostring(cfg.Title or "Retro95")
    local author = cfg.Author and tostring(cfg.Author) or nil
    local statusDefault = tostring(cfg.Status or "Ready")
    local togKey = normalizeKey(cfg.ToggleKey or 0x79)
    local hasMenu = cfg.MenuBar ~= false
    local MIN_W, MIN_H, MAX_W, MAX_H = 460, 340, 1000, 760
    local TREE_W = clamp(floor(finite(cfg.TreeWidth, 150)), 110, 240)
    local MENU_H = hasMenu and 20 or 0
    local normW = clamp(finite(cfg.Size and cfg.Size[1], 600), MIN_W, MAX_W)
    local normH = clamp(finite(cfg.Size and cfg.Size[2], 440), MIN_H, MAX_H)
    local W, H = normW, normH
    local winX, winY = floor((viewport.X - W) / 2), floor((viewport.Y - H) / 2)

    local visible, minimized, maximized, preMax = true, false, false, nil
    local windowAlive, winHidden, miniShown = true, false, false
    local miniX, miniY, anim, captured = nil, nil, nil, nil
    local dg = { x = 0, y = 0, rx = 0, ry = 0, mx = 0, my = 0, sx = 0, sy = 0, moved = false }
    local lastTitleClick, lastToggle = 0, 0
    local scrollY, maxScroll = 0, 0
    local pan = { y = 0, s = 0, pending = false }
    local cRect = { 0, 0, 0, 0 }
    local openMenu, popItems, popW = nil, {}, 120
    local openEl, focusEl, activeInput, activeCaptor = nil, nil, nil, nil
    local hoverText = nil
    local fps, frames, fpsT = 60, 0, clock()
    local clockText = ""
    local errShown = false
    local conns, watermarks = {}, {}
    local draws, miniDraws, extras = {}, {}, {}
    local keybinds, sections, tabs = {}, {}, {}
    local activeTab = nil
    local fnow, fmx, fmy, fdown, fclick, frelease = 0, 0, 0, false, false, false
    local clipY, clipH, hoverOK, cclick = 0, 0, false, false
    local fits = { title = {}, head = {}, status = {}, mini = {} }
    local gradT, gradC = nil, {}

    local function wd(kind, props, list)
        props = props or {}
        if props.Visible == nil then props.Visible = false end
        if HAS_Z and props.ZIndex == nil then props.ZIndex = 1 end
        local d = newDraw(kind, props)
        local l = list or draws
        l[#l + 1] = d
        return d
    end
    local function wdm(kind, props) return wd(kind, props, miniDraws) end
    local function sq() return wd("Square", { Filled = true }) end

    -- frame, title bar and caption buttons
    local frameB = mkBevel(wd)
    local slices = mkSquares(wd, SLICES)
    local ticon = mkSquares(wd, 3)
    local titleTxt = mkText(wd, 13, F_SYS, { Text = title })
    local caps = {}
    for i = 1, 3 do
        caps[i] = { b = mkBevel(wd), g = mkSquares(wd, 4) }
        if i == 1 then
            caps[i].l1 = wd("Line", { Thickness = 2 })
            caps[i].l2 = wd("Line", { Thickness = 2 })
        end
    end
    local menuHL = mkBevel(wd)
    local treeB = mkBevel(wd)
    local pageB = mkBevel(wd)
    local headTxt = mkText(wd, 14, F_SYS)
    local headCrumb = mkText(wd, 13)
    local headE = mkSquares(wd, 2)
    local panes = { mkBevel(wd), mkBevel(wd), mkBevel(wd) }
    local paneTxt = { mkText(wd, 13), mkText(wd, 13), mkText(wd, 13) }
    local grip = {}
    for i = 1, 6 do grip[i] = wd("Line", { Thickness = 1 }) end

    local mini = { b = mkBevel(wdm), g = mkSquares(wdm, 2), btn = mkBevel(wdm), icon = mkSquares(wdm, 3),
        txt = mkText(wdm, 13, F_SYS, { Text = title }) }

    local zoomSq = newDraw("Square", { Filled = true, Visible = false, ZIndex = 6 })
    local meter = newDraw("Text", { Visible = false, Size = 13, Font = F_UI, Text = "" })
    extras[1], extras[2] = zoomSq, meter

    local doMinimize, doRestore, toggleMax, doHide, showAbout, toggleUI, selectTab

    -- ── menus ──
    local pop = nil
    local function ensurePop()
        if pop then return end
        local function zc(kind, props)
            props = props or {}
            props.ZIndex = 5
            return wd(kind, props)
        end
        pop = { b = mkBevel(zc), slots = {} }
        for i = 1, POP_N do
            pop.slots[i] = {
                hl = zc("Square", { Filled = true }), t = mkText(zc, 13), sc = mkText(zc, 13),
                dot = zc("Square", { Filled = true }), s1 = zc("Square", { Filled = true }), s2 = zc("Square", { Filled = true }),
            }
        end
    end
    local function hidePop()
        if not pop then return end
        hideAll(pop.b)
        for _, s in ipairs(pop.slots) do
            s.hl.Visible = false; s.t.Visible = false; s.sc.Visible = false
            s.dot.Visible = false; s.s1.Visible = false; s.s2.Visible = false
        end
    end
    local function closeMenu()
        if openMenu then openMenu = nil; markDirty() end
    end
    local menuDefs = {}
    local function openMenuAt(i)
        ensurePop()
        openMenu = i
        popItems = menuDefs[i].build()
        local wmax = 60
        for k = 1, POP_N do
            local it, s = popItems[k], pop.slots[k]
            if it and not it.sep then
                s.t.Text = it.text or ""
                s.sc.Text = it.sc or ""
                local ww = textW(s.t, 13) + (it.sc and (textW(s.sc, 13) + 24) or 0)
                if ww > wmax then wmax = ww end
            end
        end
        popW = floor(wmax + 44)
        markDirty()
    end
    local function addMenuDraws(def)
        def.t = mkText(wd, 13, F_UI, { Text = def.title })
        def.ul = sq()
        meter.Text = string.sub(def.title, 1, 1)
        def.ulW = max(4, floor(textW(meter, 13)) - 1)
    end
    menuDefs = {
        { title = "Window", build = function()
            return {
                { text = "Minimize", act = function() doMinimize() end },
                { text = maximized and "Restore" or "Maximize", act = function() toggleMax() end },
                { sep = true },
                { text = "Hide", sc = getKeyName(togKey), act = function() doHide() end },
            }
        end },
        { title = "View", build = function()
            local list = {}
            for _, name in ipairs(THEME_ORDER) do
                list[#list + 1] = { text = name, radio = Retro._theme.Name == name, act = function() Retro:SetTheme(name) end }
            end
            return list
        end },
        { title = "Help", build = function()
            return { { text = "About " .. title .. "...", act = function() showAbout() end } }
        end },
    }
    if hasMenu then for _, def in ipairs(menuDefs) do addMenuDraws(def) end end

    -- ── keyboard ──
    local POLL = type(iskeypressed) == "function"
    local keyPrev = {}

    local function keyIsDown(vk)
        local ok, r = pcall(iskeypressed, vk)
        return ok and r == true
    end
    local function keyEdge(vk)
        local d = keyIsDown(vk)
        local was = keyPrev[vk]
        keyPrev[vk] = d
        return d and not was
    end
    local function snapshotKeys(from, to)
        if not POLL then return end
        for vk = from, to do keyPrev[vk] = keyIsDown(vk) end
    end
    local function finishInput()
        local el = activeInput
        if not el then return end
        activeInput = nil
        commit(el, el.text)
    end
    local function focusInput(el)
        finishInput()
        activeCaptor = nil
        activeInput = el
        el.text = el.value
        snapshotKeys(0x08, 0xFE)
        markDirty()
    end
    local function typeKey(vk, shift)
        local el = activeInput
        if not el then return end
        if vk == 0x08 then
            el.text = utf8Prefix(el.text, #el.text - 1)
        elseif vk == 0x0D or vk == 0x1B then
            finishInput()
            return
        elseif vk >= 0x41 and vk <= 0x5A then
            local c = string.char(vk)
            el.text = el.text .. (shift and c or string.lower(c))
        elseif vk >= 0x30 and vk <= 0x39 then
            local c = string.char(vk)
            el.text = el.text .. (shift and (SHIFT_DIGITS[c] or c) or c)
        elseif PUNCT[vk] then
            el.text = el.text .. PUNCT[vk]
        end
        if #el.text > el.maxLen then el.text = string.sub(el.text, 1, el.maxLen) end
        markDirty()
    end
    local function captureKey(vk)
        local el = activeCaptor
        if not el then return end
        activeCaptor = nil
        if vk ~= 0x1B then commit(el, vk) else markDirty() end
    end
    local function startListen(el)
        finishInput()
        activeCaptor = el
        el.listenT = clock()
        snapshotKeys(0x02, 0xFE)
        markDirty()
    end
    local function applyKeybind(el, down)
        if el.destroyed then return end
        local hit = down and not el.keyDown
        el.keyDown = down
        local val = el.enabled
        if el.mode == "hold" then val = down
        elseif el.mode == "always" then val = true
        elseif el.mode == "click" then val = hit
        elseif hit then val = not val end
        if val ~= el.enabled then
            el.enabled = val
            fire(el.onTriggered, val, el.value)
        end
    end
    local function closeOverlays()
        closeMenu()
        if openEl then openEl.open = false; openEl = nil; markDirty() end
    end
    local function pollKeys(now)
        if not POLL then return end
        if type(isrbxactive) == "function" then
            local ok, a = pcall(isrbxactive)
            if ok and a == false then return end
        end
        if activeCaptor then
            if now - (activeCaptor.listenT or 0) > 0.15 then
                for vk = 0x02, 0xFE do
                    if keyEdge(vk) then captureKey(vk); break end
                end
            end
            return
        end
        if activeInput then
            local shift = keyIsDown(0x10)
            for _, vk in ipairs(TYPE_KEYS) do
                if keyEdge(vk) then typeKey(vk, shift) end
            end
            return
        end
        if keyEdge(togKey) then toggleUI() end
        if togKey ~= 0x1B and keyEdge(0x1B) then closeOverlays() end
        for _, el in ipairs(keybinds) do
            applyKeybind(el, el.value > 0 and keyIsDown(el.value))
        end
    end

    -- ── elements ──
    local function hideElem(el) for _, d in ipairs(el.all) do d.Visible = false end end
    local function hideTab(tab)
        if not tab then return end
        for _, el in ipairs(tab.elems) do hideElem(el); el.culled = true end
    end
    local function paletteCols(w) return max(1, floor((w + 2) / 24)) end
    local function elemHeight(el, w)
        local t = el.type
        if t == "paragraph" then
            if el.wrapW ~= w then
                local text, lines = wrapText(el.title, max(10, floor((w - 4) / 6.3)))
                el.d.txt.Text = text
                el.height = lines * 14 + 4
                el.wrapW = w
            end
            return el.height
        elseif t == "space" then
            return el.height
        end
        local h = BASE_H[t] or 20
        if t == "dropdown" and el.open then
            h = h + #el.options * 16 + 4
        elseif t == "colorpicker" and el.open then
            h = h + math.ceil(#el.presets / paletteCols(w)) * 22 + 4
        end
        return h
    end
    local function measure(tab, width)
        local items, x, y, rowH = {}, 0, 0, 0
        local cols, gap = tab.columns or 1, 8
        for _, el in ipairs(tab.elems) do
            if not el.destroyed and el.visible then
                local full = cols == 1 or FULL[el.type]
                local ew = full and width or floor((width - gap * (cols - 1)) / cols)
                if x > 0 and (full or x + ew > width + 1) then y = y + rowH + 4; x = 0; rowH = 0 end
                local eh = elemHeight(el, ew)
                items[#items + 1] = { el, x, y, ew }
                if full then
                    y = y + eh + 4; x = 0; rowH = 0
                else
                    x = x + ew + gap; rowH = max(rowH, eh)
                end
            end
        end
        return items, y + rowH
    end
    local function label(el, x, y, room, T, v)
        local d = el.d.lbl
        fitInto(d, el.title, room, el)
        d.Position = V(x, y); d.Color = T.Text; d.Visible = v
    end
    local function toggleOpen(el)
        if el.open then
            el.open = false
            if openEl == el then openEl = nil end
        else
            if openEl and openEl ~= el then openEl.open = false end
            el.open = true
            openEl = el
        end
        markDirty()
    end

    local function renderElem(el, x, y, w, T)
        local t, d = el.type, el.d
        local fullH = elemHeight(el, w)
        if y + fullH < clipY or y > clipY + clipH then
            if not el.culled then hideElem(el); el.culled = true end
            if el.open and fclick then el.open = false; if openEl == el then openEl = nil end end
            return
        end
        el.culled = false
        local baseH = (t == "paragraph" or t == "space") and el.height or BASE_H[t] or 20
        local v = y >= clipY and y + baseH <= clipY + clipH
        local hot = v and hoverOK and inRect(fmx, fmy, x, y, w, baseH)
        if hot and t ~= "space" and t ~= "divider" then hoverText = el.desc or el.title end

        if t == "header" then
            d.txt.Position = V(x, y + 6); d.txt.Color = T.Text; d.txt.Visible = v
            local lx = x + floor(textW(d.txt, 13)) + 8
            rect(d.e1, lx, y + 13, x + w - lx, 1, T.Sh, v)
            rect(d.e2, lx, y + 14, x + w - lx, 1, T.Hi, v)

        elseif t == "toggle" then
            if hot and cclick then captured = el end
            if frelease and captured == el and hot then commit(el, not el.value) end
            local push = captured == el and hot and fdown
            paintBevel(d.box, x + 1, y + 4, 13, 13, "field", push and T.Face or T.Win, v, T)
            paintCheck(d.chk, x + 4, y + 7, T.Text, v and el.value)
            label(el, x + 21, y + 4, w - 22, T, v)

        elseif t == "slider" then
            d.val.Text = fmtNum(el.value, el.step) .. el.suffix
            local vw = max(44, floor(textW(d.val, 13)) + 12)
            label(el, x, y + 3, w - vw - 8, T, v)
            paintBevel(d.vbox, x + w - vw, y, vw, 20, "field", T.Win, v, T)
            d.val.Position = V(x + w - vw + floor((vw - textW(d.val, 13)) / 2), y + 3); d.val.Color = T.Text; d.val.Visible = v
            local tx, tw = x + 5, w - 10
            if hot and cclick and fmy >= y + 18 then captured = el end
            if captured == el and fdown then
                local p = clamp((fmx - tx - 5) / max(1, tw - 11), 0, 1)
                local nv = normalize(el, el.min + (el.max - el.min) * p)
                if nv ~= el.value then commit(el, nv) end
            end
            local frac = (el.value - el.min) / max(el.max - el.min, 1e-9)
            paintBevel(d.groove, tx, y + 28, tw, 4, "field", T.Face, v, T)
            paintBevel(d.thumb, tx + floor(frac * (tw - 11) + 0.5), y + 20, 11, 20, "button", T.Face, v, T)
            for i = 1, 6 do
                rect(d.ticks[i], tx + 5 + floor((i - 1) / 5 * (tw - 11) + 0.5), y + 42, 1, 4, T.Text, v)
            end

        elseif t == "button" then
            local bh = 24
            if hot and cclick then captured = el end
            if frelease and captured == el and hot then focusEl = el; fire(el.callback) end
            local push = captured == el and hot and fdown
            local bx, by, bw, bhh = x, y, w, bh
            if el.primary or focusEl == el then
                rect(d.def, x, y, w, bh, T.Dk, v)
                bx, by, bw, bhh = x + 1, y + 1, w - 2, bh - 2
            else
                d.def.Visible = false
            end
            paintBevel(d.b, bx, by, bw, bhh, push and "pressed" or "button", T.Face, v, T)
            fitInto(d.lbl, el.title, w - 16, el)
            local o = push and 1 or 0
            d.lbl.Position = V(x + floor((w - textW(d.lbl, 13)) / 2) + o, y + 5 + o)
            d.lbl.Color = el.danger and T.Danger or T.Text; d.lbl.Visible = v
            local f = d.focus
            if v and focusEl == el then
                f.Position = V(x + 4, y + 4); f.Size = V(w - 8, bh - 8); f.Color = T.Sh; f.Visible = true
            else
                f.Visible = false
            end

        elseif t == "dropdown" then
            label(el, x, y + 3, w, T, v)
            local fy = y + 20
            local n = #el.options
            local ly, lh = fy + 21, n * 16 + 2
            if fclick and el.open and not inRect(fmx, fmy, x, fy, w, 21 + lh) then
                el.open = false
                if openEl == el then openEl = nil end
                markDirty()
            end
            local fhot = v and hoverOK and inRect(fmx, fmy, x, fy, w, 21)
            if fhot and cclick then toggleOpen(el) end
            paintBevel(d.field, x, fy, w, 21, "field", T.Win, v, T)
            local s
            if el.multi then
                local list = {}
                for _, o in ipairs(el.options) do if el.value[o] then list[#list + 1] = o end end
                s = #list == 0 and "(none)" or table.concat(list, ", ")
            else
                s = el.value ~= nil and tostring(el.value) or ""
            end
            local maxC = max(3, floor((w - 30) / 6.3))
            if #s > maxC then s = utf8Prefix(s, maxC - 3) .. "..." end
            d.val.Text = s
            rect(d.vhl, x + 3, fy + 3, w - 22, 15, T.Sel, v and el.open)
            d.val.Position = V(x + 5, fy + 3); d.val.Color = el.open and T.SelText or T.Text; d.val.Visible = v
            local bpush = fhot and fdown
            local o = bpush and 1 or 0
            paintBevel(d.btn, x + w - 18, fy + 2, 16, 17, bpush and "pressed" or "button", T.Face, v, T)
            paintArrow(d.arr, x + w - 11 + o, fy + 10 + o, "down", T.Text, v)
            if el.open then
                local top, bot = max(ly, clipY), min(ly + lh, clipY + clipH)
                rect(d.lbox, x, top, w, bot - top, T.Dk, bot - top > 2)
                rect(d.lin, x + 1, top + 1, w - 2, bot - top - 2, T.Win, bot - top > 4)
            else
                d.lbox.Visible = false; d.lin.Visible = false
            end
            local hovIdx = nil
            if el.open and hoverOK then
                for i = 1, n do
                    if inRect(fmx, fmy, x + 1, ly + 1 + (i - 1) * 16, w - 2, 16) then hovIdx = i end
                end
            end
            for i, opt in ipairs(el.options) do
                local od = el.opts[i]
                local oy = ly + 1 + (i - 1) * 16
                local ov = el.open and oy >= clipY and oy + 16 <= clipY + clipH
                local sel
                if el.multi then sel = el.value[opt] == true else sel = el.value == opt end
                local hl = ov and (hovIdx == i or (hovIdx == nil and not el.multi and sel))
                if ov and hovIdx == i then hoverText = opt end
                rect(od.hl, x + 1, oy, w - 2, 16, T.Sel, hl)
                local col = hl and T.SelText or T.Text
                local tx0 = x + 4
                if el.multi then
                    rect(od.b1, x + 4, oy + 3, 10, 10, col, ov)
                    rect(od.b2, x + 5, oy + 4, 8, 8, hl and T.Sel or T.Win, ov)
                    rect(od.b3, x + 7, oy + 6, 4, 4, col, ov and sel)
                    tx0 = x + 19
                end
                od.t.Position = V(tx0, oy + 1); od.t.Color = col; od.t.Visible = ov
                if ov and cclick and hovIdx == i then
                    if el.multi then
                        local nv = {}
                        for k2, v2 in pairs(el.value) do nv[k2] = v2 end
                        nv[opt] = (not sel) or nil
                        commit(el, nv)
                    else
                        el.open = false
                        openEl = nil
                        if el.value ~= opt then commit(el, opt) else markDirty() end
                    end
                end
            end

        elseif t == "keybind" then
            local bw = 96
            local bx = x + w - bw
            d.mode.Text = "[" .. el.mode .. "]"
            local mw = floor(textW(d.mode, 13))
            label(el, x, y + 5, w - bw - mw - 16, T, v)
            if hot and cclick and activeCaptor ~= el then startListen(el) end
            local listening = activeCaptor == el
            paintBevel(d.field, bx, y + 2, bw, 21, "field", listening and T.Info or T.Win, v, T)
            d.key.Text = listening and "Press a key..." or getKeyName(el.value)
            d.key.Position = V(bx + floor((bw - textW(d.key, 13)) / 2), y + 5); d.key.Color = T.Text; d.key.Visible = v
            d.mode.Position = V(bx - 8 - mw, y + 5); d.mode.Color = T.Gray; d.mode.Visible = v

        elseif t == "colorpicker" then
            local bw = 50
            local bx = x + w - bw
            d.hex.Text = toHex(el.value)
            local hw = floor(textW(d.hex, 13))
            label(el, x, y + 5, w - bw - hw - 16, T, v)
            if fclick and el.open and not inRect(fmx, fmy, x, y, w, fullH) then
                el.open = false
                if openEl == el then openEl = nil end
                markDirty()
            end
            local bhot = v and hoverOK and inRect(fmx, fmy, bx, y + 1, bw, 22)
            if bhot and cclick then toggleOpen(el) end
            local push = bhot and fdown
            local o = push and 1 or 0
            paintBevel(d.btn, bx, y + 1, bw, 22, push and "pressed" or "button", T.Face, v, T)
            rect(d.swo, bx + 5 + o, y + 5 + o, 26, 14, T.Dk, v)
            rect(d.sw, bx + 6 + o, y + 6 + o, 24, 12, el.value, v)
            paintArrow(d.arr, bx + 40 + o, y + 12 + o, "down", T.Text, v)
            d.hex.Position = V(bx - 8 - hw, y + 5); d.hex.Color = T.Gray; d.hex.Visible = v
            local cols = paletteCols(w)
            for i, c in ipairs(el.presets) do
                local tile = el.tiles[i]
                local tx, ty = x + ((i - 1) % cols) * 24, y + 28 + floor((i - 1) / cols) * 22
                local tv = el.open and ty >= clipY and ty + 20 <= clipY + clipH
                local thot = tv and hoverOK and inRect(fmx, fmy, tx, ty, 22, 20)
                local mark = tv and (thot or colorEq(c, el.value))
                rect(tile.f, tx, ty, 22, 20, T.Text, mark)
                rect(tile.g, tx + 1, ty + 1, 20, 18, T.Face, mark)
                rect(tile.b, tx + 2, ty + 2, 18, 16, T.Sh, tv)
                rect(tile.c, tx + 3, ty + 3, 16, 14, c, tv)
                if thot then hoverText = toHex(c) end
                if thot and cclick and not colorEq(c, el.value) then commit(el, c) end
            end

        elseif t == "input" then
            label(el, x, y + 3, w, T, v)
            local fy = y + 20
            local fhot = v and hoverOK and inRect(fmx, fmy, x, fy, w, 21)
            if fhot and cclick and activeInput ~= el then
                focusInput(el)
            elseif fclick and activeInput == el and not fhot then
                finishInput()
            end
            paintBevel(d.field, x, fy, w, 21, "field", T.Win, v, T)
            local focused = activeInput == el
            local s = focused and el.text or el.value
            local maxC = max(4, floor((w - 14) / 6.3))
            local shown, col
            if s == "" and not focused then
                shown, col = el.placeholder, T.Gray
                if #shown > maxC then shown = utf8Prefix(shown, maxC - 3) .. "..." end
            else
                shown, col = s, T.Text
                if #shown > maxC then shown = string.sub(shown, -maxC) end
            end
            d.txt.Text = shown
            d.txt.Position = V(x + 5, fy + 3); d.txt.Color = col; d.txt.Visible = v
            local caretX = x + 5 + (shown == "" and 0 or floor(textW(d.txt, 13))) + 1
            rect(d.caret, caretX, fy + 3, 1, 15, T.Text, v and focused and floor(fnow * 2) % 2 == 0)

        elseif t == "progressbar" then
            d.pct.Text = floor(el.value * 100 + 0.5) .. "%"
            local pw2 = floor(textW(d.pct, 13))
            label(el, x, y + 2, w - pw2 - 10, T, v)
            d.pct.Position = V(x + w - pw2, y + 2); d.pct.Color = T.Text; d.pct.Visible = v
            paintBevel(d.box, x, y + 20, w, 20, "thin", T.Face, v, T)
            local iw = w - 6
            local n, step = floor((iw + 2) / 11), 11
            if n > CHUNKS then n = CHUNKS; step = (iw + 2) / CHUNKS end
            local filled = floor(n * el.value + 0.0001)
            for i = 1, CHUNKS do
                local x0 = floor((i - 1) * step)
                rect(d.ch[i], x + 3 + x0, y + 23, floor(i * step) - x0 - 2, 14, T.Sel, v and i <= filled)
            end

        elseif t == "paragraph" then
            d.txt.Position = V(x + 2, y + 2); d.txt.Color = T.Text; d.txt.Visible = v

        elseif t == "divider" then
            rect(d.e1, x, y + 5, w, 1, T.Sh, v)
            rect(d.e2, x, y + 6, w, 1, T.Hi, v)
        end
    end

    -- ── window painting ──
    local menuX, menuW = {}, {}
    local function renderWindow(T)
        local vp = viewport
        if maximized then winX, winY, W, H = 0, 0, vp.X, vp.Y end
        if captured == "title" and fdown then
            winX = clamp(fmx - dg.x, 60 - W, vp.X - 60)
            winY = clamp(fmy - dg.y, 0, max(0, vp.Y - 30))
        elseif captured == "grip" and fdown then
            W = clamp(fmx - dg.rx, MIN_W, max(MIN_W, min(MAX_W, vp.X)))
            H = clamp(fmy - dg.ry, MIN_H, max(MIN_H, min(MAX_H, vp.Y)))
            normW, normH = W, H
        end
        local X, Y, w, h = floor(winX), floor(winY), floor(W), floor(H)
        local clickAvail = fclick
        local mbY = Y + 22
        local bodyY = mbY + MENU_H + (hasMenu and 2 or 0)
        local stY = Y + h - 4 - STATUS_H
        local bodyH = stY - 3 - bodyY

        if hasMenu then
            local ix = X + 6
            for i, m in ipairs(menuDefs) do
                menuX[i] = ix
                menuW[i] = floor(textW(m.t, 13)) + 12
                ix = ix + menuW[i]
            end
        end

        -- popup menu (click priority)
        if openMenu and pop then
            local px, py = menuX[openMenu], mbY + MENU_H - 1
            local count = min(#popItems, POP_N)
            local ph = 6
            for k = 1, count do ph = ph + (popItems[k].sep and 8 or 18) end
            paintBevel(pop.b, px, py, popW, ph, "window", T.Face, true, T)
            local iy, hov = py + 3, nil
            for k = 1, POP_N do
                local it, s = popItems[k], pop.slots[k]
                if it and k <= count then
                    if it.sep then
                        rect(s.s1, px + 4, iy + 3, popW - 8, 1, T.Sh, true)
                        rect(s.s2, px + 4, iy + 4, popW - 8, 1, T.Hi, true)
                        s.hl.Visible = false; s.t.Visible = false; s.sc.Visible = false; s.dot.Visible = false
                        iy = iy + 8
                    else
                        local hot = inRect(fmx, fmy, px + 3, iy, popW - 6, 18)
                        if hot then hov = k; hoverText = it.text end
                        rect(s.hl, px + 3, iy, popW - 6, 18, T.Sel, hot)
                        local col = hot and T.SelText or T.Text
                        s.t.Position = V(px + 22, iy + 2); s.t.Color = col; s.t.Visible = true
                        s.sc.Position = V(px + popW - 10 - floor(textW(s.sc, 13)), iy + 2); s.sc.Color = col; s.sc.Visible = it.sc ~= nil
                        rect(s.dot, px + 9, iy + 7, 5, 5, col, it.radio == true)
                        s.s1.Visible = false; s.s2.Visible = false
                        iy = iy + 18
                    end
                else
                    s.hl.Visible = false; s.t.Visible = false; s.sc.Visible = false
                    s.dot.Visible = false; s.s1.Visible = false; s.s2.Visible = false
                end
            end
            if clickAvail then
                if hov then
                    clickAvail = false
                    local it = popItems[hov]
                    closeMenu()
                    if it.act then it.act() end
                elseif not inRect(fmx, fmy, X, mbY, w, MENU_H) then
                    clickAvail = false
                    closeMenu()
                end
            end
        else
            hidePop()
        end

        -- frame and title
        paintBevel(frameB, X, Y, w, h, "window", T.Face, true, T)
        local tw = w - 6
        if colorEq(T.T1, T.T2) then
            rect(slices[1], X + 3, Y + 3, tw, TITLE_H, T.T1, true)
            for i = 2, SLICES do slices[i].Visible = false end
        else
            if gradT ~= T then
                gradT = T
                for i = 1, SLICES do gradC[i] = mixC(T.T1, T.T2, (i - 1) / (SLICES - 1)) end
            end
            for i = 1, SLICES do
                local x0 = floor((i - 1) * tw / SLICES)
                local x1 = floor(i * tw / SLICES)
                rect(slices[i], X + 3 + x0, Y + 3, x1 - x0, TITLE_H, gradC[i], true)
            end
        end
        rect(ticon[1], X + 5, Y + 6, 14, 12, BLACK, true)
        rect(ticon[2], X + 6, Y + 7, 12, 10, WHITE, true)
        rect(ticon[3], X + 6, Y + 7, 12, 3, ICON_BAR, true)
        fitInto(titleTxt, title, w - 85, fits.title)
        titleTxt.Position = V(X + 23, Y + 5); titleTxt.Color = T.TText; titleTxt.Visible = true

        local cbx = { X + w - 21, X + w - 39, X + w - 55 }
        local cby = Y + 5
        local tips = { "Close", maximized and "Restore" or "Maximize", "Minimize" }
        for i = 1, 3 do
            local c, bx, id = caps[i], cbx[i], CAP_ID[i]
            local hot = inRect(fmx, fmy, bx, cby, 16, 14)
            if hot then hoverText = tips[i] end
            if clickAvail and hot then clickAvail = false; captured = id end
            if frelease and captured == id and hot then
                if i == 1 then doHide() elseif i == 2 then toggleMax() else doMinimize() end
            end
            local push = captured == id and hot and fdown
            paintBevel(c.b, bx, cby, 16, 14, push and "pressed" or "button", T.Face, true, T)
            local o = push and 1 or 0
            local g = c.g
            if i == 1 then
                c.l1.From = V(bx + 4 + o, cby + 3 + o); c.l1.To = V(bx + 11 + o, cby + 10 + o); c.l1.Color = T.Text; c.l1.Visible = true
                c.l2.From = V(bx + 11 + o, cby + 3 + o); c.l2.To = V(bx + 4 + o, cby + 10 + o); c.l2.Color = T.Text; c.l2.Visible = true
                hideAll(g)
            elseif i == 2 then
                if maximized then
                    rect(g[1], bx + 5 + o, cby + 1 + o, 7, 7, T.Text, true)
                    rect(g[2], bx + 6 + o, cby + 3 + o, 5, 4, T.Face, true)
                    rect(g[3], bx + 2 + o, cby + 4 + o, 7, 7, T.Text, true)
                    rect(g[4], bx + 3 + o, cby + 6 + o, 5, 4, T.Face, true)
                else
                    rect(g[1], bx + 3 + o, cby + 2 + o, 9, 9, T.Text, true)
                    rect(g[2], bx + 4 + o, cby + 4 + o, 7, 6, T.Face, true)
                    g[3].Visible = false; g[4].Visible = false
                end
            else
                rect(g[1], bx + 4 + o, cby + 9 + o, 6, 2, T.Text, true)
                g[2].Visible = false; g[3].Visible = false; g[4].Visible = false
            end
        end
        if clickAvail and inRect(fmx, fmy, X + 3, Y + 3, w - 6, TITLE_H) then
            clickAvail = false
            if fnow - lastTitleClick < 0.4 then
                lastTitleClick = 0
                toggleMax()
            else
                lastTitleClick = fnow
                if not maximized then captured = "title"; dg.x, dg.y = fmx - winX, fmy - winY end
            end
        end
        if clickAvail and not maximized and inRect(fmx, fmy, X + w - 16, Y + h - 16, 16, 16) then
            clickAvail = false
            captured = "grip"
            dg.rx, dg.ry = fmx - W, fmy - H
        end

        -- menu bar
        if hasMenu then
            local hovM = nil
            for i, m in ipairs(menuDefs) do
                if inRect(fmx, fmy, menuX[i], mbY, menuW[i], MENU_H - 1) then hovM = i end
                m.t.Position = V(menuX[i] + 6, mbY + 3); m.t.Color = T.Text; m.t.Visible = true
                rect(m.ul, menuX[i] + 6, mbY + 16, m.ulW, 1, T.Text, true)
            end
            if hovM and openMenu and hovM ~= openMenu then openMenuAt(hovM) end
            if clickAvail and hovM then
                clickAvail = false
                if openMenu == hovM then closeMenu() else openMenuAt(hovM) end
            end
            local hi = openMenu or hovM
            if hi then
                paintBevel(menuHL, menuX[hi], mbY, menuW[hi], MENU_H - 1, openMenu and "thin" or "thinUp", T.Face, true, T)
            else
                hideAll(menuHL)
            end
        end

        -- tree (Explorer style)
        local tx, ty = X + 4, bodyY
        paintBevel(treeB, tx, ty, TREE_W, bodyH, "field", T.Win, true, T)
        local ry, clipB = ty + 4, ty + bodyH - 3
        for _, s in ipairs(sections) do
            local d = s.d
            local sv = ry + ROW_H <= clipB
            local shot = sv and inRect(fmx, fmy, tx + 2, ry, TREE_W - 4, ROW_H)
            if shot then hoverText = s.title end
            if clickAvail and shot then
                clickAvail = false
                s.collapsed = not s.collapsed
                markDirty()
            end
            rect(d.bo, tx + 6, ry + 4, 9, 9, T.Sh, sv)
            rect(d.bi, tx + 7, ry + 5, 7, 7, T.Win, sv)
            rect(d.mi, tx + 8, ry + 8, 5, 1, T.Text, sv)
            rect(d.pl, tx + 10, ry + 6, 1, 5, T.Text, sv and s.collapsed)
            rect(d.f1, tx + 19, ry + 3, 6, 3, FOLDER_DK, sv)
            rect(d.f2, tx + 19, ry + 5, 15, 10, FOLDER_DK, sv)
            rect(d.f3, tx + 20, ry + 6, 13, 8, FOLDER, sv)
            fitInto(d.txt, s.title, TREE_W - 44, s.fit)
            d.txt.Position = V(tx + 38, ry + 2); d.txt.Color = T.Text; d.txt.Visible = sv
            local secY = ry
            ry = ry + ROW_H
            local lastMid = nil
            for _, tab in ipairs(s.tabs) do
                local td = tab.d
                local tv = not s.collapsed and ry + ROW_H <= clipB
                local thot = tv and inRect(fmx, fmy, tx + 2, ry, TREE_W - 4, ROW_H)
                if thot then hoverText = tab.title end
                if clickAvail and thot then clickAvail = false; selectTab(tab) end
                local isA = tab == activeTab
                rect(td.stub, tx + 11, ry + 9, 9, 1, T.Sh, tv)
                rect(td.p1, tx + 22, ry + 2, 11, 14, T.Sh, tv)
                rect(td.p2, tx + 23, ry + 3, 9, 12, WHITE, tv)
                rect(td.p3, tx + 25, ry + 6, 5, 1, T.Sh, tv)
                rect(td.p4, tx + 25, ry + 9, 5, 1, T.Sh, tv)
                rect(td.p5, tx + 25, ry + 12, 3, 1, T.Sh, tv)
                fitInto(td.txt, tab.title, TREE_W - 46, tab.fit)
                rect(td.hl, tx + 37, ry + 1, floor(textW(td.txt, 13)) + 4, 16, T.Sel, tv and isA)
                td.txt.Position = V(tx + 39, ry + 2); td.txt.Color = isA and T.SelText or T.Text; td.txt.Visible = tv
                if tv then lastMid = ry + 9 end
                if not s.collapsed then ry = ry + ROW_H end
            end
            if lastMid then rect(d.vl, tx + 10, secY + 14, 1, lastMid - secY - 13, T.Sh, true) else d.vl.Visible = false end
        end

        -- content page
        local px = X + 4 + TREE_W + 3
        local pw = X + w - 4 - px
        paintBevel(pageB, px, bodyY, pw, bodyH, "window", T.Face, true, T)
        if activeTab then
            fitInto(headTxt, activeTab.title, pw - 130, fits.head)
            headTxt.Position = V(px + 10, bodyY + 8); headTxt.Color = T.Text; headTxt.Visible = true
            headCrumb.Text = activeTab.section.title
            headCrumb.Position = V(px + pw - 10 - floor(textW(headCrumb, 13)), bodyY + 9); headCrumb.Color = T.Gray; headCrumb.Visible = true
        else
            headTxt.Visible = false; headCrumb.Visible = false
        end
        rect(headE[1], px + 8, bodyY + 28, pw - 16, 1, T.Sh, true)
        rect(headE[2], px + 8, bodyY + 29, pw - 16, 1, T.Hi, true)
        local cx, cy = px + 10, bodyY + 36
        local cw, ch = pw - 20, bodyH - 42
        cRect[1], cRect[2], cRect[3], cRect[4] = cx, cy, cw, ch
        local items, total = {}, 0
        if activeTab then items, total = measure(activeTab, cw) end
        maxScroll = max(0, total - ch)
        -- Matcha does not expose the mouse wheel: content scrolls by dragging
        if captured == "pan" and fdown then scrollY = pan.s - (fmy - pan.y) end
        scrollY = floor(clamp(scrollY, 0, maxScroll) + 0.5)

        -- controls
        clipY, clipH = cy, ch
        hoverOK = openMenu == nil and (captured == nil or type(captured) == "table") and inRect(fmx, fmy, cx - 2, cy, cw + 4, ch)
        cclick = clickAvail and hoverOK
        if activeTab then
            for _, el in ipairs(activeTab.elems) do el.placed = false end
            for _, it in ipairs(items) do
                it[1].placed = true
                renderElem(it[1], cx + it[2], cy - scrollY + it[3], it[4], T)
            end
            for _, el in ipairs(activeTab.elems) do
                if not el.placed and not el.culled then hideElem(el); el.culled = true end
            end
        end
        -- drag from anywhere: moving more than 6 px before releasing scrolls instead of clicking
        if cclick then pan.y, pan.s, pan.pending = fmy, scrollY, true end
        if not fdown then pan.pending = false end
        if pan.pending and fdown and maxScroll > 0 and abs(fmy - pan.y) > 6 then
            local c = captured
            if c == nil or (type(c) == "table" and (c.type == "toggle" or c.type == "button")) then
                captured = "pan"
                pan.pending = false
            end
        end
        if cclick then clickAvail = false end
        if captured == "pan" then hoverText = "Drag to scroll" end

        -- status bar
        local right = X + w - 4 - 14
        local clkW, fpsW = 74, 58
        local clkX = right - clkW
        local fpsX = clkX - 2 - fpsW
        local lX = X + 4
        local lW = fpsX - 2 - lX
        paintBevel(panes[1], lX, stY, lW, STATUS_H, "thin", T.Face, true, T)
        paintBevel(panes[2], fpsX, stY, fpsW, STATUS_H, "thin", T.Face, true, T)
        paintBevel(panes[3], clkX, stY, clkW, STATUS_H, "thin", T.Face, true, T)
        fitInto(paneTxt[1], hoverText or statusDefault, lW - 8, fits.status)
        paneTxt[1].Position = V(lX + 4, stY + 2)
        paneTxt[2].Text = fps .. " FPS"
        paneTxt[2].Position = V(fpsX + floor((fpsW - textW(paneTxt[2], 13)) / 2), stY + 2)
        paneTxt[3].Text = clockText
        paneTxt[3].Position = V(clkX + floor((clkW - textW(paneTxt[3], 13)) / 2), stY + 2)
        for i = 1, 3 do paneTxt[i].Color = T.Text; paneTxt[i].Visible = true end
        local gx, gy = X + w - 4, Y + h - 4
        for k = 1, 3 do
            local off = k * 4 - 1
            local a, b = grip[k * 2 - 1], grip[k * 2]
            a.From = V(gx - off - 1, gy); a.To = V(gx, gy - off - 1); a.Color = T.Hi; a.Visible = not maximized
            b.From = V(gx - off, gy); b.To = V(gx, gy - off); b.Color = T.Sh; b.Visible = not maximized
        end
    end

    -- taskbar-style button shown while minimized
    local function ensureMiniPos()
        if not miniX then miniX = 6; miniY = viewport.Y - MINI_H - 6 end
    end
    local function renderMini(T, show)
        if not show then
            if miniShown then hideAll(miniDraws); miniShown = false end
            return
        end
        miniShown = true
        ensureMiniPos()
        local vp = viewport
        if fclick and inRect(fmx, fmy, miniX, miniY, MINI_W, MINI_H) then
            captured = "mini"
            dg.mx, dg.my, dg.sx, dg.sy, dg.moved = fmx - miniX, fmy - miniY, fmx, fmy, false
        end
        if captured == "mini" and fdown then
            if abs(fmx - dg.sx) + abs(fmy - dg.sy) > 4 then dg.moved = true end
            if dg.moved then miniX, miniY = fmx - dg.mx, fmy - dg.my end
        end
        miniX = clamp(miniX, 0, max(0, vp.X - MINI_W))
        miniY = clamp(miniY, 0, max(0, vp.Y - MINI_H))
        local X, Y = floor(miniX), floor(miniY)
        local bx, by, bw, bh = X + 10, Y + 4, MINI_W - 14, MINI_H - 8
        local bhot = inRect(fmx, fmy, bx, by, bw, bh)
        if frelease and captured == "mini" and not dg.moved and bhot then doRestore() end
        paintBevel(mini.b, X, Y, MINI_W, MINI_H, "window", T.Face, true, T)
        rect(mini.g[1], X + 5, Y + 4, 1, MINI_H - 8, T.Hi, true)
        rect(mini.g[2], X + 6, Y + 4, 1, MINI_H - 8, T.Sh, true)
        local push = captured == "mini" and not dg.moved and bhot and fdown
        local o = push and 1 or 0
        paintBevel(mini.btn, bx, by, bw, bh, push and "pressed" or "button", T.Face, true, T)
        rect(mini.icon[1], bx + 5 + o, by + 5 + o, 14, 12, BLACK, true)
        rect(mini.icon[2], bx + 6 + o, by + 6 + o, 12, 10, WHITE, true)
        rect(mini.icon[3], bx + 6 + o, by + 6 + o, 12, 3, ICON_BAR, true)
        fitInto(mini.txt, title, bw - 30, fits.mini)
        mini.txt.Position = V(bx + 24 + o, by + 4 + o); mini.txt.Color = T.Text; mini.txt.Visible = true
    end

    local function frame(now)
        local T = Retro._theme
        hoverText = nil
        if visible and not minimized then
            renderWindow(T)
            winHidden = false
        elseif not winHidden then
            hideAll(draws)
            winHidden = true
        end
        renderMini(T, visible and minimized and anim == nil)
        if anim then
            local p = clamp((now - anim.t0) / 0.22, 0, 1)
            local a, b = anim.a, anim.b
            rect(zoomSq, lerp(a[1], b[1], p), lerp(a[2], b[2], p), lerp(a[3], b[3], p), 18, T.T1, true)
            if p >= 1 then
                if anim.restoring then minimized = false end
                anim = nil
                zoomSq.Visible = false
                markDirty()
            end
        end
        if frelease then captured = nil end
    end

    -- ── window actions ──
    local function titleRect() return floor(winX) + 3, floor(winY) + 3, floor(W) - 6 end
    doMinimize = function()
        if minimized or anim then return end
        closeOverlays(); finishInput(); activeCaptor = nil
        ensureMiniPos()
        local tx, ty, tw = titleRect()
        anim = { t0 = clock(), a = { tx, ty, tw }, b = { miniX + 10, miniY + 4, MINI_W - 14 }, restoring = false }
        minimized = true
        markDirty()
    end
    doRestore = function()
        visible = true
        if not minimized or anim then markDirty(); return end
        ensureMiniPos()
        local tx, ty, tw = titleRect()
        anim = { t0 = clock(), a = { miniX + 10, miniY + 4, MINI_W - 14 }, b = { tx, ty, tw }, restoring = true }
        markDirty()
    end
    toggleMax = function()
        if maximized then
            maximized = false
            if preMax then winX, winY, W, H = preMax[1], preMax[2], preMax[3], preMax[4] end
        else
            preMax = { winX, winY, W, H }
            maximized = true
            winX, winY, W, H = 0, 0, viewport.X, viewport.Y
        end
        markDirty()
    end
    doHide = function()
        visible = false
        closeOverlays(); finishInput(); activeCaptor = nil
        Retro:Notify({ Title = title, Content = "The window is hidden. Press " .. getKeyName(togKey) .. " to show it again.", Type = "info", Duration = 4 })
        markDirty()
    end
    showAbout = function()
        Retro:Notify({ Title = "About " .. title, Type = "info", Duration = 6,
            Content = title .. (author and ("\nby " .. author) or "") .. "\nRetro95 UI v" .. Retro.Version .. "\nTheme: " .. Retro._theme.Name })
    end
    toggleUI = function()
        if clock() - lastToggle < 0.25 then return end
        lastToggle = clock()
        if minimized then
            doRestore()
        else
            visible = not visible
            if not visible then closeOverlays(); finishInput(); activeCaptor = nil end
        end
        markDirty()
    end
    selectTab = function(tab)
        if activeTab == tab then return end
        finishInput()
        if openEl then openEl.open = false; openEl = nil end
        hideTab(activeTab)
        activeTab = tab
        scrollY, focusEl = 0, nil
        markDirty()
    end

    -- ── main loop: only repaints when something changed ──
    do
    local lmx, lmy, lastEpoch, forceAt, prevDown, lastRefresh = -1, -1, -1, 0, false, -10
    conns[#conns + 1] = connectFrame(function()
        if not Retro._alive or not windowAlive then return end
        local ok, err = pcall(function()
            local now = clock()
            frames = frames + 1
            if now - fpsT >= 0.5 then
                fps = floor(frames / (now - fpsT) + 0.5)
                frames, fpsT = 0, now
            end
            if now - lastRefresh > 1 then
                lastRefresh = now
                refreshRuntime()
                if os and type(os.date) == "function" then
                    local okD, s = pcall(os.date, "%I:%M %p")
                    if okD and type(s) == "string" then clockText = s:gsub("^0", "") end
                end
            end
            local mx, my = mousePos()
            local down = isMouseDown()
            fclick = down and not prevDown
            frelease = prevDown and not down
            prevDown = down
            fdown, fmx, fmy, fnow = down, mx, my, now
            pollKeys(now)
            if mx == lmx and my == lmy and not down and not frelease and epoch == lastEpoch and now < forceAt and not anim then return end
            lmx, lmy, lastEpoch = mx, my, epoch
            forceAt = (floor(now * 2) + 1) / 2
            frame(now)
        end)
        if not ok and not errShown then
            errShown = true
            report("render error: " .. tostring(err))
        end
    end)
    end

    do
    local lastWheel = 0
    local function onWheel(z)
        local now = clock()
        if now - lastWheel < 0.01 then return end
        lastWheel = now
        if not visible or minimized then return end
        local mx, my = mousePos()
        if not inRect(mx, my, cRect[1], cRect[2], cRect[3], cRect[4]) then return end
        scrollY = clamp(scrollY - z * 40, 0, maxScroll)
        markDirty()
    end
    if UserInputService then
        pcall(function()
            conns[#conns + 1] = UserInputService.InputChanged:Connect(function(input)
                pcall(function()
                    if input.UserInputType == Enum.UserInputType.MouseWheel then onWheel(input.Position.Z) end
                end)
            end)
        end)
    end
    if mouse then
        pcall(function() conns[#conns + 1] = mouse.WheelForward:Connect(function() onWheel(1) end) end)
        pcall(function() conns[#conns + 1] = mouse.WheelBackward:Connect(function() onWheel(-1) end) end)
    end
    end

    -- event-based keyboard when iskeypressed is unavailable
    if not POLL and UserInputService then
        local function shiftDown()
            local ok, r = pcall(function()
                return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
            end)
            return ok and r == true
        end
        pcall(function()
            conns[#conns + 1] = UserInputService.InputBegan:Connect(function(input)
                pcall(function()
                    local code = normalizeKey(input.KeyCode)
                    if code == 0 and input.UserInputType == Enum.UserInputType.MouseButton2 then code = 2 end
                    if activeCaptor then
                        if code ~= 0 then captureKey(code) end
                        return
                    end
                    if activeInput then
                        if code ~= 0 then typeKey(code, shiftDown()) end
                        return
                    end
                    if code == togKey then toggleUI() elseif code == 0x1B then closeOverlays() end
                    for _, el in ipairs(keybinds) do if el.value == code then applyKeybind(el, true) end end
                end)
            end)
            conns[#conns + 1] = UserInputService.InputEnded:Connect(function(input)
                pcall(function()
                    local code = normalizeKey(input.KeyCode)
                    for _, el in ipairs(keybinds) do if el.value == code then applyKeybind(el, false) end end
                end)
            end)
        end)
    end

    -- ── control API ──
    local function newElem(tab, kind, c)
        local el = { type = kind, d = {}, all = {}, tab = tab, visible = true, title = "" }
        if type(c) == "table" then
            el.desc = c.Description and tostring(c.Description) or nil
            el.flag = c.Flag
            el.callback = type(c.Callback) == "function" and c.Callback or nil
        end
        tab.elems[#tab.elems + 1] = el
        markDirty()
        return el
    end
    local function creator(el)
        return function(kind, props)
            local d = wd(kind, props)
            el.all[#el.all + 1] = d
            return d
        end
    end
    local function dropDraws(el, set)
        local keep = {}
        for _, d in ipairs(el.all) do if set[d] then kill(d) else keep[#keep + 1] = d end end
        el.all = keep
        local keep2 = {}
        for _, d in ipairs(draws) do if not set[d] then keep2[#keep2 + 1] = d end end
        draws = keep2
    end
    local function removeElem(tab, el)
        if el.destroyed then return end
        el.destroyed = true
        if el.flag ~= nil then
            local c = Retro._controls[el.flag]
            if c and c.el == el then Retro._controls[el.flag] = nil; Retro.Flags[el.flag] = nil end
        end
        if activeInput == el then activeInput = nil end
        if activeCaptor == el then activeCaptor = nil end
        if openEl == el then openEl = nil end
        if focusEl == el then focusEl = nil end
        if captured == el then captured = nil end
        local set = {}
        for _, d in ipairs(el.all) do set[d] = true end
        dropDraws(el, set)
        for i, x in ipairs(tab.elems) do if x == el then table.remove(tab.elems, i); break end end
        for i, x in ipairs(keybinds) do if x == el then table.remove(keybinds, i); break end end
        markDirty()
    end
    local function register(tab, el)
        local h = {}
        function h:Set(v, silent)
            if el.destroyed or NO_VALUE[el.type] then return self end
            local nv = normalize(el, v)
            if nv == nil or sameValue(nv, el.value) then return self end
            if el == activeInput then activeInput = nil end
            commit(el, nv, silent)
            return self
        end
        function h:Get() return el.value end
        function h:OnChanged(cb) el.callback = type(cb) == "function" and cb or nil; return self end
        function h:SetTitle(t)
            el.title = tostring(t or "")
            el.wrapW, el.fw = nil, nil
            if el.d.txt and (el.type == "header" or el.type == "paragraph") then el.d.txt.Text = el.title end
            markDirty()
            return self
        end
        function h:SetDescription(t) el.desc = t and tostring(t) or nil; return self end
        function h:SetVisible(v)
            el.visible = v ~= false
            if not el.visible then hideElem(el); el.culled = true end
            markDirty()
            return self
        end
        function h:Destroy() removeElem(tab, el) end
        h.SetValue, h.GetValue, h.SetText = h.Set, h.Get, h.SetTitle
        if el.type == "progressbar" then h.SetProgress, h.GetProgress = h.Set, h.Get end
        if el.type == "button" then function h:Fire() fire(el.callback) end end
        if el.type == "keybind" then
            function h:IsEnabled() return el.enabled == true end
            function h:OnTriggered(cb) el.onTriggered = cb; return self end
        end
        if el.flag ~= nil then
            assert(not Retro._controls[el.flag], "Retro95: duplicate Flag '" .. tostring(el.flag) .. "'")
            Retro._controls[el.flag] = { el = el, handle = h }
            Retro.Flags[el.flag] = el.value
        end
        el.handle = h
        return h
    end
    local function buildOptions(el, list)
        if el.opts then
            local set = {}
            for _, od in ipairs(el.opts) do for _, d in pairs(od) do set[d] = true end end
            dropDraws(el, set)
        end
        el.options, el.opts = {}, {}
        for _, o in ipairs(list) do el.options[#el.options + 1] = tostring(o) end
        local mk = creator(el)
        for i, o in ipairs(el.options) do
            local od = { hl = mk("Square", { Filled = true }) }
            if el.multi then
                od.b1 = mk("Square", { Filled = true })
                od.b2 = mk("Square", { Filled = true })
                od.b3 = mk("Square", { Filled = true })
            end
            od.t = mkText(mk, 13, F_UI, { Text = o })
            el.opts[i] = od
        end
    end
    local function buildTabAPI(tab)
        local API = {}

        function API:Section(name)
            local el = newElem(tab, "header", nil)
            el.title = tostring(name or "")
            local mk = creator(el)
            el.d.txt = mkText(mk, 13, F_SYS, { Text = el.title })
            el.d.e1 = mk("Square", { Filled = true })
            el.d.e2 = mk("Square", { Filled = true })
            return register(tab, el)
        end

        function API:Toggle(c)
            if type(c) == "string" then c = { Title = c } end
            c = c or {}
            local el = newElem(tab, "toggle", c)
            el.title = tostring(c.Title or "Toggle")
            el.value = c.Default == true
            local mk = creator(el)
            el.d.box = mkBevel(mk)
            el.d.chk = mkSquares(mk, 7)
            el.d.lbl = mkText(mk, 13)
            return register(tab, el)
        end

        function API:Slider(c, pMin, pMax, pDef, pCb)
            if type(c) == "string" then c = { Title = c, Min = pMin, Max = pMax, Default = pDef, Callback = pCb } end
            c = c or {}
            local el = newElem(tab, "slider", c)
            el.title = tostring(c.Title or "Slider")
            el.min, el.max = finite(c.Min, 0), finite(c.Max, 100)
            if el.min > el.max then el.min, el.max = el.max, el.min end
            el.step = finite(c.Step, 1)
            if el.step <= 0 then el.step = 1 end
            el.suffix = tostring(c.Suffix or "")
            el.value = el.min
            el.value = normalize(el, finite(c.Default, el.min))
            local mk = creator(el)
            el.d.lbl = mkText(mk, 13)
            el.d.vbox = mkBevel(mk)
            el.d.val = mkText(mk, 13)
            el.d.groove = mkBevel(mk)
            el.d.ticks = mkSquares(mk, 6)
            el.d.thumb = mkBevel(mk)
            return register(tab, el)
        end

        function API:Button(c)
            if type(c) == "string" then c = { Title = c } end
            c = c or {}
            local el = newElem(tab, "button", c)
            el.title = tostring(c.Title or "Button")
            el.danger = c.Style == "danger" or c.Danger == true
            el.primary = c.Style == "primary" or c.Primary == true
            local mk = creator(el)
            el.d.def = mk("Square", { Filled = true })
            el.d.b = mkBevel(mk)
            el.d.lbl = mkText(mk, 13)
            el.d.focus = mk("Square", { Filled = false, Thickness = 1 })
            return register(tab, el)
        end

        function API:Dropdown(c)
            c = c or {}
            local el = newElem(tab, "dropdown", c)
            el.title = tostring(c.Title or "Dropdown")
            el.multi = c.Multi == true
            el.open = false
            local mk = creator(el)
            el.d.lbl = mkText(mk, 13)
            el.d.field = mkBevel(mk)
            el.d.vhl = mk("Square", { Filled = true })
            el.d.val = mkText(mk, 13)
            el.d.btn = mkBevel(mk)
            el.d.arr = mkSquares(mk, 4)
            el.d.lbox = mk("Square", { Filled = true })
            el.d.lin = mk("Square", { Filled = true })
            buildOptions(el, type(c.Options) == "table" and c.Options or { "Option A", "Option B" })
            if el.multi then
                el.value = normalize(el, c.Default or {})
            else
                el.value = normalize(el, c.Default) or el.options[1]
            end
            local h = register(tab, el)
            function h:SetOptions(list)
                if el.destroyed then return self end
                buildOptions(el, type(list) == "table" and list or {})
                local nv = normalize(el, el.value)
                if not el.multi and nv == nil then nv = el.options[1] end
                el.value = nv
                if el.flag ~= nil then Retro.Flags[el.flag] = nv end
                markDirty()
                return self
            end
            h.Refresh = h.SetOptions
            return h
        end

        function API:Keybind(c)
            c = c or {}
            local el = newElem(tab, "keybind", c)
            el.title = tostring(c.Title or "Keybind")
            el.value = normalizeKey(c.Default or 0)
            el.mode = string.lower(tostring(c.Mode or "toggle"))
            if el.mode ~= "hold" and el.mode ~= "always" and el.mode ~= "click" then el.mode = "toggle" end
            el.enabled, el.keyDown = el.mode == "always", false
            el.onTriggered = c.OnTriggered
            local mk = creator(el)
            el.d.lbl = mkText(mk, 13)
            el.d.mode = mkText(mk, 13)
            el.d.field = mkBevel(mk)
            el.d.key = mkText(mk, 13)
            keybinds[#keybinds + 1] = el
            return register(tab, el)
        end

        function API:Colorpicker(c)
            c = c or {}
            local el = newElem(tab, "colorpicker", c)
            el.title = tostring(c.Title or "Color")
            el.value = colorValid(c.Default) and c.Default or rgb(0, 0, 128)
            el.presets = {}
            for _, col in ipairs(type(c.Presets) == "table" and c.Presets or DEFAULT_PALETTE) do
                if colorValid(col) then el.presets[#el.presets + 1] = col end
            end
            if #el.presets == 0 then el.presets[1] = el.value end
            el.open = false
            local mk = creator(el)
            el.d.lbl = mkText(mk, 13)
            el.d.hex = mkText(mk, 13)
            el.d.btn = mkBevel(mk)
            el.d.swo = mk("Square", { Filled = true })
            el.d.sw = mk("Square", { Filled = true })
            el.d.arr = mkSquares(mk, 4)
            el.tiles = {}
            for i = 1, #el.presets do
                el.tiles[i] = { f = mk("Square", { Filled = true }), g = mk("Square", { Filled = true }),
                    b = mk("Square", { Filled = true }), c = mk("Square", { Filled = true }) }
            end
            return register(tab, el)
        end

        function API:Input(c)
            c = c or {}
            local el = newElem(tab, "input", c)
            el.title = tostring(c.Title or "Input")
            el.maxLen = clamp(floor(finite(c.MaxLength, 64)), 1, 256)
            el.value = string.sub(tostring(c.Default or ""), 1, el.maxLen)
            el.text = el.value
            el.placeholder = tostring(c.Placeholder or "")
            local mk = creator(el)
            el.d.lbl = mkText(mk, 13)
            el.d.field = mkBevel(mk)
            el.d.txt = mkText(mk, 13)
            el.d.caret = mk("Square", { Filled = true })
            return register(tab, el)
        end

        function API:Progressbar(c)
            c = c or {}
            local el = newElem(tab, "progressbar", c)
            el.title = tostring(c.Title or "Progress")
            el.value = clamp(finite(c.Default, 0), 0, 1)
            local mk = creator(el)
            el.d.lbl = mkText(mk, 13)
            el.d.pct = mkText(mk, 13)
            el.d.box = mkBevel(mk)
            el.d.ch = mkSquares(mk, CHUNKS)
            return register(tab, el)
        end

        function API:Paragraph(c)
            if type(c) == "string" then c = { Text = c } end
            c = c or {}
            local el = newElem(tab, "paragraph", c)
            el.title = tostring(c.Text or c.Title or "")
            el.height = 18
            el.d.txt = mkText(creator(el), 13, F_UI, { Text = el.title })
            return register(tab, el)
        end

        function API:Divider()
            local el = newElem(tab, "divider", nil)
            local mk = creator(el)
            el.d.e1 = mk("Square", { Filled = true })
            el.d.e2 = mk("Square", { Filled = true })
            return register(tab, el)
        end

        function API:Space(px)
            local el = newElem(tab, "space", nil)
            el.height = clamp(floor(finite(px, 8)), 0, 200)
            return register(tab, el)
        end

        function API:SetColumns(n)
            tab.columns = clamp(floor(finite(n, 1)), 1, 4)
            markDirty()
            return self
        end
        function API:Select() selectTab(tab) end

        API.AddToggle, API.AddSlider, API.AddButton = API.Toggle, API.Slider, API.Button
        API.AddDropdown, API.AddKeybind, API.AddColorPicker = API.Dropdown, API.Keybind, API.Colorpicker
        API.AddInput, API.AddProgressBar = API.Input, API.Progressbar
        API.AddLabel, API.AddDivider, API.AddSection = API.Paragraph, API.Divider, API.Section
        return API
    end

    -- ── window API ──
    local Window = {}

    function Window:Section(scfg)
        if type(scfg) == "string" then scfg = { Title = scfg } end
        scfg = scfg or {}
        local s = { title = tostring(scfg.Title or "Section"), tabs = {}, collapsed = scfg.Collapsed == true, fit = {}, d = {} }
        local d = s.d
        d.vl = sq(); d.bo = sq(); d.bi = sq(); d.mi = sq(); d.pl = sq()
        d.f1 = sq(); d.f2 = sq(); d.f3 = sq()
        d.txt = mkText(wd, 13)
        sections[#sections + 1] = s
        markDirty()
        local S = { title = s.title }
        function S:Tab(tcfg)
            if type(tcfg) == "string" then tcfg = { Title = tcfg } end
            tcfg = tcfg or {}
            local tab = { title = tostring(tcfg.Title or "Tab"), section = s, elems = {}, fit = {}, d = {},
                columns = clamp(floor(finite(tcfg.Columns, 1)), 1, 4) }
            local td = tab.d
            td.hl = sq(); td.stub = sq()
            td.p1 = sq(); td.p2 = sq(); td.p3 = sq(); td.p4 = sq(); td.p5 = sq()
            td.txt = mkText(wd, 13)
            s.tabs[#s.tabs + 1] = tab
            tabs[#tabs + 1] = tab
            if not activeTab then activeTab = tab end
            markDirty()
            return buildTabAPI(tab)
        end
        function S:SetCollapsed(v) s.collapsed = v == true; markDirty(); return self end
        return S
    end
    local defaultSection
    function Window:AddTab(options)
        if not defaultSection then defaultSection = self:Section("Pages") end
        return defaultSection:Tab(options)
    end
    function Window:AddMenu(name, items)
        if not hasMenu then return self end
        local def = { title = tostring(name or "Menu"), build = function()
            local list = {}
            for _, it in ipairs(items or {}) do
                if it == "-" or (type(it) == "table" and it.Separator) then
                    list[#list + 1] = { sep = true }
                elseif type(it) == "table" then
                    list[#list + 1] = { text = tostring(it.Title or "Item"), sc = it.Shortcut and tostring(it.Shortcut) or nil,
                        act = function() fire(it.Callback) end }
                end
            end
            return list
        end }
        addMenuDraws(def)
        table.insert(menuDefs, #menuDefs, def)
        markDirty()
        return self
    end
    function Window:SetTitle(t)
        title = tostring(t or "")
        titleTxt.Text = title; mini.txt.Text = title
        fits.title.fw, fits.mini.fw = nil, nil
        markDirty()
        return self
    end
    function Window:SetStatus(t) statusDefault = tostring(t or "Ready"); markDirty(); return self end
    function Window:Minimize() doMinimize() end
    function Window:Restore() doRestore() end
    function Window:Toggle() toggleUI() end
    function Window:ToggleExpand() toggleMax() end
    function Window:Maximize() if not maximized then toggleMax() end end
    function Window:SetToggleKey(vk) togKey = normalizeKey(vk) end
    function Window:SetSize(nw, nh)
        if maximized then toggleMax() end
        normW = clamp(finite(nw, normW), MIN_W, MAX_W)
        normH = clamp(finite(nh, normH), MIN_H, MAX_H)
        W, H = normW, normH
        markDirty()
    end
    function Window:IsPointerOver(mx, my)
        if not windowAlive or not visible then return false end
        if minimized then return miniX ~= nil and inRect(mx, my, miniX, miniY, MINI_W, MINI_H) end
        return inRect(mx, my, winX, winY, W, H)
    end
    function Window:SetIcon() return self end
    function Window:SetVisualFX() return self end
    function Window:GetVisualFX() return false end
    function Window:SetLayout() return self end
    function Window:IsAlive() return windowAlive and Retro._alive end

    function Window:Watermark(c)
        c = c or {}
        local wmLabel = tostring(c.Title or title)
        local list = {}
        local function mk(kind, props)
            props = props or {}
            props.Visible = false
            if HAS_Z then props.ZIndex = 8 end
            local d = newDraw(kind, props)
            list[#list + 1] = d
            return d
        end
        local b, p, ic, t = mkBevel(mk), mkBevel(mk), mkSquares(mk, 3), mkText(mk, 13)
        local shown, nextAt = true, 0
        local conn = connectFrame(function()
            if not Retro._alive or not windowAlive then return end
            local now = clock()
            if now < nextAt then return end
            nextAt = now + 0.5
            pcall(function()
                if not shown then hideAll(list); return end
                local T = Retro._theme
                t.Text = wmLabel .. "  |  " .. fps .. " fps  |  " .. clockText
                local ww = floor(textW(t, 13)) + 40
                local x, y = 10, 10
                paintBevel(b, x, y, ww, 26, "window", T.Face, true, T)
                paintBevel(p, x + 3, y + 3, ww - 6, 20, "thin", T.Face, true, T)
                rect(ic[1], x + 7, y + 7, 14, 12, BLACK, true)
                rect(ic[2], x + 8, y + 8, 12, 10, WHITE, true)
                rect(ic[3], x + 8, y + 8, 12, 3, ICON_BAR, true)
                t.Position = V(x + 27, y + 6); t.Color = T.Text; t.Visible = true
            end)
        end)
        local wm = {}
        wm.destroy = function()
            pcall(function() conn:Disconnect() end)
            for _, d in ipairs(list) do kill(d) end
        end
        watermarks[#watermarks + 1] = wm
        local hd = {}
        function hd:SetVisible(v) shown = v ~= false; nextAt = 0 end
        function hd:SetTitle(s) wmLabel = tostring(s or ""); nextAt = 0 end
        function hd:Destroy() wm.destroy() end
        return hd
    end

    function Window:Destroy()
        if not windowAlive then return end
        windowAlive = false
        for _, tab in ipairs(tabs) do
            for _, el in ipairs(tab.elems) do
                el.destroyed = true
                if el.flag ~= nil then
                    local c = Retro._controls[el.flag]
                    if c and c.el == el then Retro._controls[el.flag] = nil; Retro.Flags[el.flag] = nil end
                end
            end
        end
        for _, cn in ipairs(conns) do pcall(function() cn:Disconnect() end) end
        for _, wm in ipairs(watermarks) do wm.destroy() end
        for _, d in ipairs(draws) do kill(d) end
        for _, d in ipairs(miniDraws) do kill(d) end
        for _, d in ipairs(extras) do kill(d) end
        for i = #Retro._windows, 1, -1 do if Retro._windows[i] == Window then table.remove(Retro._windows, i) end end
    end

    Retro._windows[#Retro._windows + 1] = Window
    markDirty()
    return Window
end

function Retro:AddTab(options)
    if not self._defaultWindow or not self._defaultWindow:IsAlive() then
        self._defaultWindow = self:CreateWindow({ Title = "Retro95" })
    end
    return self._defaultWindow:AddTab(options)
end
function Retro:Destroy()
    for i = #self._windows, 1, -1 do pcall(function() self._windows[i]:Destroy() end) end
    for _, n in ipairs(notifs) do killNotif(n) end
    notifs = {}
    if notifConn then pcall(function() notifConn:Disconnect() end); notifConn = nil end
    self._windows, self._controls, self._watchers = {}, {}, {}
    self._alive = false
    runtimeAlive = false
end
function Retro:Unload() self:Destroy() end

_G.__Retro95Cleanup = function() Retro:Destroy() end
_G.Retro95 = Retro
if typeOf(getgenv) == "function" then pcall(function() getgenv().Retro95 = Retro end) end

return Retro
