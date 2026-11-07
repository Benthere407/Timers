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

--------------------------------------------------------------------------------
-- Copy to your other characters: one client writes all its sets to themes\filter_push.txt, and
-- every other character adds them to its own, now if it is running, else at its next login
-- (each character keeps the stamp of the last copy it took).  Those that took it say so in
-- themes\filter_push_ack.txt.
--------------------------------------------------------------------------------
M.pushed = nil       -- the stamp of the copy this client sent
M.push_took = {}     -- the characters that took it

local function push_path() return gThemes.dir() .. 'filter_push.txt' end
local function ack_path() return gThemes.dir() .. 'filter_push_ack.txt' end

local function push_stamp()
    local f = io.open(push_path(), 'r')
    if not f then return nil end
    local line = f:read('*l')
    f:close()
    return line and line:match('^%-%- (%S+)')
end

local function clean_set(s)
    local e = { name = tostring(s.name), job = tonumber(s.job) or 0 }
    for _, kind in ipairs(M.KINDS) do
        local f = type(s[kind]) == 'table' and s[kind] or {}
        e[kind] = { only_checked = (f.only_checked == true), show = copy_list(f.show), hide = copy_list(f.hide) }
    end
    return e
end

-- Sends every saved set.  Returns true, or false and why
function M.push()
    local d = { from = gThemes.my_name() or 'Another client', sets = {} }
    for _, s in ipairs(M.data.sets) do d.sets[#d.sets + 1] = clean_set(s) end
    local stamp = ('%d-%d'):format(os.time(), math.random(100000, 999999))
    os.remove(ack_path())
    local f, err = io.open(push_path(), 'w')
    if not f then return false, tostring(err) end
    f:write('-- ', stamp, '\n')
    f:write('return ', gThemes.serialize(d, ''), '\n')
    f:close()
    M.data.push_seen, M.pushed, M.push_took = stamp, stamp, {}
    persist()
    return true
end

-- A set here with the same name is replaced (keeping its job when the new one has none); others stay
local function merge(sets)
    for _, s in ipairs(sets) do
        if type(s) == 'table' and s.name then
            local e = clean_set(s)
            local old, idx = M.get(e.name)
            if old then
                if e.job == 0 then e.job = old.job or 0 end
                M.data.sets[idx] = e
            else
                table.insert(M.data.sets, e)
            end
            if e.job > 0 then M.set_job(e.name, e.job, true) end
        end
    end
end

-- Each second: a new copy to take, and who took the one sent from here
function M.poll()
    if not M.data then return end
    local name = gThemes.my_name()
    if not name then return end                     -- (no character yet: these aren't anyone's sets)
    local stamp = push_stamp()
    if stamp and stamp ~= M.data.push_seen then
        local fn = loadfile(push_path())
        if not fn then return end                   -- (still being written: next time)
        setfenv(fn, {})
        local ok, d = pcall(fn)
        if not ok or type(d) ~= 'table' or type(d.sets) ~= 'table' then return end
        merge(d.sets)
        M.data.push_seen = stamp
        persist()
        print(('[Timers] Added %d filter set(s) from %s: see Filter Sets.'):format(#d.sets, tostring(d.from)))
        local f = io.open(ack_path(), 'a')
        if f then
            f:write(stamp, '|', name, '\n')
            f:close()
        end
    end
    if M.pushed then
        local f = io.open(ack_path(), 'r')
        if f then
            local took = {}
            for line in f:lines() do
                local s, n = line:match('^(%S+)|(.+)$')
                if s == M.pushed then took[#took + 1] = n end
            end
            f:close()
            M.push_took = took
        end
    end
end

return M
