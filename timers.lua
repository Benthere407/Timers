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

addon.name      = 'Timers';
addon.author    = 'Shiyo, The Mystic, Benthere407';
addon.version   = '2.0.5';
addon.desc      = 'Displays the duration of spells and abilities you\'ve used';
addon.link      = 'https://github.com/Benthere407/Timers';

require('common');
require('ffi')
require('timer_group')
require('helpers')

local settings  = require('settings');

gRecast     = require('recasts');
gDebuff     = require('debuffs');
gBuff       = require('buffs');
gPacketData = require('packetdata')
gDuration   = require('duration.duration')
gFilterSets = require('filter_sets')
gThemes     = require('themes')
gGui        = require('conf_ui')

gShiftDown = false;
gRightClickEaten = false;   -- a right-click on a panel opened the settings: its button-up is blocked too

-- Default Settings
local default_settings = T{
    opacity = 1.0,
    padding = 1.0,
    scale = 1.0,
    locked = false,
    party_buffs = true,
    party_buffs_combine = true,
    ui_scale = 1.0, -- the settings window's scale (kept in the recast panel's settings)
    test_rows = 5,          -- the Test tool: sample timers in each panel, and what it marks them with
    test_titles = true,     -- (kept in the recast panel's settings, as ui_scale)
    test_outlines = true,

    -- Timers movement variables..
    move = T{
        dragging = false,
        drag_x = 0,
        drag_y = 0,
        shift_down = false,
    },
}

local timers = T{
    recasts = {
        settings = T{ },
        -- Currently displayed recast timers
        timers = nil,
    },
    debuffs = {
        settings = T{ },
        -- Currently displayed debuff timers
        timers = nil,
    },
    buffs = {
        settings = T{ },
        -- Currently displayed buff timers
        timers = nil,
    },
}

local function is_player_valid()
    if AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0) ~= 0 then
        return AshitaCore:GetMemoryManager():GetPlayer():GetIsZoning() == 0
    end

    return false
end

local function save_settings()
    settings.save('recast_panel_settings')
    settings.save('debuff_panel_settings')
    settings.save('buff_panel_settings')

    settings.save('recast_timer_settings')
    settings.save('debuff_timer_settings')
    settings.save('buff_timer_settings')
end

-- Every panel starts at the same place in its defaults, so a new install showed only one of
-- them (the others under it).  While all three are still on one spot, put them side by side.
local START_POS = { { 'recasts', 200 }, { 'buffs', 440 }, { 'debuffs', 680 } }
local START_Y = 200

local function spread_panels()
    local r, b, d = timers.recasts.timers, timers.buffs.timers, timers.debuffs.timers
    if not (r and b and d) then return end
    local rp, bp, dp = r.settings.background, b.settings.background, d.settings.background
    if not (rp.position_x == bp.position_x and bp.position_x == dp.position_x
            and rp.position_y == bp.position_y and bp.position_y == dp.position_y) then return end
    for _, e in ipairs(START_POS) do
        timers[e[1]].timers:move_to(e[2], START_Y)
    end
end

settings.register('recast_panel_settings', 'recast_panel_settings_update', function(s)
    if s ~= nil then timers.recasts.settings = s end
    settings.save('recast_panel_settings')
end)

settings.register('debuff_panel_settings', 'debuff_panel_settings_update', function(s)
    if s ~= nil then timers.debuffs.settings = s end
    settings.save('debuff_panel_settings')
end)

settings.register('buff_panel_settings', 'buff_panel_settings_update', function(s)
    if s ~= nil then timers.buffs.settings = s end
    settings.save('buff_panel_settings')
end)

settings.register('filter_sets', 'filter_sets_update', function(s)
    if s ~= nil then gFilterSets.init(s) end
    settings.save('filter_sets')
end)

settings.register('recast_timer_settings', 'recast_timer_settings_update', function(s)
    if s ~= nil then timers.recasts.timers.settings = s end
    settings.save('recast_timer_settings')
    if timers.recasts.timers then timers.recasts.timers:apply_settings() end
    spread_panels()
end)

settings.register('debuff_timer_settings', 'debuff_timer_settings_update', function(s)
    if s ~= nil then timers.debuffs.timers.settings = s end
    settings.save('debuff_timer_settings')
    if timers.debuffs.timers then timers.debuffs.timers:apply_settings() end
    spread_panels()
end)

settings.register('buff_timer_settings', 'buff_timer_settings_update', function(s)
    if s ~= nil then timers.buffs.timers.settings = s end
    settings.save('buff_timer_settings')
    if timers.buffs.timers then timers.buffs.timers:apply_settings() end
    spread_panels()
end)

--[[
* event: key
* desc : Event called when the addon is loaded
--]]
ashita.events.register('load', 'load_cb', function ()
    timers.recasts.settings = settings.load(default_settings, 'recast_panel_settings')
    timers.debuffs.settings = settings.load(default_settings, 'debuff_panel_settings')
    timers.buffs.settings = settings.load(default_settings, 'buff_panel_settings')

    timers.recasts.timers = TimerGroup:new()
    timers.debuffs.timers = TimerGroup:new()
    timers.buffs.timers = TimerGroup:new()

    timers.recasts.timers.panel_id = 'recasts'
    timers.debuffs.timers.panel_id = 'debuffs'
    timers.buffs.timers.panel_id = 'durations'

    timers.recasts.timers.settings = settings.load(TimerGroup:default_settings(), 'recast_timer_settings')
    timers.debuffs.timers.settings = settings.load(TimerGroup:default_settings(), 'debuff_timer_settings')
    timers.buffs.timers.settings = settings.load(TimerGroup:default_settings(), 'buff_timer_settings')

    timers.recasts.timers:apply_settings()
    timers.debuffs.timers:apply_settings()
    timers.buffs.timers:apply_settings()
    spread_panels()

    gFilterSets.init(settings.load(T{ auto_load = true, sets = T{}, push_seen = '' }, 'filter_sets'))

    local pm = AshitaCore:GetPointerManager();
    if (pm:Get(REALUTCSTAMP_ID) == 0) then
        pm:Add(REALUTCSTAMP_ID, 'FFXiMain.dll', '8B0D????????8B410C8B49108D04808D04808D04808D04C1C3', 2, 0);
    end

    -- the theme files, and any look this character's settings kept for a built-in theme
    gThemes.init({ recasts = timers.recasts.timers, durations = timers.buffs.timers, debuffs = timers.debuffs.timers })
    gThemes.on_take = save_settings

    -- VanaCore: the game's windows (menus, item details, shops) drawn over this addon's windows where
    -- they meet, so the panels sit behind them (the player's [client] menus.ontop=0 turns it off)
    pcall(function()
        local v = rawget(_G, 'vana')
        if v and v.ui and v.ui.game_on_top then v.ui.game_on_top(true) end
    end)

    gBuff.SyncBuffs()
end);

--[[
* event: key
* desc : Event called when the addon is unloaded
--]]
ashita.events.register('unload', 'unload_cb', function ()
    save_settings()
    pcall(gThemes.tick, true)

    if timers.recasts.timers then timers.recasts.timers:destroy() end
    if timers.debuffs.timers then timers.debuffs.timers:destroy() end
    if timers.buffs.timers then timers.buffs.timers:destroy() end
end);

--[[
* event: packet
* desc : Event called when a packet is received from the server
--]]
ashita.events.register('packet_in', 'packet_in_cb', function(e)
    if gPacketData then gPacketData.HandlePacket(e) end
    if gBuff then gBuff.HandlePacket(e) end
    if gDebuff then gDebuff.HandlePacket(e) end
end)

--[[
* event: key
* desc : Event called when the Direct3D device is presenting a scene
--]]
local last_job = nil

-- Load the filter set bound to the main job whenever the job changes
local function auto_load_filter_set()
    local job = AshitaCore:GetMemoryManager():GetPlayer():GetMainJob()
    if job == 0 or job == last_job then return end
    last_job = job

    if not gFilterSets.ready() or not gFilterSets.data.auto_load then return end

    local entry = gFilterSets.find_for_job(job)
    if entry then
        gFilterSets.apply(entry, {
            recasts   = timers.recasts.timers,
            durations = timers.buffs.timers,
            debuffs   = timers.debuffs.timers,
        })
    end
end

ashita.events.register('d3d_present', 'present_cb', function ()
    if not is_player_valid() then return end

    auto_load_filter_set()

    gBuff.ShowPartyBuffs(timers.buffs.settings.party_buffs, timers.buffs.settings.party_buffs_combine)
    UpdateGameMenu()

    gRecast.Update(timers.recasts.timers)
    gDebuff.Update(timers.debuffs.timers)
    gBuff.Update(timers.buffs.timers)

    gGui.render_config_ui(timers)
    gThemes.tick()
end);

--[[
* event: command
* desc : Event called when a / command is entered
--]]
ashita.events.register('command', 'command_cb', function (e)
    if string.lower(e.command) == '/timers' then
        gGui.is_open[1] = not gGui.is_open[1]
        e.blocked = true
    elseif string.lower(e.command) == '/timers lock' then
        timers.recasts.settings.locked = true
        timers.debuffs.settings.locked = true
        timers.buffs.settings.locked = true
        e.blocked = true;
    elseif string.lower(e.command) == '/timers unlock' then
        timers.recasts.settings.locked = false
        timers.debuffs.settings.locked = false
        timers.buffs.settings.locked = false
        e.blocked = true;
    elseif string.lower(e.command) == '/timers test' then
        e.blocked = true;
    end
end);

--[[
* event: key
* desc : Event called when the addon is processing keyboard input. (WNDPROC)
--]]
ashita.events.register('key', 'key_callback', function (e)
    -- Key: VK_SHIFT
    if (e.wparam == 0x10) then
        gShiftDown = not (bit.band(e.lparam, bit.lshift(0x8000, 0x10)) == bit.lshift(0x8000, 0x10));
        return;
    end
end);

--[[
* event: mouse
* desc : Event called when the addon is processing mouse input. (WNDPROC)
--]]
ashita.events.register('mouse', 'mouse_cb', function (e)

    -- Tests if the given coords are within the timers area.
    local function HitTest(panel, x, y)
        if (not panel.timers or not panel.timers.bg) then
            return false
        end

        -- We've already performed a hit test, and it was true, and the mouse
        -- button has not yet been released.  This provents the cursor
        -- from moving outside the border of the background and dropping
        -- the panel inappropriately while the mouse button is still down.
        if panel.settings.move.dragging then return true end

        local e_x = panel.timers.bg.position_x;
        local e_y = panel.timers.bg.position_y;
        local e_w = panel.timers.bg.width;
        local e_h = panel.timers.bg.height;

        return ((e_x <= x) and (e_x + e_w) >= x) and ((e_y <= y) and (e_y + e_h) >= y);
    end

    -- Right button up after a right-click that opened the settings: the game never saw the down
    if e.message == 517 and gRightClickEaten then
        gRightClickEaten = false
        e.blocked = true
        return
    end

    local panel = nil
    if HitTest(timers.recasts, e.x, e.y) then
        panel = timers.recasts
    elseif HitTest(timers.debuffs, e.x, e.y) then
        panel = timers.debuffs
    elseif HitTest(timers.buffs, e.x, e.y) then
        panel = timers.buffs
    end

    if not panel then return end

    -- Right-click on a panel on screen: open the settings window
    if e.message == 516 and panel.timers.shown then
        gGui.is_open[1] = true
        gRightClickEaten = true
        e.blocked = true
        return
    end

    local function is_dragging() return panel.settings.move.dragging; end

    -- Handle the various mouse messages..
    switch(e.message, {
        -- Event: Mouse Move
        [512] = (function ()
            panel.timers:move_to(
                e.x - panel.settings.move.drag_x,
                e.y - panel.settings.move.drag_y
            )

            e.blocked = true;
        end):cond(is_dragging),

        -- Event: Mouse Left Button Down
        [513] = (function ()
            if (gShiftDown and not panel.settings.locked) then
                panel.settings.move.dragging = true;
                -- Drag relative to the panel's anchor (top edge when growing down,
                -- bottom edge when growing up)
                panel.settings.move.drag_x = e.x - panel.timers.settings.background.position_x;
                panel.settings.move.drag_y = e.y - panel.timers.settings.background.position_y;

                e.blocked = true;
            end
        end):cond(HitTest:bindn(panel, e.x, e.y)),

        -- Event: Mouse Left Button Up
        [514] = (function ()
            if (panel.settings.move.dragging) then
                panel.settings.move.dragging = false;

                save_settings()

                e.blocked = true;
            end
        end):cond(is_dragging),

        -- (The mouse wheel is left alone: it used to change an opacity setting that nothing
        -- uses, erroring on it and eating the scroll of any window over a panel.)
    })
end)
