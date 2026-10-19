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

require('timer')
require('timer_common')

local prims     = require('primitives');
local scaling   = require('scaling')

local default_settings = T{
    enabled = true,
    enable_background = true,
    font_height = 8,
    font_bg_color = 0x00000000,
    font_bg_visible = false,
    font_family = 'Arial',
    name_font_color = 0xFFFFFFFF,
    name_outline_color = 0xFF000000,
    time_font_color = 0xFFFFFFFF,
    time_outline_color = 0xFF000000,
    bar_border_visible = true,
    bar_border_color = 0x80000000,
    bar_height = 3,
    bar_width = 200,
    max_height = 500,
    grow_up = false,
    sort_mode = 0,
    sort_reverse = false,
    enable_icons = true,
    icon_scale = 0.5,
    icon_offset_x = 0,
    icon_offset_y = 0,
    name_font_offset_x = 2,
    name_font_offset_y = 0,
    timer_font_offset_x = -2,
    timer_font_offset_y = 0,
    padding = T{ 5,2,5,2 },

    -- Background Primitive Settings
    background = T{
        border_visible = false,
        border_color = 0xFF000000,
        border_flags = FontBorderFlags.All,
        border_sizes = '1,1,1,1',
        visible = false,
        color = 0x40000000,
        can_focus = false,
        locked = true,
        width = 200,
        height = 0,
        position_x = 800,
        position_y = 500
    },

    thresholds = {
        t75 = 30,
        t50 = 20,
        t25 = 10,
    },

    colors = {
        color100 = 0xFF00FF00,
        color75  = 0xFFFFFF33,
        color50  = 0xFFFFA64D,
        color25  = 0xFFFF0000,
    },

    -- Include/exclude filter.  Names are matched case-insensitively.
    --   only_checked = false: everything is shown except names in 'hide'
    --   only_checked = true:  only names in 'show' are shown
    filter = T{
        only_checked = false,
        show = T{},
        hide = T{},
    },
}

TimerGroup = T{
    bg = nil,
    timers = {},
    active_timers = 0,

    settings = {}
}

function table.table_copy(t)
    local t2 = {}

    for k, v in pairs(t) do
        if type(v) == 'table' then
            t2[k] = table.table_copy(v)
        else
            t2[k] = v
        end
    end

    return t2
end

function TimerGroup:default_settings()
    return default_settings
end

function TimerGroup:new(o)
    local o = o or {}
    setmetatable(o, self)
    self.__index = self

    o.settings = table.table_copy(default_settings)
    o.bg = prims.new(o.settings.background);

    -- Names seen in this panel during this session (lowercase -> display name).
    -- Used to populate the filter tab.  Not saved.
    o.seen = {}

    -- Players can have no more than 32 statuses at once.
    -- Create 32 potential timer slots
    o.timers = {}
    for i = 0, 31 do
        local t = Timer:new(nil, nil, nil, 0, 0)
        t:hide()
        t.active = false
        t.thresholds = o.settings.thresholds
        t.colors = o.settings.colors

        o.timers[i + 1] = t
    end

    o.bg.width = o.settings.bar_width + o.settings.padding[1] + o.settings.padding[3]
    
    o:hide()
    return o
end

function TimerGroup:destroy()
    for k, v in pairs(self.timers) do
        if v then 
            v:destroy()
            self.timers[k] = nil
        end
    end

    self.bg:destroy()
end

function TimerGroup:clear()
    for k, v in pairs(self.timers) do
        if not v.active then break end
        if v then
            v.active = false
            v:hide()
        end
    end
end

function TimerGroup:clear_by_key(key)
    for k, v in pairs(self.timers) do
        if not v.active then break end
        if v and v.key == key then 
            v.active = false
            v:hide()
        end
    end
end

function TimerGroup:get_by_name(name)
    for _, v in pairs(self.timers) do
        if not v.active then break end
        if v and name:lower() == v.name:lower() then return v end
    end

    return nil
end

function TimerGroup:get_by_name_and_key(name, key)
    for _, v in pairs(self.timers) do
        if not v.active then break end
        if v and name:lower() == v.name:lower() and v.key == key then 
            return v
        end
    end

    return nil
end

function TimerGroup:get_by_key(key)
    for _, v in pairs(self.timers) do
        if not v.active then break end
        if v and v.key == key then return v end
    end

    return nil
end

function TimerGroup:hide()
    for _, v in pairs(self.timers) do
        if not v.active then break end
        if v then v:hide() end
    end

    self.bg.visible = false
end

function TimerGroup:show()
    -- Never show if the panel is set as hidden
    if not self.settings.enabled then
        -- And make sure that it's already hidden
        self:hide()
        return
    end

    self:move_to(self.settings.background.position_x, self.settings.background.position_y)
    self.bg.visible = self.settings.enable_background

    for _, v in pairs(self.timers) do
        if not v.active then break end
        if v then v:show() end
    end

end

-- x,y is the panel's anchor.  When growing down the anchor is the top-left corner,
-- when growing up it is the bottom-left corner.  Individual timer positions are
-- calculated every frame in render().
function TimerGroup:move_to(x, y)
    -- Do this so the position gets saved in the settings
    self.settings.background.position_x = x
    self.settings.background.position_y = y

    self.bg.position_x = x
    if self.settings.grow_up then
        self.bg.position_y = y - (self.bg.height or 0)
    else
        self.bg.position_y = y
    end
end

-- Switch growth direction without making the panel jump on screen.
function TimerGroup:set_grow_up(flag)
    flag = flag and true or false
    if (self.settings.grow_up and true or false) == flag then return end

    local top = self.bg.position_y
    local height = self.bg.height or 0

    self.settings.grow_up = flag
    self.settings.background.position_y = flag and (top + height) or top
end

function TimerGroup:update_timer_settings()
    for i = 1, 32 do
        local t = self.timers[i]

        t.bg.height = self.settings.bar_height
        t.width = self.settings.bar_width

        t.name_font.font_family = self.settings.font_family
        t.name_font.font_height = scaling.scale_f(self.settings.font_height)
        t.name_font.background.color = self.settings.font_bg_color
        t.name_font.background.visible = self.settings.font_bg_visible

        t.time_font.font_family = self.settings.font_family
        t.time_font.font_height = scaling.scale_f(self.settings.font_height)
        t.time_font.background.color = self.settings.font_bg_color
        t.time_font.background.visible = self.settings.font_bg_visible

        t.name_color = self.settings.name_font_color
        t.name_outline_color = self.settings.name_outline_color
        t.time_color = self.settings.time_font_color
        t.time_outline_color = self.settings.time_outline_color
        t.border_visible = self.settings.bar_border_visible
        t.border_color = self.settings.bar_border_color

        t.thresholds = self.settings.thresholds
        t.colors = self.settings.colors
        t.padding = self.settings.padding

        t.enable_icons = self.settings.enable_icons
        t.icon_scale = self.settings.icon_scale
        t.icon_offset_x = self.settings.icon_offset_x
        t.icon_offset_y = self.settings.icon_offset_y
        t.name_font_offset_x = self.settings.name_font_offset_x
        t.name_font_offset_y = self.settings.name_font_offset_y
        t.timer_font_offset_x = self.settings.timer_font_offset_x
        t.timer_font_offset_y = self.settings.timer_font_offset_y
    end
end

function TimerGroup:apply_settings()
    self.bg.border_visible = self.settings.background.border_visible
    self.bg.border_color = self.settings.background.border_color
    self.bg.border_sizes = self.settings.background.border_sizes
    self.bg.visible = self.settings.background.visible
    self.bg.color = self.settings.background.color

    self:update_timer_settings()
    self:move_to(self.settings.background.position_x, self.settings.background.position_y)
end

function TimerGroup:update_settings()
    -- Do this so these get saved in the settings
    self.settings.background.border_visible = self.bg.border_visible
    self.settings.background.border_color = self.bg.border_color
    self.settings.background.visible = self.bg.border_visible
    self.settings.background.color = self.bg.color

    self:update_timer_settings()
end

-- Filter helpers ------------------------------------------------------------

function TimerGroup:get_filter()
    local f = self.settings.filter
    if type(f) ~= 'table' then
        f = { only_checked = false, show = {}, hide = {} }
        self.settings.filter = f
    end
    if type(f.show) ~= 'table' then f.show = {} end
    if type(f.hide) ~= 'table' then f.hide = {} end
    return f
end

-- lowercase name -> true/false for every explicitly configured name
function TimerGroup:filter_map()
    local f = self:get_filter()
    if self._fmap == nil or self._fmap_src ~= f or self._fmap_dirty then
        local m = {}
        for _, n in ipairs(f.hide) do m[tostring(n):lower()] = false end
        for _, n in ipairs(f.show) do m[tostring(n):lower()] = true end
        self._fmap = m
        self._fmap_src = f
        self._fmap_dirty = false
    end
    return self._fmap, f
end

function TimerGroup:is_name_visible(name)
    local m, f = self:filter_map()
    local v = m[name:lower()]
    if v == nil then return not f.only_checked end
    return v
end

function TimerGroup:set_name_visible(name, visible)
    local _, f = self:filter_map()
    local key = name:lower()

    for _, list in ipairs({ f.show, f.hide }) do
        for i = #list, 1, -1 do
            if tostring(list[i]):lower() == key then table.remove(list, i) end
        end
    end

    table.insert(visible and f.show or f.hide, name)
    self._fmap_dirty = true
    self.filter_version = (self.filter_version or 0) + 1
end

-- Clears every explicit entry.  only_checked=false shows everything,
-- only_checked=true hides everything until items are checked again.
function TimerGroup:reset_filter(only_checked)
    local f = self:get_filter()
    f.only_checked = only_checked and true or false
    f.show = {}
    f.hide = {}
    self._fmap_dirty = true
    self.filter_version = (self.filter_version or 0) + 1
end

--[[
    Param is a table of bars with the structure:
    {name=<name>, duration=<duration>, remains=<remains>, mode=<mode>, key=<key>, icon_id=<id>,
     filter_name=<name used by the include/exclude filter; defaults to name>,
     start_time=<ms timestamp the timer was cast, for Cast Order>, target=<target name, for Target sort>,
     blink=<true to blink the timer while it is still running>}
    opts (optional) overrides the saved sort: { sort_mode=<SortMode>, sort_reverse=<bool> }
]]
function TimerGroup:render(bars, opts)
    self:clear()

    -- Apply the include/exclude filter and drop timers that have been overdue too long
    local list = {}
    for _, b in ipairs(bars) do
        local fname = FilterBaseName(b.filter_name or b.name)
        if fname ~= '' then self.seen[fname:lower()] = fname end

        local remains = b.remains or 0
        if remains > -OVERDUE_LIMIT and (fname == '' or self:is_name_visible(fname)) then
            table.insert(list, b)
        end
    end

    if not self.settings.enabled or #list <= 0 then
        self:hide()
        return
    else
        self:show()
    end

    local pad = self.settings.padding
    local row_h = self.timers[1]:get_height() + pad[4]

    -- How many rows fit in the configured maximum height
    local count = 0
    for i = 1, math.min(#list, 32) do
        if pad[2] + (row_h * i) > self.settings.max_height then break end
        count = i
    end

    if count == 0 then
        self:hide()
        return
    end

    -- Keep only what fits, then sort what is left
    for i = #list, count + 1, -1 do list[i] = nil end

    local mode    = (opts and opts.sort_mode) or self.settings.sort_mode or SortMode.Default
    local reverse = self.settings.sort_reverse
    if opts and opts.sort_reverse ~= nil then reverse = opts.sort_reverse end

    local grow_up = self.settings.grow_up and true or false

    if mode == SortMode.Default then
        -- First timer sits next to the anchor: top when growing down, bottom when growing up
        if grow_up then
            local n = #list
            for i = 1, math.floor(n / 2) do list[i], list[n - i + 1] = list[n - i + 1], list[i] end
        end
    else
        local items = {}
        for i, b in ipairs(list) do items[i] = { b = b, i = i } end

        table.sort(items, function(x, y)
            local a, b = x.b, y.b
            if mode == SortMode.CastOrder then
                local sa, sb = a.start_time or 0, b.start_time or 0
                if sa ~= sb then return sa < sb end
            elseif mode == SortMode.Target then
                local ta, tb = tostring(a.target or ''):lower(), tostring(b.target or ''):lower()
                if ta ~= tb then return ta < tb end
                if (a.remains or 0) ~= (b.remains or 0) then return (a.remains or 0) < (b.remains or 0) end
            else
                if (a.remains or 0) ~= (b.remains or 0) then return (a.remains or 0) < (b.remains or 0) end
            end
            return x.i < y.i -- keep the sort stable so rows don't swap places every frame
        end)

        for i, it in ipairs(items) do list[i] = it.b end

        if reverse then
            local n = #list
            for i = 1, math.floor(n / 2) do list[i], list[n - i + 1] = list[n - i + 1], list[i] end
        end
    end

    -- list[1] is now the top row on screen
    local anchor_x = self.settings.background.position_x
    local anchor_y = self.settings.background.position_y
    local total_h  = pad[2] + (row_h * count)
    local top_y    = grow_up and (anchor_y - total_h) or anchor_y

    self.bg.position_x = anchor_x
    self.bg.position_y = top_y
    self.bg.height = total_h
    self.bg.width = self.settings.bar_width + pad[1] + pad[3]

    for i = 1, count do
        local t = self.timers[i]
        local b = list[i]

        t.name = b.name or "Error: No Name"
        t.duration = b.duration or 0
        t.remains = b.remains or 0
        t.mode = b.mode or TimerMode.RightToLeft
        t.key = b.key or nil
        t.icon_id = b.icon_id or -1

        t.blink = (b.blink == true)

        local slot = i - 1
        t.position_x = anchor_x + pad[1]
        t.position_y = top_y + pad[2] + (row_h * slot)

        t.active = true

        t:show()
        t:update()
    end
end
