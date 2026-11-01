--[[
* timers - Copyright (c) 2022 The Mystic
*
* This file is part of Timers for Ashita.
*
* Timers is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* Timers is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with Timers.  If not, see <https://www.gnu.org/licenses/>.
--]]

--[[
    YunaUI theme: draws a timer panel with ImGui in the look of YunaUI's own Timers (white names
    with a thin dark edge, the time left in the bar's colour, a thin glowing bar that drains, and
    the TeX Gyre Adventor font).  Based on YunaUI by Yunas - https://github.com/YunasXI/yunaui

    The panels still keep their Ashita primitives for the Default theme; while a panel uses this
    theme they are hidden and this module draws it instead (see TimerGroup:render).

    Each panel keeps a second set of the look settings for this theme (group.settings.yuna): the
    same names as the Default theme's (Bars, Text and Icons pages) with YunaUI's values, plus a
    few of its own.  The layout (bar length, padding, max height, background, border, menu lines)
    is the panel's own and shared by both themes.
]]

require('common')
local imgui   = require('imgui')
local ffi     = require('ffi')
local d3d     = require('d3d8')
local helpers = require('helpers')

local yuna = {}

-- Colours: ARGB (as the Default theme's), except kinds: { r, g, b } from 0 to 1.
yuna.DEFAULTS = T{
    -- the Default theme's look settings, with YunaUI's values
    bar_height         = 2,
    bar_length         = 100,          -- % of the row's width
    bar_offset_x       = 0,
    bar_offset_y       = 0,
    bar_border_visible = false,
    bar_border_color   = 0xEB000000,
    thresholds         = T{ t75 = 30, t50 = 20, t25 = 10 },
    colors             = T{ color100 = 0xFF00FF00, color75 = 0xFFFFFF33, color50 = 0xFFFFA64D, color25 = 0xFFFF0000 },
    font_family        = 'texgyreadventor-regular.otf',
    font_height        = 12,           -- px
    font_bg_visible    = false,
    font_bg_color      = 0x80000000,
    name_font_color    = 0xFFFFFFFF,
    name_outline_color = 0xE6000000,
    time_font_color    = 0xFFFFFFFF,
    time_outline_color = 0xE6000000,
    name_font_offset_x = -2,
    name_font_offset_y = 0,
    timer_font_offset_x = 0,
    timer_font_offset_y = 0,
    name_align         = 'left',       -- where the name sits in its row: 'left', 'center' or 'right'
    time_align         = 'right',      -- the countdown, the same
    enable_icons       = false,
    icon_scale         = 1.0,          -- of the row's height
    icon_offset_x      = 0,
    icon_offset_y      = 0,

    -- YunaUI's own
    frame              = false,        -- the style's panel frame (YunaVEXWB, YunaVEXP, YunaHEX)
    bar_end            = T{ 0.62, 0.40, 1.00 },   -- the bars' far colour, for styles whose bars fade to one colour
    time_bar_color     = true,         -- the countdown in the bar's colour (else time_font_color)
    row_gap            = 2,            -- px between one row's bar and the next row's name
    color_mode         = 'type',       -- 'type': by kind of timer (kinds), 'time': by time left (thresholds / colors)
    effects            = true,         -- the bar's flowing colours, sheen and breathing glow
    dot_blink          = true,         -- the dot at a thin bar's end blinks with the countdown near the end
    kinds              = T{            -- sp/ja/ma are YunaUI's own (one-hours, abilities, spells)
        sp     = T{ 1.00, 0.45, 0.75 },
        ja     = T{ 1.00, 0.85, 0.45 },
        ma     = T{ 0.55, 0.80, 1.00 },
        buff   = T{ 0.40, 0.90, 0.72 },
        debuff = T{ 0.80, 0.55, 1.00 },
    },
}

--[[
    The styles: YunaUI's looks, each its own theme with its own settings (group.settings[key]).
      bar:   'glow'  YunaUI's thin glowing bar
             'plate' a solid bar, lit at the top, in a dark outline (Vex's white HP / blue MP bars)
             'thin'  the Damage Meter's thin line with a white dot at its end
      fade:  'shade' the bar fades to a darker shade of its colour; 'end' it fades to bar_end
      frame: the panel frame drawn when the Frame setting is on: 'plate', 'vex' or 'hex'
    over: the settings that differ from DEFAULTS (YunaUI's).  Colours from YunaUI's own tables:
    HP pink / white, MP blue, Hex link's gold and azure.
]]
local GOLD, GOLD2, AZURE = T{ 1.00, 0.84, 0.42 }, T{ 1.00, 0.90, 0.62 }, T{ 0.35, 0.80, 1.00 }
yuna.STYLES = {
    { id = 'yunaui', label = 'YunaUI', key = 'yuna', bar = 'glow', fade = 'shade', frame = nil, over = {} },
    { id = 'yuna_vexwb', label = 'YunaVEXWB', key = 'yuna_vexwb', bar = 'plate', fade = 'shade', frame = 'plate', over = {
        bar_height = 6, row_gap = 4, frame = true, effects = false, time_bar_color = false,
        bar_border_visible = true, bar_border_color = 0xEB000000,
        kinds = T{ sp = T{ 1.00, 0.36, 0.62 }, ja = T{ 1.00, 1.00, 1.00 }, ma = T{ 0.40, 0.55, 1.00 },
                   buff = T{ 1.00, 1.00, 1.00 }, debuff = T{ 0.40, 0.55, 1.00 } },
    } },
    { id = 'yuna_vexp', label = 'YunaVEXP', key = 'yuna_vexp', bar = 'thin', fade = 'end', frame = 'vex', over = {
        bar_height = 3, row_gap = 6, frame = true, time_bar_color = false,
        bar_end = T{ 0.62, 0.40, 1.00 },
        kinds = T{ sp = T{ 1.00, 0.36, 0.62 }, ja = T{ 1.00, 0.42, 0.72 }, ma = T{ 0.40, 0.55, 1.00 },
                   buff = T{ 1.00, 0.42, 0.72 }, debuff = T{ 0.86, 0.24, 0.86 } },
    } },
    { id = 'yuna_hex', label = 'YunaHEX', key = 'yuna_hex', bar = 'thin', fade = 'shade', frame = 'hex', over = {
        bar_height = 3, row_gap = 6, frame = true, time_bar_color = false,
        name_font_color = 0xFFFFF7DB, time_font_color = 0xFFFFC257,     -- (Hex link's cream and gold)
        kinds = T{ sp = GOLD2, ja = GOLD, ma = AZURE, buff = AZURE, debuff = GOLD },
    } },
    -- The game's own classic look: a blue FFXI menu window with its light bevelled edge,
    -- square bevelled gauges, plain white text with a black outline
    { id = 'classic', label = 'Classic', key = 'classic', bar = 'classic', fade = 'shade', frame = 'ffxi', over = {
        font_family = 'arial.ttf', font_height = 12, bar_height = 2, row_gap = 0, frame = true,
        effects = true, time_bar_color = true, color_mode = 'time', name_font_offset_x = 0,
        name_outline_color = 0xFF000000, time_outline_color = 0xFF000000,
        bar_border_visible = true, bar_border_color = 0xFF000000,
        enable_icons = true, icon_offset_x = 1, icon_offset_y = 2,
        kinds = T{ sp = T{ 1.00, 0.50, 0.40 }, ja = T{ 0.98, 0.84, 0.45 }, ma = T{ 0.55, 0.78, 1.00 },
                   buff = T{ 0.98, 0.84, 0.45 }, debuff = T{ 0.98, 0.84, 0.45 } },
    } },
}
yuna.STYLE = {}
for _, st in ipairs(yuna.STYLES) do yuna.STYLE[st.id] = st end

-- The kinds of timer each panel shows (for its colour settings)
yuna.KIND_LABELS = {
    recasts   = { { 'sp', 'One-hours' }, { 'ja', 'Abilities' }, { 'ma', 'Spells' } },
    durations = { { 'buff', 'Durations' } },
    debuffs   = { { 'debuff', 'Debuffs' } },
}

-- The kind a panel's timers are when the bar doesn't say (recast bars say ja / ma / sp)
local PANEL_KIND = { recasts = 'ja', durations = 'buff', debuffs = 'debuff' }
yuna.PANEL_KIND = PANEL_KIND

local function copy(v) return (type(v) == 'table') and table.table_copy(v) or v end

-- Is this theme one of these styles (drawn by this module)?
function yuna.is_theme(theme) return yuna.STYLE[theme] ~= nil end

-- A style's defaults: DEFAULTS with the style's own values (made once)
local style_defaults = {}
function yuna.defaults_for(theme)
    local st = yuna.STYLE[theme] or yuna.STYLE.yunaui
    if style_defaults[st.id] == nil then
        local d = table.table_copy(yuna.DEFAULTS)
        for k, v in pairs(st.over) do d[k] = copy(v) end
        style_defaults[st.id] = d
    end
    return style_defaults[st.id]
end

-- The look a character's settings file kept for a style before themes (themes.lua) held the
-- looks, with anything missing filled in: read once, to carry those settings into a theme.
-- Returns the settings and the style.
-- (settings:merge can hand a panel the defaults' own tables: those are copied, so editing one
-- panel never changes the defaults or another panel)
function yuna.settings(group, theme)
    local st = yuna.STYLE[theme or group.settings.theme] or yuna.STYLE.yunaui
    local D = yuna.defaults_for(st.id)
    local s = group.settings[st.key]
    if type(s) ~= 'table' or s == D or s == yuna.DEFAULTS then
        s = T{}
        group.settings[st.key] = s
    end

    -- settings from the first YunaUI theme (1.1.0)
    if s.font_size ~= nil then s.font_height, s.font_size = s.font_size, nil end
    if type(s.colors) == 'table' and type(s.colors.sp) == 'table' then s.kinds, s.colors = s.colors, nil end
    if type(s.text_color) == 'table' then
        s.name_font_color = helpers.color_v4_to_u32({ s.text_color[1], s.text_color[2], s.text_color[3], 1 })
        s.text_color = nil
    end

    for k, v in pairs(D) do
        if s[k] == nil or (type(v) == 'table' and s[k] == v) then s[k] = copy(v) end
    end
    -- (that upgrade could leave the threshold colours among the type colours: only tables belong there)
    for k, v in pairs(s.kinds) do
        if type(v) ~= 'table' then s.kinds[k] = nil end
    end
    for _, sub in ipairs({ 'kinds', 'thresholds', 'colors' }) do
        for k, v in pairs(D[sub]) do
            if s[sub][k] == nil or (type(v) == 'table' and s[sub][k] == v) then s[sub][k] = copy(v) end
        end
    end
    if type(s.bar_end) ~= 'table' or s.bar_end == D.bar_end then s.bar_end = copy(D.bar_end) end
    return s, st
end

--------------------------------------------------------------------------------
-- Drawing helpers (scratch tables, so no Lua table is made per draw call)
--------------------------------------------------------------------------------
local function xy(a, b)
    if type(a) == 'table' then return a[1] or a.x or 0, a[2] or a.y or 0 end
    return a or 0, b or 0
end

local c4, P1, P2 = { 0, 0, 0, 0 }, { 0, 0 }, { 0, 0 }
local function U4(r, g, b, a) c4[1], c4[2], c4[3], c4[4] = r, g, b, a; return imgui.GetColorU32(c4) end
local function UA(argb, alpha)                                  -- an ARGB colour, its alpha times alpha
    local v = helpers.color_u32_to_v4(argb)
    return U4(v[1], v[2], v[3], v[4] * (alpha or 1))
end
local function RF(dl, x1, y1, x2, y2, col, r)
    P1[1], P1[2], P2[1], P2[2] = x1, y1, x2, y2
    dl:AddRectFilled(P1, P2, col, r or 0)
end
local function RR(dl, x1, y1, x2, y2, col, r, th)
    P1[1], P1[2], P2[1], P2[2] = x1, y1, x2, y2
    dl:AddRect(P1, P2, col, r or 0, 0, th or 1)
end
local function RFM(dl, x1, y1, x2, y2, a, b, c, d)
    P1[1], P1[2], P2[1], P2[2] = x1, y1, x2, y2
    dl:AddRectFilledMultiColor(P1, P2, a, b, c, d)
end
local function TX(dl, x, y, col, s)
    P1[1], P1[2] = x, y
    dl:AddText(P1, col, s)
end

-- Text with a thin dark edge (readable on any ground), as YunaUI's
local OUTLINE = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 }, { 1, 2 } }
local function outlined(dl, x, y, s, col, edge)
    for _, o in ipairs(OUTLINE) do TX(dl, x + o[1], y + o[2], edge, s) end
    TX(dl, x, y, col, s)
end

local function text_w(s) return (xy(imgui.CalcTextSize(s))) end

local function fit(s, max_w)
    if max_w <= 0 then return '' end
    if text_w(s) <= max_w then return s end
    local lo, hi = 0, #s
    while lo < hi do
        local m = math.ceil((lo + hi) / 2)
        if text_w(s:sub(1, m) .. '...') <= max_w then lo = m else hi = m - 1 end
    end
    return s:sub(1, lo) .. '...'
end

-- YunaUI's clock: 1:02:03, 4:05, 37s.  Overdue timers count past zero: -3s
local function clock(frames)
    if frames < 0 then return ('-%ds'):format(math.ceil(-frames / 60)) end
    local s = math.max(0, math.ceil(frames / 60))
    local h, m = math.floor(s / 3600), math.floor(s / 60) % 60
    if h > 0 then return ('%d:%02d:%02d'):format(h, m, s % 60) end
    if m > 0 then return ('%d:%02d'):format(m, s % 60) end
    return ('%ds'):format(s)
end

--------------------------------------------------------------------------------
-- The bar: a glowing coloured edge, the colours flowing along inside it and a sheen that
-- sweeps along now and then (YunaUI's glow_bar, without the damage lag)
--------------------------------------------------------------------------------
local function frac(v) return v - math.floor(v) end

local function glow_bar(dl, x, y, w, h, v, c1, c2, seed, fx)
    v = math.max(0, math.min(1, v or 0))
    local now = os.clock()
    RF(dl, x, y, x + w, y + h, U4(0.05, 0.04, 0.07, 0.70), h / 2)
    if v <= 0 then return end
    local fw = w * v

    local pulse = fx and (0.5 + 0.5 * math.sin(now * 2.2 + seed)) or 0.5
    for k = 1, 4 do                                         -- the coloured glow around it, breathing
        RF(dl, x - k, y - k, x + fw + k, y + h + k, U4(c2[1], c2[2], c2[3], (0.11 - k * 0.022) * (0.75 + 0.5 * pulse)), h / 2 + k)
    end
    RF(dl, x - 1, y - 1, x + fw + 1, y + h + 1, U4(c2[1], c2[2], c2[3], 0.85), h / 2 + 1)   -- the edge

    -- the fill: the two colours flow along the bar in slow waves, lighter towards its end
    local ph = fx and (now * 0.35 + seed * 0.21) or 0.3
    local r_ = math.min(h / 2, fw / 2)
    local L_ = (v < 0.985) and math.min(fw, math.max(8, h * 2.6)) or 0
    local lt = { c2[1] + (1 - c2[1]) * 0.85, c2[2] + (1 - c2[2]) * 0.85, c2[3] + (1 - c2[3]) * 0.85 }
    local function colx(px)
        local f = (px - x) / w
        local u = 0.5 + 0.5 * math.sin((f * 1.6 - ph) * math.pi * 2)
        local cr, cg, cb = c1[1] + (c2[1] - c1[1]) * u, c1[2] + (c2[2] - c1[2]) * u, c1[3] + (c2[3] - c1[3]) * u
        local t = (L_ > 0) and 0.45 * math.max(0, math.min(1, (px - (x + fw - L_)) / math.max(1, L_ - r_))) or 0
        return U4(cr + (lt[1] - cr) * t, cg + (lt[2] - cg) * t, cb + (lt[3] - cb) * t, 1)
    end
    RF(dl, x, y, x + math.min(fw, h), y + h, colx(x), r_)
    RF(dl, x + fw - math.min(fw, h), y, x + fw, y + h, colx(x + fw), r_)
    local segs = math.max(4, math.floor(w / 40))
    local cuts = {}
    for k = 0, segs do cuts[#cuts + 1] = x + w * k / segs end
    if L_ > 0 then cuts[#cuts + 1] = x + fw - L_ end
    table.sort(cuts)
    for k = 1, #cuts - 1 do
        local x1, x2 = math.max(x + r_, cuts[k]), math.min(x + fw - r_, cuts[k + 1])
        if x2 > x1 then
            local a, b = colx(x1), colx(x2)
            RFM(dl, x1, y, x2, y + h, a, b, b, a)
        end
    end

    if not fx then return end
    -- the sheen: a soft band of light that runs along the bar every few seconds
    local sp = frac(now * 0.32 + seed * 0.137)
    local hx, hw = x - 40 + sp * (fw + 80), 40
    local function band(x1, x2, a1, a2)
        local cx1, cx2 = math.max(x + r_, x1), math.min(x + fw - r_, x2)
        if cx2 <= cx1 then return end
        local f1, f2 = (cx1 - x1) / (x2 - x1), (cx2 - x1) / (x2 - x1)
        local b1, b2 = a1 + (a2 - a1) * f1, a1 + (a2 - a1) * f2
        RFM(dl, cx1, y, cx2, y + h, U4(1, 1, 1, b1), U4(1, 1, 1, b2), U4(1, 1, 1, b2), U4(1, 1, 1, b1))
    end
    band(hx - hw, hx, 0, 0.55)
    band(hx, hx + hw, 0.55, 0)
end

local function CF(dl, x, y, r, col)
    P1[1], P1[2] = x, y
    dl:AddCircleFilled(P1, r, col, 12)
end

-- The Damage Meter's bar (YunaVEXP, YunaHEX): a thin line fading from c1 to c2 in a soft halo,
-- with a white dot at its end (it breathes when effects are on)
local function thin_bar(dl, x, y, w, h, v, c1, c2, fx, dot_a)
    v = math.max(0, math.min(1, v or 0))
    RF(dl, x, y, x + w, y + h, U4(0.05, 0.04, 0.07, 0.70), h / 2)
    if v <= 0 then return end
    local fw = math.max(h, w * v)
    RF(dl, x, y - 2, x + fw, y + h + 2, U4(c2[1], c2[2], c2[3], 0.18), h)
    local a, b = U4(c1[1], c1[2], c1[3], 1), U4(c2[1], c2[2], c2[3], 1)
    if not pcall(RFM, dl, x, y, x + fw, y + h, a, b, b, a) then RF(dl, x, y, x + fw, y + h, b, h / 2) end
    local pulse = fx and (0.75 + 0.25 * math.sin(os.clock() * 3)) or 1
    CF(dl, x + fw, y + h / 2, math.max(4.5, h * 1.5), U4(c1[1], c1[2], c1[3], 0.30 * pulse))
    CF(dl, x + fw, y + h / 2, math.max(2.2, h * 0.75), U4(1, 1, 1, dot_a or 1))
end

-- Vex's HP / MP bar (YunaVEXWB): a solid bar, lighter at the top, with a fine light line along it.
-- classic: the game's gauge instead: square, in a dark inset track with a light line under it.
local function plate_bar(dl, x, y, w, h, v, c1, c2, fx, classic)
    v = math.max(0, math.min(1, v or 0))
    local rr = classic and 0 or 2
    RF(dl, x, y, x + w, y + h, classic and U4(0.02, 0.02, 0.06, 0.90) or U4(0.10, 0.11, 0.14, 0.85), rr)
    if classic then RF(dl, x, y + h, x + w, y + h + 1, U4(0.70, 0.72, 0.85, 0.45)) end
    if v <= 0 then return end
    local fw = w * v
    if fx then                                              -- a soft glow round the fill
        for k = 1, 2 do RF(dl, x - k, y - k, x + fw + k, y + h + k, U4(c1[1], c1[2], c1[3], 0.10 / k), rr + k) end
    end
    local top, bot = U4(c1[1], c1[2], c1[3], 1), U4(c2[1], c2[2], c2[3], 1)
    if not pcall(RFM, dl, x, y, x + fw, y + h, top, top, bot, bot) then RF(dl, x, y, x + fw, y + h, top, rr) end
    if h >= 4 then RF(dl, x, y, x + fw, y + 1, U4(1, 1, 1, classic and 0.50 or 0.35)) end
end

-- The panel frames (drawn just outside the panel's area)
local function TF(dl, ax, ay, bx, by, cx, cy, col)
    local P3 = { cx, cy }
    P1[1], P1[2], P2[1], P2[2] = ax, ay, bx, by
    dl:AddTriangleFilled(P1, P2, P3, col)
end
local function LN(dl, ax, ay, bx, by, col, th)
    P1[1], P1[2], P2[1], P2[2] = ax, ay, bx, by
    dl:AddLine(P1, P2, col, th or 1)
end

local menu_lines   -- (below, with the layout)

-- The game's menu blues (the Menu Style defaults)
local FFXI_MENU = { thickness = 2, opacity = 100, light_top = 0xFF1B1A41, light_bottom = 0xFF252459,
                    dark_top = 0xFF120D35, dark_bottom = 0xFF191249 }

local function draw_frame(dl, kind, l, t, r, b)
    if kind == 'ffxi' then                                  -- the game's menu window: blue lines, a light bevelled edge
        RF(dl, l, t, r, b, U4(0.07, 0.06, 0.20, 0.88), 5)
        menu_lines(dl, FFXI_MENU, l + 2, t + 2, (r - l) - 4, (b - t) - 4)
        RR(dl, l, t, r, b, U4(0.72, 0.74, 0.82, 0.95), 5, 2)
        RR(dl, l + 2, t + 2, r - 2, b - 2, U4(0.02, 0.02, 0.08, 0.80), 4, 1)
    elseif kind == 'plate' then                                -- Vex's bar plate: dark, a fine light edge
        RF(dl, l, t, r, b, U4(0.05, 0.05, 0.07, 0.82), 4)
        RR(dl, l, t, r, b, U4(0.86, 0.88, 0.94, 0.55), 4, 1.2)
    elseif kind == 'vex' then                               -- the Damage Meter's window: dark glass, a faint violet edge
        RF(dl, l, t, r, b, U4(0.07, 0.06, 0.09, 0.80), 8)
        RR(dl, l, t, r, b, U4(0.74, 0.66, 0.95, 0.30), 8, 1)
    elseif kind == 'hex' then                               -- Hex link: square, cut corners, a gold edge
        local c = 8
        local pts = { { l + c, t }, { r, t }, { r, b - c }, { r - c, b }, { l, b }, { l, t + c } }
        local mx, my = (l + r) / 2, (t + b) / 2
        local fill, edge = U4(0.05, 0.045, 0.04, 0.82), U4(1.00, 0.76, 0.34, 0.85)
        for i = 1, #pts do
            local p, q = pts[i], pts[i % #pts + 1]
            TF(dl, p[1], p[2], q[1], q[2], mx, my, fill)
        end
        for i = 1, #pts do
            local p, q = pts[i], pts[i % #pts + 1]
            LN(dl, p[1], p[2], q[1], q[2], edge, 1.2)
        end
        LN(dl, l + c + 4, t + 3, l + c + 34, t + 3, U4(1.00, 0.90, 0.62, 0.55), 1)   -- (a short lit line along the top)
    end
end

--------------------------------------------------------------------------------
-- Fonts, by the Text page's font family: a font file in this addon's fonts folder or in
-- Windows\Fonts (with or without .ttf / .otf), else TeX Gyre Adventor, Century Gothic, Segoe UI.
-- Fonts can only be added while running under VanaCore (ImGui 1.92), and one added this frame
-- is used from the next.  Elsewhere ImGui's own font stays.
--------------------------------------------------------------------------------
local LOAD_PX = 16
local fonts = {}   -- [family] = { font, new, frame } or false

local function frame_no()
    local ok, n = pcall(imgui.GetFrameCount)
    return (ok and n) or math.floor(os.clock() * 60)
end

local function find_font_file(family)
    local win = (os.getenv('WINDIR') or 'C:\\Windows') .. '\\Fonts\\'
    local names = { family }
    if not family:lower():find('%.[ot]tf$') then names = { family .. '.ttf', family .. '.otf', family } end
    for _, dir in ipairs({ addon.path .. '/fonts/', win }) do
        for _, n in ipairs(names) do
            local fh = io.open(dir .. n, 'rb')
            if fh then fh:close(); return dir .. n end
        end
    end
    return nil
end

local function load_font(family)
    fonts[family] = false
    if not rawget(_G, 'vana') then return end
    local win = (os.getenv('WINDIR') or 'C:\\Windows') .. '\\Fonts\\'
    local paths = { find_font_file(family), addon.path .. '/fonts/texgyreadventor-regular.otf', win .. 'GOTHIC.TTF', win .. 'segoeui.ttf' }
    for i = 1, 4 do
        local path = paths[i]
        local fh = path and io.open(path, 'rb')
        if fh then
            fh:close()
            local ok, f = pcall(imgui.AddFontFromFileTTF, path, LOAD_PX)
            if ok and f then
                local ok2, ls = pcall(function() return f.LegacySize end)   -- (ImGui 1.92 fonts draw at any size)
                fonts[family] = { font = f, new = ok2 and ls ~= nil, frame = frame_no() }
                return
            end
        end
    end
end

-- Push the family's font at px; returns whether a font was pushed (for pop_font)
local function push_font(family, px)
    family = (family and family ~= '') and family or yuna.DEFAULTS.font_family
    if fonts[family] == nil then pcall(load_font, family) end
    local e = fonts[family]
    if e and frame_no() > e.frame then
        if e.new and pcall(imgui.PushFont, e.font, px) then return true end
        if pcall(imgui.PushFont, e.font) then
            imgui.SetWindowFontScale(px / LOAD_PX)
            return true
        end
    end
    imgui.SetWindowFontScale(px / 13)                   -- (ImGui's own font is 13 px)
    return false
end

local function pop_font(pushed)
    imgui.SetWindowFontScale(1)
    if pushed then imgui.PopFont() end
end

--------------------------------------------------------------------------------
-- Status icons as ImGui textures, loaded on first use
--------------------------------------------------------------------------------
local icons = {}   -- [id] = { tex, ptr } or false

local function status_icon(id)
    if id == nil or id < 0 then return nil end
    local ic = icons[id]
    if ic ~= nil then return ic or nil end
    icons[id] = false
    pcall(function()
        local data = AshitaCore:GetResourceManager():GetStatusIconById(id)
        if data == nil or data.Bitmap == nil then return end
        local size = data.ImageSize or #data.Bitmap
        local ptr = ffi.new('IDirect3DTexture8*[1]')
        if ffi.C.D3DXCreateTextureFromFileInMemoryEx(d3d.get_device(), data.Bitmap, size, 0xFFFFFFFF, 0xFFFFFFFF, 1, 0,
                ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED, ffi.C.D3DX_DEFAULT, ffi.C.D3DX_DEFAULT, 0xFF000000, nil, nil, ptr) == ffi.C.S_OK then
            local tex = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', ptr[0]))
            icons[id] = { tex = tex, ptr = tonumber(ffi.cast('uint32_t', tex)) }
        end
    end)
    return icons[id] or nil
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------
local line_h = {}   -- [family .. px] = the font's line height, measured while drawing

-- Height of one row (name, bar and the gap under it) with look s, for the panel's layout
function yuna.row_height(s)
    local lh = line_h[tostring(s.font_family) .. s.font_height] or math.floor(s.font_height * 1.25)
    return math.max(1, lh + 3 + s.bar_height + s.row_gap)
end

local function bar_color(group, s, b)
    if s.color_mode == 'time' then
        local secs, t, c = (b.remains or 0) / 60, s.thresholds, s.colors
        local u = (secs >= t.t75 and c.color100) or (secs >= t.t50 and c.color75) or (secs >= t.t25 and c.color50) or c.color25
        return helpers.color_u32_to_v4(u)
    end
    local kind = b.kind or PANEL_KIND[group.panel_id] or 'ja'
    return s.kinds[kind] or yuna.DEFAULTS.kinds[kind] or yuna.DEFAULTS.kinds.ja
end

-- The FFXI menu style lines (the panel's Menu Style settings), as the Default theme draws them
menu_lines = function(dl, m, x, y, w, h)
    local thick = math.max(1, math.floor(m.thickness or 2))
    if math.ceil(h / (thick * 2)) > 64 then thick = math.ceil(h / 128) end
    local op = math.max(0, math.min(100, m.opacity or 100)) / 100
    local off = 0
    while off < h do
        for k = 0, 1 do
            local top = off + k * thick
            local seg = math.min(thick, h - top)
            if seg <= 0 then break end
            local t = (top + seg / 2) / h
            local a = helpers.color_u32_to_v4((k == 0) and m.light_top or m.dark_top)
            local b = helpers.color_u32_to_v4((k == 0) and m.light_bottom or m.dark_bottom)
            RF(dl, x, y + top, x + w, y + top + seg, U4(a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t,
                a[3] + (b[3] - a[3]) * t, (a[4] + (b[4] - a[4]) * t) * op))
        end
        off = off + thick * 2
    end
end

local FRAME_PAD = 6   -- how far a style's frame sits outside the panel's area

local function draw_rows(group, s, st, list, count, left, top, width, height)
    -- ImGui's background list: drawn under every ImGui window (YunaUI's pieces, the Damage Meter,
    -- this addon's settings, other addons' windows), so the panels sit behind them
    local okb, bdl = pcall(imgui.GetBackgroundDrawList)
    local dl  = (okb and bdl) or imgui.GetWindowDrawList()
    local now = os.clock()
    local gs  = group.settings
    local pad = gs.padding

    -- The panel's background (Layout > Show a background): the style's frame round it when its
    -- Panel frame setting is on, else the plain background, menu lines and border
    if gs.enable_background and s.frame and st.frame then
        draw_frame(dl, st.frame, left - FRAME_PAD, top - FRAME_PAD, left + width + FRAME_PAD, top + height + FRAME_PAD)
    elseif gs.enable_background then
        local m = group:get_menu_bg()
        local round = m.enabled and 0 or 6
        RF(dl, left, top, left + width, top + height, UA(group.bg.color), round)
        if m.enabled then menu_lines(dl, m, left, top, width, height) end
        if group.bg.border_visible then
            local bs = tonumber(tostring(gs.background.border_sizes):match('^(%d+)')) or 1
            RR(dl, left, top, left + width, top + height, UA(group.bg.border_color), round, bs)
        end
    end

    local lh   = imgui.GetTextLineHeight()
    local bh   = s.bar_height
    local row  = math.max(1, lh + 3 + bh + s.row_gap)
    local isz  = (lh + 3 + bh) * s.icon_scale                  -- an icon (at 1.0) is as tall as the name and its bar
    local S    = gs.stretch or 0                               -- (Layout's Stretch: the bar alone takes it)
    local w    = math.max(10, gs.bar_width + S)

    for i = 1, count do
        local b  = list[i]
        local ry = top + pad[2] + (i - 1) * row
        local x  = left + pad[1]
        local bw = w

        local c  = bar_color(group, s, b)
        local c2 = (st.fade == 'end') and s.bar_end
                   or ((st.bar == 'plate' or st.bar == 'classic') and { c[1] * 0.80, c[2] * 0.80, c[3] * 0.86 })
                   or { c[1] * 0.75, c[2] * 0.75, c[3] * 0.75 }
        local remains = b.remains or 0

        -- run out (or past its estimate): the whole row pulses until the group drops it
        local a = 1
        if remains < 0 then a = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(now * 8)) end

        if s.enable_icons then
            local ic = status_icon(b.icon_id)
            if ic then
                local ix, iy = x + s.icon_offset_x, ry + s.icon_offset_y
                P1[1], P1[2], P2[1], P2[2] = ix, iy, ix + isz, iy + isz
                dl:AddImage(ic.ptr, P1, P2, { 0, 0 }, { 1, 1 }, U4(1, 1, 1, a))
            end
            x  = x + isz + 6
            bw = math.max(10, w - isz - 6)
        end

        local ts = clock(remains)
        local tw = text_w(ts)
        local nm = fit(b.name or '', bw - tw - 10)
        local function at(align, tw_)                              -- the text's left edge for its alignment
            if align == 'center' then return x + math.floor((bw - tw_) / 2) end
            if align == 'right' then return x + bw - tw_ end
            return x
        end
        local nx, ny = at(s.name_align, text_w(nm)) + s.name_font_offset_x, ry + s.name_font_offset_y
        local tx, ty = at(s.time_align or 'right', tw) + s.timer_font_offset_x, ry + s.timer_font_offset_y

        if s.font_bg_visible then
            local fb = UA(s.font_bg_color, a)
            RF(dl, nx - 2, ny, nx + text_w(nm) + 2, ny + lh, fb, 3)
            RF(dl, tx - 2, ty, tx + tw + 2, ty + lh, fb, 3)
        end

        -- the last 10 seconds (and recasts about to come back) blink softly, as YunaUI's
        local soon = ((remains >= 0 and remains < 600) or b.blink) and (0.75 + 0.25 * math.sin(now * 8)) or 1

        outlined(dl, nx, ny, nm, UA(s.name_font_color, a), UA(s.name_outline_color, a))
        local tcol = s.time_bar_color and U4(c[1], c[2], c[3], a * soon) or UA(s.time_font_color, a * soon)
        outlined(dl, tx, ty, ts, tcol, UA(s.time_outline_color, a * soon))

        -- every bar drains, recasts included (YunaUI's look)
        local v = 0
        if (b.duration or 0) > 0 and remains > 0 then v = remains / b.duration end
        -- the bar's own length and place in its row (Bars page); the text keeps to the row
        local by = ry + lh + 3 + (s.bar_offset_y or 0)
        x  = x + (s.bar_offset_x or 0)
        bw = math.max(2, math.floor((bw - S) * (s.bar_length or 100) / 100) + S)
        if s.bar_border_visible then
            local round = (st.bar == 'classic') and 0 or (st.bar == 'plate') and 2 or (bh / 2 + 1)
            RR(dl, x - 1, by - 1, x + bw + 1, by + bh + 1, UA(s.bar_border_color, a), round, 1.5)
        end
        if st.bar == 'thin' then
            thin_bar(dl, x, by, bw, bh, v, c, c2, s.effects, s.dot_blink and soon or 1)
        elseif st.bar == 'plate' or st.bar == 'classic' then
            plate_bar(dl, x, by, bw, bh, v, c, c2, s.effects, st.bar == 'classic')
        else
            glow_bar(dl, x, by, bw, bh, v, c, c2, 3.3 + i, s.effects)
        end
    end
end

local FLAGS = nil
local function window_flags()
    if FLAGS == nil then
        FLAGS = bit.bor(ImGuiWindowFlags_NoTitleBar or 0, ImGuiWindowFlags_NoResize or 0, ImGuiWindowFlags_NoScrollbar or 0,
                        ImGuiWindowFlags_NoScrollWithMouse or 0, ImGuiWindowFlags_NoCollapse or 0,
                        ImGuiWindowFlags_NoBackground or 0, ImGuiWindowFlags_NoFocusOnAppearing or 0,
                        ImGuiWindowFlags_NoNav or 0, ImGuiWindowFlags_NoSavedSettings or 0,
                        ImGuiWindowFlags_NoInputs or 0, ImGuiWindowFlags_NoMove or 0,
                        ImGuiWindowFlags_NoBringToFrontOnFocus or 0)
    end
    return FLAGS
end

local last_err = nil

-- An empty, see-through ImGui window over a Default-theme panel (drawn with Ashita's fonts and bars,
-- not ImGui): VanaCore puts the game's windows over an addon's ImGui windows where they meet
-- (vana.ui.game_on_top, timers.lua), so this gives those panels the same.  Only under VanaCore.
function yuna.area_window(group, left, top, width, height)
    if not rawget(_G, 'vana') or width <= 0 or height <= 0 then return end
    imgui.SetNextWindowPos({ left, top }, ImGuiCond_Always)
    imgui.SetNextWindowSize({ width, height }, ImGuiCond_Always)
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 })
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0)
    if imgui.Begin('##timers_area_' .. tostring(group.panel_id), { true }, window_flags()) then
        imgui.Dummy({ width, height })
    end
    imgui.End()
    imgui.PopStyleVar(2)
end

-- Draws a panel with look s in style `style` (a STYLES id): list holds its rows top to bottom
-- (count of them); left, top, width, height is the panel's area on screen (the same area
-- Shift+drag uses).  Called from d3d_present.
function yuna.draw(group, s, style, list, count, left, top, width, height)
    local st = yuna.STYLE[style] or yuna.STYLE.yunaui
    local framed = group.settings.enable_background and s.frame and st.frame
    local M = framed and (FRAME_PAD + 4) or 8                    -- room round the panel for the bars' glow (and frame)
    imgui.SetNextWindowPos({ left - M, top - M }, ImGuiCond_Always)
    imgui.SetNextWindowSize({ width + M * 2, height + M * 2 }, ImGuiCond_Always)
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 })
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0)
    if imgui.Begin('##timers_yuna_' .. tostring(group.panel_id), { true }, window_flags()) then
        local pushed = push_font(s.font_family, s.font_height)
        line_h[tostring(s.font_family) .. s.font_height] = imgui.GetTextLineHeight()
        local ok, e = pcall(draw_rows, group, s, st, list, count, left, top, width, height)
        pop_font(pushed)
        if not ok and e ~= last_err then
            last_err = e
            print(('[Timers] YunaUI theme: %s'):format(tostring(e)))
        end
    end
    imgui.End()
    imgui.PopStyleVar(2)
end

-- The Test tool's outlines: a solid line round the panel as it is now, and a dashed one round
-- the most it can grow to (its Max height, from where it is anchored)
local function dashed(dl, x1, y1, x2, y2, col)
    local DASH, GAP = 6, 4
    for x = x1, x2, DASH + GAP do RF(dl, x, y1, math.min(x + DASH, x2), y1 + 1, col); RF(dl, x, y2 - 1, math.min(x + DASH, x2), y2, col) end
    for y = y1, y2, DASH + GAP do RF(dl, x1, y, x1 + 1, math.min(y + DASH, y2), col); RF(dl, x2 - 1, y, x2, math.min(y + DASH, y2), col) end
end

function yuna.test_outline(left, top, width, height, max_top, max_h)
    local okb, dl = pcall(imgui.GetBackgroundDrawList)
    if not okb or not dl then return end
    dashed(dl, left - 2, max_top - 2, left + width + 2, max_top + max_h + 2, U4(1.0, 0.84, 0.4, 0.55))
    RR(dl, left - 1, top - 1, left + width + 1, top + height + 1, U4(1.0, 0.84, 0.4, 0.95), 0, 1.5)
    local s = 'max height'
    local tw = text_w(s)
    local lh = imgui.GetTextLineHeight()
    local ty = (max_top < top) and (max_top + 2) or (max_top + max_h - lh - 2)
    outlined(dl, left + width - tw - 4, ty, s, U4(1.0, 0.84, 0.4, 0.75), U4(0, 0, 0, 0.8))
end

-- A name over a panel (the Test tool: which panel is which), gold with a dark edge, just above
-- its area (and its frame when it has one).  Drawn on ImGui's background list, as the panels.
function yuna.title(group, text, left, top, s, style)
    local okb, dl = pcall(imgui.GetBackgroundDrawList)
    if not okb or not dl then return end
    local st = style and yuna.STYLE[style]
    local framed = st and group.settings.enable_background and s and s.frame and st.frame
    local lh = imgui.GetTextLineHeight()
    local y  = top - lh - 3 - (framed and FRAME_PAD or 0)
    outlined(dl, left, y, text, U4(1.0, 0.84, 0.4, 1.0), U4(0, 0, 0, 0.9))
end

return yuna
