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

function ActionIsLocal(actor)
    local party = AshitaCore:GetMemoryManager():GetParty()

    if not party then return false end

    -- Check every alliance slot (0-5 own party, 6-11 and 12-17 the other parties)
    for i = 0, 17 do
        local serverId = party:GetMemberServerId(i)
        if party:GetMemberIsActive(i) == 1 and serverId and serverId ~= 0 and (serverId == actor) then
            return true
        end
    end

    return false
end

function GetTargetIndex(target)
    if not target then return nil end

    local targetIndex = nil
    local packedIndex = bit.band(target, 0x7FF);

    if ((packedIndex < 0x400) and (AshitaCore:GetMemoryManager():GetEntity():GetServerId(packedIndex) == target)) then
        -- Target is a monster
        targetIndex = packedIndex
    else
        for i = 0x400,0x8FF do
            if (AshitaCore:GetMemoryManager():GetEntity():GetServerId(i) == target) then
                targetIndex = i;
                break;
            end
        end
    end

    return targetIndex
end

-- Number of frames (60 per second) an overdue timer keeps flashing in the list
-- before it is dropped.  5 seconds.
OVERDUE_LIMIT = 5 * 60

-- Strips the trailing "[...]" decoration (charges, roll value, step count, etc)
-- so "Ready [2]" or "Fighter's Roll [IV]" is filtered as "Ready" / "Fighter's Roll".
function FilterBaseName(name)
    if not name then return '' end
    local n = tostring(name)
    n = n:gsub('%s*%b[]%s*$', '')
    n = n:gsub('^%s+', '')
    n = n:gsub('%s+$', '')
    return n
end

-- Builds a sorted, de-duplicated list of names used by the filter tabs' search box.
--   timer_abilities: true  -> abilities that appear in the recast list (by timer id)
--                    false -> abilities that apply buffs/debuffs (action packet id + 512)
--   extra:           array of additional names to include
function BuildNameCatalog(timer_abilities, extra)
    local res  = AshitaCore:GetResourceManager()
    local seen = {}
    local list = {}

    local function add(n)
        if type(n) == 'string' and n ~= '' then
            local k = n:lower()
            if not seen[k] then
                seen[k] = true
                table.insert(list, n)
            end
        end
    end

    for _, n in ipairs(extra or {}) do add(n) end

    pcall(function()
        for i = 1, 1024 do
            local s = res:GetSpellById(i)
            if s and s.Name then add(s.Name[1]) end
        end

        if timer_abilities then
            for i = 1, 300 do
                local a = res:GetAbilityByTimerId(i)
                if a and a.Name then add(a.Name[1]) end
            end
        else
            for i = 512, 1023 do
                local a = res:GetAbilityById(i)
                if a and a.Name then add(a.Name[1]) end
            end
        end
    end)

    table.sort(list, function(a, b) return a:lower() < b:lower() end)
    return list
end

-- Ashita does not expose ability or spell icon images, only status-effect icons.
-- For recasts we look for a status effect with the same name (Berserk, Warcry, Haste,
-- Protect, ...) and use its icon.  Returns -1 when there is no match.
local gStatusIconByName = nil

function GetStatusIconForName(name)
    if gStatusIconByName == nil then
        gStatusIconByName = {}
        pcall(function()
            local res = AshitaCore:GetResourceManager()
            for i = 1, 1023 do
                local n = res:GetString('buffs.names', i)
                if n and n ~= '' and res:GetStatusIconById(i) ~= nil then
                    local k = n:lower()
                    if gStatusIconByName[k] == nil then gStatusIconByName[k] = i end
                end
            end
        end)
    end

    if not name then return -1 end
    return gStatusIconByName[FilterBaseName(name):lower()] or -1
end

-- The game's focused menu ('' when none): FFXI draws its menus before any addon draws, so a
-- panel can't go under one; it hides instead (a panel's Hide while a game menu is open).
-- Read through the game's menu pointer, as XIUI and YunaUI do ('menu    inline' -> 'inline').
local gMenuPtr = nil

function GameMenuName()
    if gMenuPtr == nil then
        local ok, p = pcall(ashita.memory.find, 'FFXiMain.dll', 0, '8B480C85C974??8B510885D274??3B05', 16, 0)
        gMenuPtr = (ok and p) or 0
    end
    if gMenuPtr == 0 then return '' end
    local ok, name = pcall(function()
        local sub = ashita.memory.read_uint32(gMenuPtr)
        if sub == nil or sub == 0 then return '' end
        local obj = ashita.memory.read_uint32(sub)
        if obj == nil or obj == 0 then return '' end
        local head = ashita.memory.read_uint32(obj + 4)
        if head == nil or head == 0 then return '' end
        return (ashita.memory.read_string(head + 0x46, 16) or '')
    end)
    if not ok or type(name) ~= 'string' then return '' end
    name = name:gsub('%z', ''):gsub('^%s*menu%s*', ''):gsub('%s+$', '')
    return name
end

-- Focused menus that don't count as a menu over the screen (typing in chat)
local NOT_A_MENU = { [''] = true, inline = true }

-- Set once a frame (timers.lua): whether a game menu is open
gGameMenuOpen = false
gGameMenuName = ''

function UpdateGameMenu()
    gGameMenuName = GameMenuName()
    gGameMenuOpen = not NOT_A_MENU[gGameMenuName]
end

-- Sort modes for TimerGroup:render.  Orders are described top-to-bottom on screen,
-- independent of which way the panel grows.
SortMode = {
    Default   = 0, -- order the timers were created in
    Remaining = 1, -- shortest remaining at the top, longest at the bottom
    CastOrder = 2, -- oldest cast at the top, newest at the bottom
    Target    = 3, -- grouped alphabetically by target, longest remaining at the bottom of each group
}
