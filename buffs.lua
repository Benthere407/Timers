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

require('timer_group')
require('action_packets')
require('timer_common')
require('ashita4data')
require('enums')

local helpers = require('helpers')

-- How timers for party members hit by our AoE buffs are shown
local PartyOptions = T{
    show = true,    -- show timers for other party members at all
    combine = true, -- one "(Party)" timer when the whole party has the same buff
}

local buffs = {
    -- Currently displayed recast timers
    buffs = T{},
};

local BlockedSpells = T{
    24931,
}

local BlockedBuffs = T{
    0,1,603,627,45,46,47,48,49,38,39,40,41,42,359,358 
}

local AbilityMsgs = T{
    [100] = T{id=100},
    [115] = T{id=115},
    [116] = T{id=116},
    [117] = T{id=117},
    [118] = T{id=118},
    [120] = T{id=120},
    [121] = T{id=121},
    [126] = T{id=126},
    [131] = T{id=131},
    [134] = T{id=134},
    [143] = T{id=143},
    [146] = T{id=146},
    [148] = T{id=148},
    [150] = T{id=150},
    [323] = T{id=323}, -- RUN Valiance Ward
    [420] = T{id=420}, -- Corsair Rolls
    [424] = T{id=424}, -- Double Up
    [426] = T{id=426}, -- Bust
    [532] = T{id=532},
    [667] = T{id=667}, -- RUN Swordplay
    [668] = T{id=668}, -- RUN Vallation Ward
    [670] = T{id=670}, -- RUN Liement Ward
    [671] = T{id=671}, -- RUN Pflug Ward
    [798] = T{id=797}, -- Maneuvers
}

local AbilityTypes = T{
    [6]  = T{id=6},
    [14] = T{id=14},
    [15] = T{id=15}, -- Run Pflug Ward.  Maybe others
}

local SpellMsgs = T{
    [205] = T{id=205},
    [230] = T{id=230},
    [266] = T{id=266},
    [280] = T{id=280},
    [319] = T{id=319},
}

local SpellTypes = T{
    [4] = T{id=4},
}

local CorsairRolls = T{
    [98]  = T{ id=98, status=310 },
    [99]  = T{ id=99, status=311 },
    [100] = T{ id=100, status=312 },
    [101] = T{ id=101, status=313 },
    [102] = T{ id=102, status=314 },
    [103] = T{ id=103, status=315 },
    [104] = T{ id=104, status=316 },
    [105] = T{ id=105, status=317 },
    [106] = T{ id=106, status=318 },
    [107] = T{ id=107, status=319 },
    [108] = T{ id=108, status=320 },
    [109] = T{ id=109, status=321 },
    [110] = T{ id=110, status=322 },
    [111] = T{ id=111, status=323 },
    [112] = T{ id=112, status=324 },
    [113] = T{ id=113, status=325 },
    [114] = T{ id=114, status=326 },
    [115] = T{ id=115, status=327 },
    [116] = T{ id=116, status=328 },
    [117] = T{ id=117, status=329 },
    [118] = T{ id=118, status=330 },
    [119] = T{ id=119, status=331 },
    [120] = T{ id=120, status=332 },
    [121] = T{ id=121, status=333 },
    [122] = T{ id=122, status=334 },
    [302] = T{ id=302, status=335 },
    [303] = T{ id=303, status=336 },
    [304] = T{ id=304, status=337 },
    [305] = T{ id=305, status=338 },
    [390] = T{ id=305, status=339 },
    [391] = T{ id=305, status=600 },
}

local SpellOverride = T{
    -- All Utsusemi spells apply param 66 in the action packet.  Normally param is
    -- the buff Id, but in this case, it's not.  Both apply buff 445 if your subjob
    -- is NIN. If your main job is NIN, Ni applies 446, and Ichi applies 445.
    -- Utsusemi: Ichi and Utsusemi: Ni
    [338] = T{ job=Jobs.Ninja, main=445, sub=445 },
    [339] = T{ job=Jobs.Ninja, main=446, sub=445 },
}

local AbilityOverride = T{
    -- Holy Circle
    [47]  = T{ job=Jobs.Paladin, main=74, sub=74 },

    -- Arcane Circle
    [50]  = T{ job=Jobs.DarkKnight, main=75, sub=75 },

    -- Mikage
    [335] = T{ job=Jobs.Ninja, main=502, sub=502 },

    -- Runes
    [358] = T{ job=Jobs.RuneFencer, main=523, sub=523 },
    [359] = T{ job=Jobs.RuneFencer, main=524, sub=524 },
    [360] = T{ job=Jobs.RuneFencer, main=525, sub=525 },
    [361] = T{ job=Jobs.RuneFencer, main=526, sub=526 },
    [362] = T{ job=Jobs.RuneFencer, main=527, sub=527 },
    [363] = T{ job=Jobs.RuneFencer, main=528, sub=528 },
    [364] = T{ job=Jobs.RuneFencer, main=529, sub=529 },
    [365] = T{ Job=Jobs.RuneFencer, main=530, sub=530 },

    -- Maneuvers
    [141] = T{ Job=Jobs.Puppetmaster, main=300, sub=300 },
    [142] = T{ Job=Jobs.Puppetmaster, main=301, sub=301 },
    [143] = T{ Job=Jobs.Puppetmaster, main=302, sub=302 },
    [144] = T{ Job=Jobs.Puppetmaster, main=303, sub=303 },
    [145] = T{ Job=Jobs.Puppetmaster, main=304, sub=304 },
    [146] = T{ Job=Jobs.Puppetmaster, main=305, sub=305 },
    [147] = T{ Job=Jobs.Puppetmaster, main=306, sub=306 },
    [148] = T{ Job=Jobs.Puppetmaster, main=307, sub=307 },

    -- Ward -> Valiance
    [371] = T{ Job=Jobs.RuneFencer, main=535, sub=535 },
}

local MultipleAllowed = T{ 
    309, -- Corsair
    523,524,525,526,527,528,529,530, -- Runefencer
    192,195,196,197,198,199,200,201,206,214,215,216,219, -- Bard
}

local function IsBardBuff(id)
    return T{ 192,195,196,197,198,199,200,201,206,214,215,216,219, }:hasval(id)
end

local function GetEffectOverride(spell, type)
    local player = AshitaCore:GetMemoryManager():GetPlayer()

    if not player then return nil end

    local mjob = player:GetMainJob()

    if AbilityTypes:haskey(type) and AbilityOverride:haskey(spell) then
        if mjob == AbilityOverride[spell].job then
            return AbilityOverride[spell].main
        else
            return AbilityOverride[spell].sub
        end
    elseif SpellTypes:haskey(type) and SpellOverride:haskey(spell) then
         if mjob == SpellOverride[spell].job then
            return SpellOverride[spell].main
        else
            return SpellOverride[spell].sub
        end
    end

    return nil
end

local function InsertBuff(actor, target, effect, name, duration, replace, time, aoe)
    local o_time = time or ashita.time.clock()['ms']
    if replace == nil then replace = true end

    if (not target or target == 0) or (not actor or actor == 0) then return end

    if not effect or effect == 0 or BlockedBuffs:hasval(effect) then return end

    local target_index = GetTargetIndex(target)
    if not target_index then return end

    if not buffs.buffs[target] then
        buffs.buffs[target] = T{}
        buffs.buffs[target].effects = T{}
    end

    if not buffs.buffs[target].effects[effect] then
        buffs.buffs[target].effects[effect] = T{}
    end

    local t = buffs.buffs[target].effects[effect]
    local entry = T{ name=name, o_time=o_time, c_time=o_time, duration=duration, target_id=target,
                     a_index=GetTargetIndex(actor), t_index=target_index, ttl=-1, aoe=(aoe == true) }

    if replace or not MultipleAllowed:hasval(effect) then
        t[1] = entry
    else
        -- Some buffs can stack (two songs, three runes), so these are appended rather than
        -- replaced.  But the same cast can arrive more than once (the action packet, then the
        -- party buff update for an AoE), and recasting a song replaces the old one in game.
        -- So reuse the existing entry instead of adding a duplicate:
        --   * songs:  a target can only have one of each song, match on name
        --   * others: match on name and cast time (the same cast reported twice)
        local dup = nil
        for k, v in pairs(t) do
            if v.name == name and (IsBardBuff(effect) or v.o_time == o_time) then
                dup = k
                break
            end
        end

        if dup then
            t[dup] = entry
        else
            -- Find a free slot (the cleanup code leaves holes, which table.insert doesn't handle well)
            local k = 1
            while t[k] do k = k + 1 end
            t[k] = entry
        end
    end
end

local function RemoveBuff(target, target_id)
    local buffs = buffs.buffs[target]
    if not buffs then return false end

    -- Find the oldest matching buff then reset the time and duration
    -- to indicate that the buff has expired, and when it expired
    -- Any BRD buff matches any other BRD buff
    local least_duration = math.huge
    local id = nil
    local idx = nil
    for b_id, buff_t in pairs(buffs.effects) do
        if (b_id == target_id) or (IsBardBuff(target_id) and IsBardBuff(b_id)) then
            for k, v in pairs(buff_t) do
                if v.duration > -1 and (v.duration < least_duration) then
                    least_duration = v.duration
                    id = b_id
                    idx = k
                end
            end
        end
    end

    if id and idx and buffs.effects[id] and buffs.effects[id][idx] then
        buffs.effects[id][idx].duration = -1
        buffs.effects[id][idx].o_time = ashita.time.clock()['ms']
        return true
    end

    return false
end

local function GetBustDuration() 
    local base = 300 -- 5 Minutes
    local merits = gData.GetMeritCount(0x588)

    return (base - (merits * 10)) * 60
end

local function HandleCorsairBust(spell, target, name, actor)
    local bust_effect = 309
    local duration = GetBustDuration()

    -- Get the right status and Remove the effect of the roll that busted
    local status = CorsairRolls[spell].status
    buffs.buffs[target].effects[status] = nil

    InsertBuff(actor, target, bust_effect, name, duration, false)
end

-- Called once for each party member the roll landed on
local function HandleCorsairRoll(target, effect, spell, actor, time)
    local a = AshitaCore:GetResourceManager():GetAbilityById(spell + 512)
    local name = (a and a.Name[1]) or 'Unknown'
    name = ('%s [%s]'):fmt(name, helpers.to_roman_numerals(effect))

    if effect >= 12 then -- Bust
        if target == actor then
            HandleCorsairBust(spell, target, name, actor)
        else
            buffs.buffs[target].effects[CorsairRolls[spell].status] = nil
        end
        return
    end

    effect = CorsairRolls[spell].status

    local t = buffs.buffs[target].effects[effect]
    if t and t[1] then
        -- This is a double-up since the buff already exists.  Replace the old
        -- buff with a new one so that we can change the name
        local e = t[1]
        InsertBuff(actor, target, effect, name, e.duration, true, e.o_time, e.aoe)

        return -- We're done here, everything below is for the initial cast/use
    end

    local duration = gDuration.GetAbilityDuration(spell, target)
    duration = (duration and duration * 60) or nil
    local o_time = time or ashita.time.clock()['ms']

    if not duration then return end

    local aoe = (a ~= nil) and a.AreaRange > 0
    InsertBuff(actor, target, effect, name, duration, false, o_time, aoe)

    -- Create a timer for Double-Up
    if target == actor then
        t = buffs.buffs[target].effects[308]
        if not t or not t[1] then
            InsertBuff(actor, target, 308, 'Double-Up Chance', 45*60, true)
        end
    end
end
 
local function ApplyBuff(target, effect, spell, actor, type, time)
    if not buffs.buffs[target] then
        buffs.buffs[target] = T{}
        buffs.buffs[target].effects = T{}
    end

    local resMan = AshitaCore:GetResourceManager()

    -- Create timer
    local duration = nil
    local name = nil
    local o_time = time or ashita.time.clock()['ms']
    local aoe = false

    if AbilityTypes:haskey(type) then
        if CorsairRolls:haskey(spell) then
            HandleCorsairRoll(target, effect, spell, actor, o_time)
            return
        end
        duration = gDuration.GetAbilityDuration(spell, target)
        duration = (duration and duration * 60) or nil
        local a = resMan:GetAbilityById(spell + 512)
        name = (a and a.Name[1]) or 'Unknown'
        aoe = (a ~= nil) and a.AreaRange > 0
    elseif SpellTypes:haskey(type) then
        duration = gDuration.GetSpellDuration(spell, target)
        duration = (duration and duration * 60) or nil
        local s = resMan:GetSpellById(spell)
        name = (s and s.Name[1]) or 'Unknown'
        aoe = (s ~= nil) and s.AreaRange > 0
    else
        local t = GetEntity(GetTargetIndex(actor))
        local name = (t and t.Name) or nil
        print(('Timers: Unknown action [%d] with type [%d] used by %s'):fmt(spell, type, name or 'Unknown'))
    end

    if not duration then return end

    InsertBuff(actor, target, effect, name, duration, false, o_time, aoe)
end

local function HandleAction(act)
    local party = AshitaCore:GetMemoryManager():GetParty()

    if not party then return end

    if #act.targets == 0 then return end
    if #act.targets[1].actions == 0 then return end

    local serverId = party:GetMemberServerId(0)
    if not serverId or (serverId ~= act.actor_id) then return end

    local spell = act.param
    local actor = act.actor_id
    local type = act['type']

    if BlockedSpells:hasval(spell) then return end

    -- AoE spells and abilities (rolls and songs included) list every member they landed on,
    -- so apply the buff to each target.  Every target of one cast shares the same cast time.
    local o_time = ashita.time.clock()['ms']

    for i = 1, #act.targets do
        local t = act.targets[i]
        local a = t.actions[1]
        if a and (AbilityMsgs:haskey(a.message) or SpellMsgs:haskey(a.message)) then
            --print(('%d, %d, %d, %d, %d'):fmt(a.message, spell, type, a.effect, a.param))
            local param = (GetEffectOverride(spell) or a.param)

            ApplyBuff(t.id, param, spell, actor, type, o_time)
        end
    end
end

local function HandleActionMessage(data)
    local msg = {}
    msg.actor_id    = struct.unpack('I', data, 0x05)
    msg.target_id   = struct.unpack('I', data, 0x09)
    msg.param_1     = struct.unpack('I', data, 0x0D)
    msg.param_2     = struct.unpack('I', data, 0x11)
    msg.actor_idx   = struct.unpack('H', data, 0x15)
    msg.target_idx  = struct.unpack('H', data, 0x17)
    msg.message_id  = struct.unpack('H', data, 0x19) % 32768

    -- Target died
    if T{6, 20, 113, 406, 605, 646}:hasval(msg.message_id) then
        buffs.buffs[msg.target_id] = nil
        
    -- Buff expired or was cancelled.  This may be unnecessary.
    -- Since I'm not sure, it doesn't hurt anything to have it
    elseif T{206, 321, 322}:hasval(msg.message_id) then
        RemoveBuff(msg.target_id, msg.param_1)
    end
end

local function HandlePartyBuffUpdate(e)
    local updatedBuffs = T{}

    for i = 0, 4 do
        local memberId = struct.unpack('L', e.data, 0x04 + (i * 0x48) + 1);
        local memberIndex = struct.unpack('H', e.data, 0x08 + (i * 0x48) + 1);
        if memberIndex == 0 then break end

        -- memberIndex is a Trust, and we don't get buff updates for Trusts
        if memberIndex > 0x6FF and memberIndex <= 0x8FF then goto continue end

        updatedBuffs[memberId] = T{}
        
        for j = 1, 32 do
            local buff = struct.unpack('B', e.data, 0x14 + (i * 0x48) + j);
            if (buff == 255) then
                break;
            end
            local bitMask = ashita.bits.unpack_be(e.data_raw, 0x0C + (i * 0x48), (j - 1) * 2, 2);
            local buff_id = bit.lshift(bitMask, 8) + buff;

            table.insert(updatedBuffs[memberId], buff_id)
        end
        ::continue::
    end

    -- Remove buffs that have worn
    for target, data in pairs(buffs.buffs) do
        for id, buff_t in pairs(data.effects) do
            for _, v in pairs(buff_t) do
                if updatedBuffs[target] and not updatedBuffs[target]:hasval(id) then
                    RemoveBuff(target, id)
                end
            end
        end
    end

    -- AoE buffs used to be guessed from here (any member gaining the same buff shortly
    -- after our cast).  That credited other players' casts to us, and the action packet
    -- already lists every member our AoE landed on, so HandleAction covers them now.
end

function HandleReplaceUtsusemi(server_id, id)
    local new_utsusemi_id = nil
    local utsusemi_table = T{ 446, 445, 444, 66 }
    if utsusemi_table:hasval(id) then
        utsusemi_table:each(function(v)
            if gData.GetBuffActive(v) then
                local effects = buffs.buffs[server_id].effects
                effects[v] = T{}
                effects[v][1] = effects[id][1]
                effects[id] = T{}
                new_utsusemi_id = v
            end
        end)
    end

    return new_utsusemi_id
end

function HandleBuffUpdate()
    local p_server_id = AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0)

    if not p_server_id or not buffs.buffs[p_server_id] then return end

    -- Remove timers for buffs we no longer have
    for id, effect_t in pairs(buffs.buffs[p_server_id].effects) do
        local buff_count = gPackets.GetBuffCount(id)
        if buff_count < helpers.table_length(effect_t) then
            local new_id = HandleReplaceUtsusemi(p_server_id, id)
            if not new_id then
                for i = 1, helpers.table_length(effect_t) - buff_count do
                    RemoveBuff(p_server_id, id)
                end
            end
        end
    end
end

--[[
    This is a fairly useless function, but there may be some cases
    where the addon is loaded with buffs already active, and I'd like
    to make a best effort at picking those up
]]
function SyncBuffs()
    local target = AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0)
    local player = AshitaCore:GetMemoryManager():GetPlayer()

    if not target or not player then return end

    if not buffs.buffs[target] then
        buffs.buffs[target] = {}
        buffs.buffs[target].effects = {}
    end

    local active_buffs = player:GetBuffs()
    local active_timers = player:GetStatusTimers()
    for i=1, 32 do
        local name = AshitaCore:GetResourceManager():GetString('buffs.names', active_buffs[i])
        if name == nil then break end

        local effect_t = buffs.buffs[target].effects[active_buffs[i]]
        if effect_t then
            -- There is already at least one instance of this buff
            local buff_count = gPackets.GetBuffCount(active_buffs[i])
            if buff_count < helpers.table_length(effect_t) then
                local duration = helpers.buff_duration(active_timers[i])
                if duration and duration > 0 then
                    InsertBuff(target, target, active_buffs[i], name, duration, false)
                end
            end
        else
            -- Permanent buffs report -1 (and expired ones 0); there is nothing to count down
            local duration = helpers.buff_duration(active_timers[i])
            if duration and duration > 0 then
                InsertBuff(target, target, active_buffs[i], name, duration, true)
            end
        end
    end
end

local function HandlePacket(e)
    if e.blocked then return end

    if e.id == 0x028 then
        HandleAction(ParseActionPacket(e.data_modified))
    elseif e.id == 0x029 then
        HandleActionMessage(e.data_modified)
    elseif e.id == 0x37 then -- Buffs changed due to Zone, or other
        HandleBuffUpdate()
    elseif e.id == 0x076 then
        HandlePartyBuffUpdate(e)
    end
end

-- Number of members in our own party (slots 0-5) in our zone, trusts included
local function GetPartySize()
    local party = AshitaCore:GetMemoryManager():GetParty()
    local zone = party:GetMemberZone(0)
    local count = 0
    for i = 0, 5 do
        if party:GetMemberIsActive(i) ~= 0 and party:GetMemberServerId(i) ~= 0
           and party:GetMemberZone(i) == zone then
            count = count + 1
        end
    end
    return count
end

-- Hide or combine the timers of other party members hit by our AoE buffs
local function ApplyPartyOptions(bars)
    if PartyOptions.show and not PartyOptions.combine then return bars end

    local self_id = AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0)
    local party_size = GetPartySize()

    -- Group AoE timers by buff and name, one per member.  Casts landing a little apart
    -- still group; the combined timer shows whoever has the least time left.
    local groups = T{}
    local seen = T{}
    for _, b in ipairs(bars) do
        if b.aoe and b.active then
            local g_key = ('%s:%s'):fmt(b.icon_id, b.filter_name)
            local m_key = g_key .. ':' .. tostring(b.target_id)
            groups[g_key] = groups[g_key] or T{}
            if not seen[m_key] then
                seen[m_key] = true
                table.insert(groups[g_key], b)
            end
            b.g_key = g_key
        end
    end

    local out = T{}
    local combined = T{}
    for _, b in ipairs(bars) do
        local group = b.g_key and groups[b.g_key]
        if PartyOptions.combine and group and party_size > 1 and #group >= party_size then
            -- The whole party has it, show one timer using the shortest one left
            if not combined[b.g_key] then
                combined[b.g_key] = true
                local first = group[1]
                for _, g in ipairs(group) do
                    if g.remains < first.remains then first = g end
                end
                table.insert(out, { name=('%s (Party)'):fmt(first.filter_name), duration=first.duration,
                                    remains=first.remains, key='party' .. b.g_key, icon_id=first.icon_id,
                                    filter_name=first.filter_name, start_time=first.start_time,
                                    target='Party' })
            end
        elseif PartyOptions.show or not b.aoe or b.target_id == self_id then
            table.insert(out, b)
        end
    end

    return out
end

local function UpdateBuffs(timers)
    local bars = T{}

    for p_id, data in pairs(buffs.buffs) do
        for id, effect in pairs(data.effects) do
            for k, v in pairs(effect) do
                local t_entity = GetEntity(v.t_index)
                local a_entity = GetEntity(v.a_index)

                local timer_name = v.name
                -- t_entity is nil while the target is out of range or in another zone
                if t_entity and t_entity.ServerId ~= (a_entity and a_entity.ServerId) then
                    timer_name = ("%s (%s)"):fmt(v.name, t_entity.Name)
                end

                local diff = ((ashita.time.clock()['ms'] - v.o_time) / 1000.0) * 60.0
                local remains = v.duration - diff
                if remains <= -OVERDUE_LIMIT then
                    -- Expired (or ran past its estimated duration) more than 5 seconds ago
                    buffs.buffs[p_id].effects[id][k] = nil
                else
                    local e = AshitaCore:GetMemoryManager():GetEntity()
                    if bit.band(e:GetRenderFlags0(v.t_index), 0x200) == 0x200 then
                        v.ttl = -1
                        table.insert(bars, { name=timer_name, duration=v.duration, remains=remains,
                                             key=v.t_index .. id, icon_id=id, filter_name=v.name,
                                             start_time=(v.c_time or v.o_time),
                                             target=(t_entity and t_entity.Name) or '',
                                             aoe=v.aoe, active=(v.duration > -1), o_time=v.o_time,
                                             target_id=p_id })
                    else
                        if v.ttl == -1 then v.ttl = ashita.time.clock()['s'] end
                        if ashita.time.clock()['s'] - v.ttl > 600 then
                            buffs.buffs[p_id].effects[id][k] = nil
                        end
                    end
                end
            end
        end
    end

    -- bars come from pairs(), whose order can change between frames, so give the
    -- unsorted (Default) mode a fixed order: cast time, then name
    table.sort(bars, function(a, b)
        if a.start_time ~= b.start_time then return a.start_time < b.start_time end
        return a.name < b.name
    end)

    timers:render(ApplyPartyOptions(bars))
end

local function ShowPartyBuffs(show, combine)
    PartyOptions.show = (show ~= false)
    PartyOptions.combine = (combine == true)
end

-- Names offered by the Durations filter tab's search box
local function GetCatalog()
    local extra = { 'Double-Up Chance' }
    local res = AshitaCore:GetResourceManager()
    pcall(function()
        for i = 1, 1023 do
            local n = res:GetString('buffs.names', i)
            if n and n ~= '' then table.insert(extra, n) end
        end
    end)
    return BuildNameCatalog(false, extra)
end

buffs.GetCatalog = GetCatalog
buffs.Update = UpdateBuffs
buffs.HandlePacket = HandlePacket
buffs.SyncBuffs = SyncBuffs
buffs.ShowPartyBuffs = ShowPartyBuffs

return buffs

