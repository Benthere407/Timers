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

-- Named sets of filters.  A set stores the Recast, Duration and Debuff filters together
-- and can optionally be bound to a job so it is loaded automatically when that job
-- becomes the main job.
--
-- Saved layout (settings file 'filter_sets'):
--   { auto_load = true,
--     sets = { { name='WAR', job=1,
--                recasts   = { only_checked=false, show={...}, hide={...} },
--                durations = { ... },
--                debuffs   = { ... } }, ... } }

local settings = require('settings')

local M = { data = nil }

M.JOB_ABBR = {
    'WAR','MNK','WHM','BLM','RDM','THF','PLD','DRK','BST','BRD','RNG',
    'SAM','NIN','DRG','SMN','BLU','COR','PUP','DNC','SCH','GEO','RUN',
}

M.KINDS = { 'recasts', 'durations', 'debuffs' }

local function copy_list(list)
    local r = {}
    for _, v in ipairs(list or {}) do r[#r + 1] = tostring(v) end
    return r
end

local function persist()
    settings.save('filter_sets')
end

-- Called with the table returned by settings.load (it must be modified in place so
-- the settings library keeps saving the same table).
function M.init(data)
    if type(data) ~= 'table' then data = {} end
    if type(data.sets) ~= 'table' then data.sets = {} end
    if data.auto_load == nil then data.auto_load = true end
    M.data = data
end

function M.ready()
    return M.data ~= nil
end

-- Sets sorted by name
function M.list()
    local r = {}
    if not M.data then return r end
    for _, s in ipairs(M.data.sets) do r[#r + 1] = s end
    table.sort(r, function(a, b) return tostring(a.name):lower() < tostring(b.name):lower() end)
    return r
end

function M.get(name)
    if not M.data or not name then return nil end
    local key = tostring(name):lower()
    for i, s in ipairs(M.data.sets) do
        if tostring(s.name):lower() == key then return s, i end
    end
    return nil
end

-- groups: { recasts = TimerGroup, durations = TimerGroup, debuffs = TimerGroup }
function M.save(name, groups, job)
    if not M.data then return false end
    name = tostring(name or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if name == '' then return false end

    local entry = M.get(name)
    if not entry then
        entry = { name = name, job = 0 }
        table.insert(M.data.sets, entry)
    end
    entry.name = name

    for _, kind in ipairs(M.KINDS) do
        local f = groups[kind]:get_filter()
        entry[kind] = {
            only_checked = (f.only_checked == true),
            show = copy_list(f.show),
            hide = copy_list(f.hide),
        }
    end

    if job and job > 0 then M.set_job(name, job, true) end

    persist()
    return true
end

function M.apply(entry, groups)
    if not entry then return false end
    for _, kind in ipairs(M.KINDS) do
        local f = entry[kind]
        if f and groups[kind] then
            groups[kind]:set_filter(f.only_checked, f.show, f.hide)
        end
    end
    return true
end

function M.load(name, groups)
    return M.apply(M.get(name), groups)
end

function M.delete(name)
    local _, idx = M.get(name)
    if not idx then return false end
    table.remove(M.data.sets, idx)
    persist()
    return true
end

-- job: 1-22, or 0 for none.  A job can only be bound to one set.
function M.set_job(name, job, skip_persist)
    local entry = M.get(name)
    if not entry then return false end

    if job and job > 0 then
        for _, s in ipairs(M.data.sets) do
            if s ~= entry and s.job == job then s.job = 0 end
        end
    end
    entry.job = job or 0

    if not skip_persist then persist() end
    return true
end

function M.find_for_job(job)
    if not M.data or not job or job <= 0 then return nil end
    for _, s in ipairs(M.data.sets) do
        if s.job == job then return s end
    end
    return nil
end

function M.set_auto_load(flag)
    if not M.data then return end
    M.data.auto_load = flag and true or false
    persist()
end

return M
