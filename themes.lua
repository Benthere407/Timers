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
    Themes: how the panels' bars, text and icons look (the layout - size, padding, background -
    is each panel's own, not part of a theme).

    Built-in themes (Default and the YunaUI styles) never change: their looks are the defaults in
    the code.  A custom theme is based on one of them ("base", whose renderer draws it) and holds
    a look for each panel.  Changing a built-in theme's settings makes a custom theme from it (see
    fork), so the built-in one stays as it was.

    Custom themes are files, themes\<name>.lua in this addon's folder, so every character can use
    them.  They are written a moment after they change (themes.tick), and when the addon unloads.
    A panel uses a custom theme as settings.theme = 'custom:<name>'.
]]

require('common')
local yuna = require('theme_yuna')

local themes = {
    custom = {},       -- [name] = { name, base, panels = { recasts = look, durations = look, debuffs = look } }
    groups = {},       -- [panel id] = TimerGroup (set by themes.init)
}

local PANELS = { 'recasts', 'durations', 'debuffs' }
themes.PANELS = PANELS

-- The Default theme's look settings (the rest of a panel's settings are its layout)
themes.DEFAULT_KEYS = { 'bar_height', 'bar_border_visible', 'bar_border_color', 'thresholds', 'colors',
    'font_family', 'font_height', 'font_bg_visible', 'font_bg_color', 'name_font_color', 'name_outline_color',
    'time_font_color', 'time_outline_color', 'name_font_offset_x', 'name_font_offset_y', 'timer_font_offset_x',
    'timer_font_offset_y', 'enable_icons', 'icon_scale', 'icon_offset_x', 'icon_offset_y',
    'bar_length', 'bar_offset_x', 'bar_offset_y', 'row_gap', 'name_align', 'time_align' }

local function copy(v) return (type(v) == 'table') and table.table_copy(v) or v end

local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    for k, v in pairs(a) do if not equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
themes.equal = equal

--------------------------------------------------------------------------------
-- Built-in themes
--------------------------------------------------------------------------------
themes.BUILTIN = { { 'default', 'Default' } }
for _, st in ipairs(yuna.STYLES) do themes.BUILTIN[#themes.BUILTIN + 1] = { st.id, st.label } end
local BUILTIN_LABEL = {}
for _, b in ipairs(themes.BUILTIN) do BUILTIN_LABEL[b[1]] = b[2] end

function themes.is_builtin(id) return BUILTIN_LABEL[id] ~= nil end

local function custom_of(id)
    if type(id) == 'string' and id:sub(1, 7) == 'custom:' then return themes.custom[id:sub(8)] end
    return nil
end
themes.custom_of = custom_of

function themes.custom_id(name) return 'custom:' .. name end

-- The built-in theme a theme draws as
function themes.base_of(id)
    if BUILTIN_LABEL[id] then return id end
    local e = custom_of(id)
    return (e and BUILTIN_LABEL[e.base]) and e.base or 'default'
end

function themes.label(id)
    if BUILTIN_LABEL[id] then return BUILTIN_LABEL[id] end
    local e = custom_of(id)
    return e and e.name or 'Default'
end

-- Every theme for a drop-down: { id, label }, the built-in ones then the custom ones
function themes.choices()
    local out = {}
    for _, b in ipairs(themes.BUILTIN) do out[#out + 1] = { b[1], b[2] } end
    local names = themes.names()
    if #names > 0 then
        out[#out + 1] = { sep = 'YOUR THEMES' }
        for _, n in ipairs(names) do out[#out + 1] = { themes.custom_id(n), n } end
    end
    return out
end

function themes.names()
    local names = {}
    for n in pairs(themes.custom) do names[#names + 1] = n end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

-- A built-in theme's look (shared and never changed: copy it before editing)
local default_look = nil
function themes.defaults(base)
    if base == 'default' or not yuna.STYLE[base] then
        if default_look == nil then
            local d = TimerGroup:default_settings()
            default_look = {}
            for _, k in ipairs(themes.DEFAULT_KEYS) do default_look[k] = copy(d[k]) end
        end
        return default_look
    end
    return yuna.defaults_for(base)
end

-- Anything a look is missing (an older file) filled in from its base's defaults
local function fill(look, base)
    local d = themes.defaults(base)
    for k, v in pairs(d) do
        if look[k] == nil then look[k] = copy(v)
        elseif type(v) == 'table' and type(look[k]) == 'table' then
            for k2, v2 in pairs(v) do
                if look[k][k2] == nil then look[k][k2] = copy(v2) end
            end
        end
    end
    return look
end

-- The panel's look now: the look table, its base, and the custom theme (nil for a built-in one,
-- whose look must not be changed)
function themes.look(group)
    local id = group.settings.theme or 'default'
    local e = custom_of(id)
    if e then
        local pid = group.panel_id or 'recasts'
        if type(e.panels[pid]) ~= 'table' then e.panels[pid] = copy(themes.defaults(e.base)) end
        return e.panels[pid], e.base, e
    end
    local base = BUILTIN_LABEL[id] and id or 'default'
    return themes.defaults(base), base, nil
end

--------------------------------------------------------------------------------
-- Files
--------------------------------------------------------------------------------
function themes.dir()
    return tostring(addon.path):gsub('[\\/]+$', '') .. '\\themes\\'
end

-- A name that is safe as a file name: letters, numbers, spaces and - _ . ( )
function themes.clean_name(n)
    n = tostring(n or ''):gsub('%z', ''):gsub('[^%w%s%-_%.%(%)]', '')
    n = n:gsub('^[%s%.]+', ''):gsub('[%s%.]+$', '')
    return n
end

local function path_of(name) return themes.dir() .. name .. '.lua' end

-- Writes a value as Lua source (tables with sorted keys, so the file reads well)
local function serialize(v, indent)
    local t = type(v)
    if t == 'number' then
        return ('%.17g'):format(v)
    elseif t == 'string' then
        return ('%q'):format(v)
    elseif t == 'boolean' then
        return tostring(v)
    elseif t == 'table' then
        local keys = {}
        for k in pairs(v) do
            if (type(k) == 'string' and k:sub(1, 1) ~= '_') or type(k) == 'number' then keys[#keys + 1] = k end
        end
        table.sort(keys, function(a, b)
            if type(a) == type(b) then return a < b end
            return type(a) == 'number'
        end)
        if #keys == 0 then return '{}' end
        local inner = indent .. '    '
        local out = { '{' }
        for _, k in ipairs(keys) do
            local val = v[k]
            if type(val) ~= 'function' and type(val) ~= 'userdata' then
                local key = (type(k) == 'string' and k:match('^[%a_][%w_]*$')) and k or ('[' .. serialize(k, inner) .. ']')
                out[#out + 1] = ('%s%s = %s,'):format(inner, key, serialize(val, inner))
            end
        end
        out[#out + 1] = indent .. '}'
        return table.concat(out, '\n')
    end
    return 'nil'
end

local function text_of(e)
    return serialize({ name = e.name, base = e.base, version = 2, panels = e.panels }, '')
end

local function write(e)
    local dir = themes.dir()
    if not ashita.fs.exists(dir) then
        if not pcall(ashita.fs.create_dir, dir) then pcall(ashita.fs.create_directory, dir) end
    end
    local text = text_of(e)
    local f, err = io.open(path_of(e.name), 'w')
    if not f then return false, tostring(err) end
    f:write('-- A Timers theme. Pick it in Timers\' Theme page; it changes as you edit it there.\n')
    f:write('return ', text, '\n')
    f:close()
    e._written = text
    return true
end

local function read(name)
    local fn = loadfile(path_of(name))
    if not fn then return nil end
    setfenv(fn, {})                                 -- (data only: the file sees no globals)
    local ok, data = pcall(fn)
    if not ok or type(data) ~= 'table' or type(data.panels) ~= 'table' or not BUILTIN_LABEL[data.base] then return nil end
    local e = { name = name, base = data.base, panels = {} }
    for _, pid in ipairs(PANELS) do
        e.panels[pid] = fill(type(data.panels[pid]) == 'table' and data.panels[pid] or {}, e.base)
    end
    e._written = text_of(e)
    return e
end

-- Reads every theme file in the themes folder
function themes.load_all()
    themes.custom = {}
    local ok, files = pcall(ashita.fs.get_dir, themes.dir(), '.*\\.lua', true)
    if not ok or type(files) ~= 'table' then ok, files = pcall(ashita.fs.get_directory, themes.dir()) end
    if not ok or type(files) ~= 'table' then return end
    for _, f in pairs(files) do
        local n = type(f) == 'string' and f:match('([^\\/]+)%.lua$')
        if n then
            local e = read(n)
            if e then themes.custom[n] = e end
        end
    end
end

-- Writes the custom themes that changed since they were last written (each second at most)
local last_tick = 0
function themes.tick(force)
    local now = os.clock()
    if not force and now - last_tick < 1 then return end
    last_tick = now
    for _, e in pairs(themes.custom) do
        if text_of(e) ~= e._written then pcall(write, e) end
    end
end

--------------------------------------------------------------------------------
-- Making, renaming and deleting custom themes
--------------------------------------------------------------------------------
local function unique_name(want)
    want = themes.clean_name(want)
    if want == '' then want = 'My theme' end
    local function taken(n)
        if themes.custom[n] then return true end
        local f = io.open(path_of(n), 'r')
        if f then f:close(); return true end
        return false
    end
    if not taken(want) then return want end
    local base = want:gsub('%s*%)$', ''):gsub('%s+%d+$', '')
    local closing = want:match('%)$') and ')' or ''
    for i = 2, 99 do
        local n = ('%s %d%s'):format(base, i, closing)
        if not taken(n) then return n end
    end
    return want .. ' ' .. os.time()
end

-- A new custom theme based on `base`, with every panel's look copied from `looks` (or the base's)
function themes.create(base, name, looks)
    local e = { name = unique_name(name or (BUILTIN_LABEL[base] .. ' (custom)')), base = base, panels = {} }
    for _, pid in ipairs(PANELS) do
        e.panels[pid] = fill(copy((looks and looks[pid]) or themes.defaults(base)), base)
    end
    themes.custom[e.name] = e
    write(e)
    return e
end

-- The panel uses a built-in theme and its look is about to change: make a custom theme from it
-- and move every panel using that built-in theme to it.  Returns the custom theme (the panel's
-- own, when it already uses one).
function themes.fork(group)
    local id = group.settings.theme or 'default'
    local e = custom_of(id)
    if e then return e end
    local base = BUILTIN_LABEL[id] and id or 'default'
    e = themes.create(base)
    for _, g in pairs(themes.groups) do
        if (g.settings.theme or 'default') == id then g.settings.theme = themes.custom_id(e.name) end
    end
    return e
end

function themes.rename(old, new)
    local e = themes.custom[old]
    if not e then return false, 'no such theme' end
    new = themes.clean_name(new)
    if new == '' then return false, 'enter a name' end
    if new == old then return true end
    if themes.custom[new] then return false, ('"%s" already exists'):format(new) end
    themes.custom[old], e.name = nil, new
    themes.custom[new] = e
    local ok, err = write(e)
    if not ok then return false, err end
    os.remove(path_of(old))
    for _, g in pairs(themes.groups) do
        if g.settings.theme == themes.custom_id(old) then g.settings.theme = themes.custom_id(new) end
    end
    if themes.start == themes.custom_id(old) then pcall(themes.set_start, themes.custom_id(new)) end
    return true
end

-- Deletes the theme's file; panels using it go back to its built-in theme
function themes.delete(name)
    local e = themes.custom[name]
    if not e then return false, 'no such theme' end
    local ok, err = os.remove(path_of(name))
    if not ok and io.open(path_of(name), 'r') then return false, tostring(err) end
    themes.custom[name] = nil
    for _, g in pairs(themes.groups) do
        if g.settings.theme == themes.custom_id(name) then g.settings.theme = e.base end
    end
    if themes.start == themes.custom_id(name) then pcall(themes.set_start, e.base) end
    return true
end

--------------------------------------------------------------------------------
-- Start up: read the theme files, and carry the looks a character's settings kept before themes
-- held them (changes made to a built-in theme) into custom themes
--------------------------------------------------------------------------------
local function stored_look(g, base)
    if base == 'default' then
        local t = {}
        for _, k in ipairs(themes.DEFAULT_KEYS) do t[k] = copy(g.settings[k]) end
        return fill(t, 'default')
    end
    return copy((yuna.settings(g, base)))
end

local function migrate()
    local made = {}   -- [built-in id] = custom theme made for it
    for _, pid in ipairs(PANELS) do
        local g = themes.groups[pid]
        if g and (g.settings.themes_v or 0) < 2 then
            local id = g.settings.theme or 'default'
            if BUILTIN_LABEL[id] then
                local look = stored_look(g, id)
                if not equal(look, themes.defaults(id)) then
                    made[id] = made[id] or themes.create(id)
                    made[id].panels[pid] = look
                end
            end
        end
    end
    for _, pid in ipairs(PANELS) do
        local g = themes.groups[pid]
        if g and (g.settings.themes_v or 0) < 2 then
            local id = g.settings.theme or 'default'
            if made[id] then g.settings.theme = themes.custom_id(made[id].name) end
            g.settings.themes_v = 2
        end
    end
    for _, e in pairs(made) do write(e) end
end

--------------------------------------------------------------------------------
-- The start theme: the theme a character's panels start with (themes\start.txt, for every
-- character).  A panel takes it once, while it is still on Default; after that its theme is its own.
--------------------------------------------------------------------------------
themes.start = nil

local function start_path() return themes.dir() .. 'start.txt' end

local function valid(id) return id ~= nil and (BUILTIN_LABEL[id] ~= nil or custom_of(id) ~= nil) end

function themes.read_start()
    themes.start = nil
    local f = io.open(start_path(), 'r')
    if not f then return end
    local id = (f:read('*l') or ''):gsub('^%s+', ''):gsub('%s+$', '')
    f:close()
    if id ~= '' and id ~= 'default' then themes.start = id end
end

-- id: a theme id, or nil / 'default' for none.  The panels here count as having chosen.
function themes.set_start(id)
    if id == 'default' then id = nil end
    themes.start = id
    if id == nil then
        os.remove(start_path())
    else
        local dir = themes.dir()
        if not ashita.fs.exists(dir) then
            if not pcall(ashita.fs.create_dir, dir) then pcall(ashita.fs.create_directory, dir) end
        end
        local f, err = io.open(start_path(), 'w')
        if not f then return false, tostring(err) end
        f:write(id, '\n')
        f:close()
    end
    for _, g in pairs(themes.groups) do g.settings.start_done = true end
    return true
end

local function apply_start()
    if not valid(themes.start) then return end
    for _, g in pairs(themes.groups) do
        if not g.settings.start_done then
            if (g.settings.theme or 'default') == 'default' then g.settings.theme = themes.start end
            g.settings.start_done = true
        end
    end
end

-- groups: { recasts = TimerGroup, durations = TimerGroup, debuffs = TimerGroup }
function themes.init(groups)
    themes.groups = groups
    themes.load_all()
    pcall(migrate)
    -- a panel whose theme file is gone goes back to Default
    for _, g in pairs(groups) do
        local id = g.settings.theme or 'default'
        if not BUILTIN_LABEL[id] and not custom_of(id) then g.settings.theme = 'default' end
    end
    pcall(themes.read_start)
    pcall(apply_start)
end

return themes
