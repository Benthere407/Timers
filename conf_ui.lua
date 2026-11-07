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

-- The settings window: a Vanacore-style menu from the vcmenu library (vcmenu.lua in this folder;
-- master copy in Documents/vcmenu).  Pages in a sidebar: About, Theme, one group of pages per
-- panel (Layout, Bars, Text, Icons, Filters), Filter Sets, and a Test tool.

require('common')

local helpers = require('helpers')
local imgui   = require('imgui')
local vc      = require('vcmenu')
local yuna    = require('theme_yuna')
local themes  = require('themes')

local C = vc.colors

math.randomseed(os.time())

local win = vc.new_state('recasts.layout')

local ui = T{
    is_open = win.open,   -- /timers toggles this
    testing = false,
    timers  = nil,        -- the addon's timers table (set every frame by render_config_ui)
}

-- The three panels.  key: the field in the timers table (timers.recasts, timers.buffs, timers.debuffs)
local PANELS = {
    { id = 'recasts',   label = 'Recasts',   icon = 'refresh', key = 'recasts' },
    { id = 'durations', label = 'Durations', icon = 'star',    key = 'buffs'   },
    { id = 'debuffs',   label = 'Debuffs',   icon = 'stop',    key = 'debuffs' },
}

local SUBPAGES = {
    { 'layout',  'Layout'  },
    { 'bars',    'Bars'    },
    { 'text',    'Text'    },
    { 'icons',   'Icons'   },
    { 'filters', 'Filters' },
}

local SORTS = { { 0, 'Added' }, { 1, 'Time left' }, { 2, 'Cast order' }, { 3, 'Target' } }

-- The panel's timer group and its panel settings (locked, party buffs, ...)
local function group_of(p) return ui.timers[p.key].timers end
local function panel_of(p) return ui.timers[p.key].settings end

--------------------------------------------------------------------------------
-- Rows: a label on the left, its control lined up at the right
--------------------------------------------------------------------------------
local SLIDER_W = 220

local function tip(t)
    if t and imgui.IsItemHovered() then imgui.SetTooltip(t) end
end

-- Text width at 100% (vcmenu scales the widths it is given)
local function text_w(s) return (vc.xy(imgui.CalcTextSize(s))) / vc.scale() end

local function switch(id, label, v, help)
    local nv = vc.switch_row(id, label, v == true)
    tip(help)
    return nv
end

-- Returns the new value while dragged, else nil
local function slider(id, label, v, lo, hi, step, fmt, help)
    vc.label_row(label, SLIDER_W + 64)
    local nv = vc.slider(id, v, lo, hi, step, fmt, SLIDER_W)
    tip(help)
    if nv ~= nil and step and step >= 1 then nv = math.floor(nv + 0.5) end
    return nv
end

local COLOR_FLAGS = bit.bor(ImGuiColorEditFlags_NoInputs or 0, ImGuiColorEditFlags_AlphaBar or 0,
                            ImGuiColorEditFlags_AlphaPreviewHalf or 0)

-- An ARGB colour (the primitives' format).  Returns the new colour when changed, else nil
local function color_argb(id, label, u, help)
    vc.label_row(label, 24)
    local c = helpers.color_u32_to_v4(u)
    local changed = imgui.ColorEdit4('##col_' .. id, c, COLOR_FLAGS)
    tip(help)
    if changed then return helpers.color_v4_to_u32(c) end
    return nil
end

-- An { r, g, b } colour (the YunaUI theme's format), changed in place
local function color_rgb(id, label, t, help)
    vc.label_row(label, 24)
    local c = { t[1], t[2], t[3] }
    if imgui.ColorEdit3('##col_' .. id, c, ImGuiColorEditFlags_NoInputs or 0) then
        t[1], t[2], t[3] = c[1], c[2], c[3]
    end
    tip(help)
end

local function seg_w(opts)
    local w = 0
    for _, o in ipairs(opts) do w = w + text_w(o[2]) + 12 end
    return w + 2
end

-- A drop-down: items = { { value, 'Label' }, ... } (an item { sep = 'CAPTION' } starts a group).
-- cur shows as chosen (nil: placeholder).  Returns the picked value, else nil.
local COMBO_W = 220
local function combo_row(id, label, items, cur, help, placeholder)
    vc.label_row(label, COMBO_W)
    local shown = placeholder or 'Choose...'
    for _, it in ipairs(items) do
        if not it.sep and it[1] == cur then shown = it[2] end
    end
    local picked = nil
    imgui.PushItemWidth(vc.z(COMBO_W))
    if imgui.BeginCombo('##cb_' .. id, shown) then
        for i, it in ipairs(items) do
            if it.sep then
                imgui.Separator()
                imgui.TextColored(C.mute, it.sep)
            elseif imgui.Selectable(it[2] .. '##cbi_' .. id .. i, it[1] == cur) then
                picked = it[1]
            end
        end
        imgui.EndCombo()
    end
    imgui.PopItemWidth()
    tip(help)
    return picked
end

local function seg_row(id, label, opts, cur, help)
    vc.label_row(label, seg_w(opts))
    local pick = vc.seg(id, opts, cur)
    tip(help)
    return pick
end

--------------------------------------------------------------------------------
-- Looks (themes.lua): the Bars, Text and Icons pages edit the look of the theme the panel uses;
-- the layout is the panel's own.  A built-in theme never changes: changing one of its settings
-- makes a custom theme from it, which every panel using it moves to.
--------------------------------------------------------------------------------
local function copy(v) return (type(v) == 'table') and table.table_copy(v) or v end

local function theme_label(g) return themes.label(g.settings.theme or 'default') end

-- Put these look settings back to the base theme's
local function reset_look(s, base, keys)
    local d = themes.defaults(base)
    for _, k in ipairs(keys) do s[k] = copy(d[k]) end
end

-- Draws a look page: fn(p, g, s, base) edits look s.  On a built-in theme it edits a copy, and if
-- anything changed, a custom theme is made from the built-in one with that change.
local gForked = nil   -- the custom theme just made (for the page's note)
local function edit_look(p, fn)
    local g = group_of(p)
    local s, base, e = themes.look(g)
    if e then
        fn(p, g, s, base)
        return
    end
    local scratch = copy(s)
    fn(p, g, scratch, base)
    if not themes.equal(scratch, s) then
        local ne = themes.fork(g)
        ne.panels[p.id] = scratch
        gForked = ne.name
    end
end

-- Put these layout settings (shared by both themes) back to their defaults
local function reset_layout(g, keys)
    local d = TimerGroup:default_settings()
    for _, k in ipairs(keys) do g.settings[k] = copy(d[k]) end
end

local function theme_note(g)
    local _, base, e = themes.look(g)
    if e then
        if gForked == e.name then
            imgui.TextColored(C.good, ('Made "%s" from %s, so %s stays as it was. Every panel that used %s now uses it.')
                :format(e.name, themes.label(base), themes.label(base), themes.label(base)))
        end
        vc.note(('These are this panel\'s settings in your theme "%s" (based on %s). It is saved as you change it; rename or delete it on the Theme page.')
            :format(e.name, themes.label(base)))
    else
        vc.note(('This panel uses the built-in %s theme, which never changes. Change anything here and a custom theme, "%s (custom)", is made from it for every panel using %s.')
            :format(themes.label(base), themes.label(base), themes.label(base)))
    end
end

--------------------------------------------------------------------------------
-- Panel pages
--------------------------------------------------------------------------------

-- Copy this panel's look to one or both of the others (asks first: it overwrites theirs)
local gCopy = { from = nil, to = nil, done_for = nil, msg = '' }
local gCopyColors = true   -- also give the others this panel's YunaUI bar colour

-- Copies a panel's look to another: its theme and layout, its look in a custom theme, and (with
-- gCopyColors) its main bar colour as every type colour of the other
local function copy_panel_look(from, to)
    local gf, gt = group_of(from), group_of(to)
    gf:copy_look_to(gt)                                 -- (the theme and the layout)
    local s, base, e = themes.look(gf)
    if e then e.panels[to.id] = copy(s) end

    if not (gCopyColors and yuna.is_theme(base)) then return end
    local c = s.kinds[yuna.PANEL_KIND[from.id]]
    if c == nil then return end
    local tl, _, te = themes.look(gt)
    local same = true
    for _, k in ipairs(yuna.KIND_LABELS[to.id] or {}) do
        if not themes.equal(tl.kinds[k[1]], { c[1], c[2], c[3] }) then same = false end
    end
    if same then return end
    if not te then te = themes.fork(gt) end             -- (a built-in theme: a custom one made from it)
    for _, k in ipairs(yuna.KIND_LABELS[to.id] or {}) do
        te.panels[to.id].kinds[k[1]] = { c[1], c[2], c[3] }
    end
end

local function copy_section(p)
    vc.section('COPY THIS LOOK')
    local others = {}
    for _, o in ipairs(PANELS) do
        if o ~= p then others[#others + 1] = o end
    end

    if gCopy.from == p.id then
        local names = {}
        for _, o in ipairs(gCopy.to) do names[#names + 1] = o.label end
        local list = table.concat(names, ' and ')
        imgui.TextColored(C.gold, ('Replace the look of %s with %s\'s?'):format(list, p.label))
        if vc.button('Yes, copy##cpy_yes_' .. p.id, 'primary', 100) then
            for _, o in ipairs(gCopy.to) do copy_panel_look(p, o) end
            gCopy = { from = nil, to = nil, done_for = p.id, msg = ('Copied to %s.'):format(list) }
        end
        imgui.SameLine()
        if vc.button('Cancel##cpy_no_' .. p.id, nil, 80) then gCopy.from = nil end
    else
        for _, o in ipairs(others) do
            if vc.button(('To %s##cpy_%s_%s'):format(o.label, p.id, o.id), nil, 120) then
                gCopy = { from = p.id, to = { o }, done_for = nil, msg = '' }
            end
            imgui.SameLine()
        end
        if vc.button('To both##cpy_both_' .. p.id, nil, 90) then
            gCopy = { from = p.id, to = others, done_for = nil, msg = '' }
        end
        if gCopy.done_for == p.id and gCopy.msg ~= '' then
            imgui.SameLine(0, 16)
            pcall(imgui.AlignTextToFramePadding)
            imgui.TextColored(C.good, gCopy.msg)
        end
    end
    local v = switch('cpycol_' .. p.id, 'Bar colours too', gCopyColors,
        ('YunaUI colours bars by type, and each panel has its own (Recasts: abilities, spells, one-hours). On: the others take %s\'s main bar colour. Off: they keep theirs.'):format(p.label))
    if v ~= nil then gCopyColors = v end
    vc.note('Copies the theme and both themes\' looks: sizes, padding, background, bars, text and icons. Each panel keeps its own place, grow direction, sort order, filters and whether it shows.')
end

local function page_layout(p)
    local g, ps, s = group_of(p), panel_of(p), group_of(p).settings
    local D = TimerGroup:default_settings()
    vc.title(p.label, 'Layout')

    copy_section(p)

    vc.section('PANEL', nil, function()
        s.enabled, ps.locked, s.hide_in_menus = true, false, false
        g:set_grow_up(false)
    end)
    local v = switch('en_' .. p.id, 'Show this panel', s.enabled, 'Toggle visibility of the panel.')
    if v ~= nil then s.enabled = v end
    v = switch('lock_' .. p.id, 'Lock its position', ps.locked, 'Stop the panel being dragged with Shift + left mouse.')
    if v ~= nil then ps.locked = v end
    v = switch('grow_' .. p.id, 'Grow upward', s.grow_up, 'On: new timers are added above the panel\'s anchor (it is anchored by its bottom edge). Off: the list grows down from its top edge.')
    if v ~= nil then g:set_grow_up(v) end
    v = switch('menu_' .. p.id, 'Hide while a game menu is open', s.hide_in_menus == true,
        'For plain Ashita, where the game\'s menus can\'t go over addons: the panel hides while one is open (not while you type in chat).')
    if v ~= nil then s.hide_in_menus = v end
    if rawget(_G, 'vana') then
        vc.note('Under VanaCore the game\'s menus already go over the panels, so this isn\'t needed (unless VanaCore\'s menus.ontop is 0).')
    end
    if s.hide_in_menus == true then
        vc.note(('Game menu open now: %s'):format((gGameMenuName ~= '') and gGameMenuName or 'none'))
    end
    local pick = combo_row('th_' .. p.id, 'Theme', themes.choices(), s.theme or 'default', 'Default: Ashita fonts and bars. The others are described on the Theme page. Each keeps its own bar, text and icon settings.')
    if pick ~= nil then s.theme = pick end

    if p.id == 'recasts' then
        vc.section('ORDER')
        vc.note('Recasts are always sorted by time left, the longest at the bottom.')
    else
        vc.section('ORDER', nil, function() reset_layout(g, { 'sort_mode', 'sort_reverse' }) end)
        pick = seg_row('sort_' .. p.id, 'Sort by', SORTS, s.sort_mode or 0,
            'Added: the order timers were made. Time left: shortest at the top. Cast order: oldest at the top. Target: grouped by target name. Works the same whichever way the panel grows.')
        if pick ~= nil then s.sort_mode = pick end
        v = switch('rev_' .. p.id, 'Reverse the order', s.sort_reverse, 'Flip the sort (no effect on Added).')
        if v ~= nil then s.sort_reverse = v end
    end

    if p.id == 'durations' then
        vc.section('PARTY BUFFS', nil, function() ps.party_buffs, ps.party_buffs_combine = true, true end)
        v = switch('aoe_' .. p.id, 'Timers for party members', ps.party_buffs, 'Show timers for other party members hit by your AoE buffs. Your own timer is always shown.')
        if v ~= nil then ps.party_buffs = v end
        v = switch('comb_' .. p.id, 'Combine into one (Party) timer', ps.party_buffs_combine, 'When your whole party has the same AoE buff, show one "(Party)" timer instead of one per member.')
        if v ~= nil then ps.party_buffs_combine = v end
    end

    vc.section('SIZE', nil, function() reset_layout(g, { 'max_height', 'bar_width', 'stretch' }) end)
    local n = slider('maxh_' .. p.id, 'Max height', s.max_height, 20, 1000, 1, '%d px', 'The tallest the panel gets; timers that don\'t fit are left off.')
    if n then s.max_height = n end
    n = slider('barw_' .. p.id, 'Row width', s.bar_width, 40, 1000, 1, '%d px', 'Width of each timer\'s row: its name, time and bar (the bar\'s own length is on the Bars page).')
    if n then s.bar_width = n end
    n = slider('str_' .. p.id, 'Stretch', s.stretch or 0, -300, 600, 1, '%d px', 'Makes the panel longer or shorter by the bar alone: the name stays where it is, the countdown moves with the bar\'s end, and the gaps between them stay the same.')
    if n then s.stretch = n end

    vc.section('BACKGROUND', nil, function()
        reset_layout(g, { 'enable_background', 'padding' })
        g.bg.color = D.background.color
        g.bg.border_visible = D.background.border_visible
        g.bg.border_color = D.background.border_color
        s.background.border_sizes = D.background.border_sizes
        g.bg.border_sizes = D.background.border_sizes
    end)
    v = switch('bg_' .. p.id, 'Show a background', s.enable_background, 'Toggle the panel\'s background.')
    if v ~= nil then s.enable_background = v end
    local ls, lbase = themes.look(g)
    local st = yuna.STYLE[lbase]
    if st then
        if st.frame and ls.frame then
            vc.note(('With %s the background is drawn as its frame (colour, border and menu lines below are for the plain background). Change that on its Bars page.'):format(st.label))
        end
    end
    local c = color_argb('bg_' .. p.id, 'Background colour', g.bg.color)
    if c then g.bg.color = c end
    local pad = s.padding
    for i, side in ipairs({ 'Left', 'Top', 'Right', 'Bottom' }) do
        n = slider(('pad%d_%s'):format(i, p.id), 'Padding ' .. side:lower(), pad[i], 0, 50, 1, '%d px',
                   'Space between the background\'s edge and the timers.')
        if n then pad[i] = n end
    end
    v = switch('bord_' .. p.id, 'Border', g.bg.border_visible, 'Toggle the border round the panel\'s background.')
    if v ~= nil then g.bg.border_visible = v end
    c = color_argb('bordc_' .. p.id, 'Border colour', g.bg.border_color)
    if c then g.bg.border_color = c end
    local size = tonumber(tostring(s.background.border_sizes):match('^(%d+)')) or 1
    n = slider('bords_' .. p.id, 'Border size', size, 1, 10, 1, '%d px')
    if n then
        s.background.border_sizes = ('%d,%d,%d,%d'):fmt(n, n, n, n)
        g.bg.border_sizes = s.background.border_sizes
    end

    local mbg = g:get_menu_bg()
    vc.section('MENU STYLE', nil, function()
        g:reset_menu_bg_colors()
        mbg.enabled = D.menu_bg.enabled
    end)
    v = switch('mbg_' .. p.id, 'FFXI menu lines', mbg.enabled, 'Draw the background as alternating light and dark lines that fade from the top colours to the bottom ones, like the game\'s menus. Drawn over the background colour (set its alpha to 0 for lines only). Needs the background on.')
    if v ~= nil then mbg.enabled = v end
    n = slider('mbgt_' .. p.id, 'Line thickness', mbg.thickness, 1, 8, 1, '%d px', 'Very tall panels use thicker lines automatically.')
    if n then mbg.thickness = n end
    n = slider('mbgo_' .. p.id, 'Opacity', mbg.opacity, 0, 100, 1, '%d%%')
    if n then mbg.opacity = n end
    for _, e in ipairs({ { 'light_top', 'Light line, top' }, { 'light_bottom', 'Light line, bottom' },
                         { 'dark_top', 'Dark line, top' }, { 'dark_bottom', 'Dark line, bottom' } }) do
        c = color_argb(e[1] .. '_' .. p.id, e[2], mbg[e[1]])
        if c then mbg[e[1]] = c end
    end
end

local function page_bars(p, g, s, base)
    local y = yuna.is_theme(base)
    vc.title(p.label, 'Bars')
    theme_note(g)

    vc.section('BAR', nil, function() reset_look(s, base, { 'bar_height', 'bar_length', 'bar_offset_x', 'bar_offset_y', 'row_gap', 'bar_border_visible', 'bar_border_color' }) end)
    local n = slider('barh_' .. p.id, 'Height', s.bar_height, y and 2 or 1, y and 20 or 50, 1, '%d px', 'Height of each timer bar.')
    if n then s.bar_height = n end
    n = slider('barl_' .. p.id, 'Length', s.bar_length or 100, 10, 150, 1, '%d%%', 'The bar\'s length, as a share of the row (the row\'s width is the Layout page\'s Row width). The name and time stay where they are.')
    if n then s.bar_length = n end
    n = slider('barx_' .. p.id, 'Offset X', s.bar_offset_x or 0, -100, 100, 1, '%d px', 'Moves the bar left or right in its row.')
    if n then s.bar_offset_x = n end
    n = slider('bary_' .. p.id, 'Offset Y', s.bar_offset_y or 0, -30, 30, 1, '%d px', 'Moves the bar up or down in its row (up to run it through the text).')
    if n then s.bar_offset_y = n end
    n = slider('ygap_' .. p.id, 'Row spacing', s.row_gap or 0, -20, 16, 1, '%d px', 'Space between one timer and the next. Below 0 the rows close up and can overlap.')
    if n then s.row_gap = n end
    local v = switch('bb_' .. p.id, 'Border', s.bar_border_visible, 'The border drawn round each bar.')
    if v ~= nil then s.bar_border_visible = v end
    local c = color_argb('bbc_' .. p.id, 'Border colour', s.bar_border_color)
    if c then s.bar_border_color = c end

    if y then
        local st = yuna.STYLE[base]
        vc.section(st.label:upper(), nil, function() reset_look(s, base, { 'effects', 'dot_blink', 'frame', 'bar_end' }) end)
        local fx_help = (st.bar == 'thin') and 'The halo round the dot at the bar\'s end breathes.'
                     or (st.bar == 'plate' or st.bar == 'classic') and 'A soft glow round the bar.'
                     or 'The colours flowing along the bar, its breathing glow and the sheen that sweeps along it.'
        v = switch('yfx_' .. p.id, 'Bar effects', s.effects, fx_help)
        if v ~= nil then s.effects = v end
        if st.bar == 'thin' then
            v = switch('ydb_' .. p.id, 'Dot blinks near the end', s.dot_blink, 'The white dot at the bar\'s end blinks with the countdown in the last 10 seconds (and when a recast is about to come back).')
            if v ~= nil then s.dot_blink = v end
        end
        if st.frame then
            v = switch('yfr_' .. p.id, 'Background as the theme\'s frame', s.frame, 'When the background is on (Layout page), draw it as: ' .. ({ plate = 'A dark plate with a fine light edge, as Vex\'s HP / MP bars.',
                vex = 'Dark glass with a faint violet edge, as the Damage Meter.', hex = 'Square, cut corners and a gold edge, as Hex link.',
                ffxi = 'The game\'s blue menu window with its light edge.' })[st.frame])
            if v ~= nil then s.frame = v end
        end
        if st.fade == 'end' then
            color_rgb('ybe_' .. p.id, 'Bars fade to', s.bar_end, 'Every bar runs from its colour on the left to this colour.')
        end
    end

    -- Bar colours: by type (the type colours) or by time left (the thresholds and their colours),
    -- one or the other.  The Default theme colours by time left only.
    local by_time = (not y) or s.color_mode == 'time'
    vc.section('BAR COLOURS', nil, function() reset_look(s, base, y and { 'color_mode', 'kinds', 'thresholds', 'colors' } or { 'thresholds', 'colors' }) end)
    if y then
        local pick = seg_row('ycm_' .. p.id, 'Colour the bars', { { 'type', 'By type' }, { 'time', 'By time left' } }, s.color_mode,
            'By type: each kind of timer its own colour. By time left: the colour changes as the time left drops past each threshold.')
        if pick ~= nil then s.color_mode = pick; by_time = (pick == 'time') end
    end

    if not by_time then
        for _, e in ipairs(yuna.KIND_LABELS[p.id] or {}) do
            color_rgb('yk_' .. p.id .. e[1], e[2], s.kinds[e[1]])
        end
        return
    end

    vc.note('The bar changes colour as its time left drops past each threshold.')
    for _, e in ipairs({ { 't75', 'T1' }, { 't50', 'T2' }, { 't25', 'T3' } }) do
        n = slider(e[1] .. '_' .. p.id, e[2], s.thresholds[e[1]], 0, 600, 1, '%d s', 'Seconds left.')
        if n then s.thresholds[e[1]] = n end
    end
    local t = s.thresholds
    for _, e in ipairs({ { 'color100', ('More than T1 (%ds)'):format(t.t75) }, { 'color75', ('More than T2 (%ds)'):format(t.t50) },
                         { 'color50', ('More than T3 (%ds)'):format(t.t25) }, { 'color25', ('Less than T3 (%ds)'):format(t.t25) } }) do
        c = color_argb(e[1] .. '_' .. p.id, e[2], s.colors[e[1]])
        if c then s.colors[e[1]] = c end
    end
end

local function page_text(p, g, s, base)
    local y = yuna.is_theme(base)
    vc.title(p.label, 'Text')
    theme_note(g)

    vc.section('FONT', nil, function() reset_look(s, base, { 'font_family', 'font_height', 'font_bg_visible' }) end)
    vc.label_row('Font family', 200)
    imgui.PushItemWidth(vc.z(200))
    local buf = { s.font_family }
    if imgui.InputText('##ff_' .. p.id, buf, 64) then s.font_family = buf[1] end
    imgui.PopItemWidth()
    if y then
        tip('A font file in this addon\'s fonts folder or in Windows\\Fonts, e.g. segoeui.ttf. Loads under VanaCore.')
    end
    local n = slider('fs_' .. p.id, 'Size', s.font_height, y and 10 or 1, y and 36 or 20, 1, '%d px')
    if n then s.font_height = n end
    local v = switch('fbg_' .. p.id, 'Text background', s.font_bg_visible, 'A background behind the text.')
    if v ~= nil then s.font_bg_visible = v end

    local keys = { 'name_font_color', 'name_outline_color', 'time_font_color', 'time_outline_color', 'font_bg_color' }
    if y then keys[#keys + 1] = 'time_bar_color' end
    vc.section('COLOURS', nil, function() reset_look(s, base, keys) end)
    if y then
        v = switch('tbc_' .. p.id, 'Countdown in the bar\'s colour', s.time_bar_color, 'YunaUI\'s look. Off: the Countdown colour below.')
        if v ~= nil then s.time_bar_color = v end
    end
    for _, e in ipairs({ { 'name_font_color', 'Name' }, { 'name_outline_color', 'Name outline' },
                         { 'time_font_color', 'Countdown' }, { 'time_outline_color', 'Countdown outline' },
                         { 'font_bg_color', 'Text background' } }) do
        local c = color_argb(e[1] .. '_' .. p.id, e[2], s[e[1]])
        if c then s[e[1]] = c end
    end

    local ALIGN = { { 'left', 'Left' }, { 'center', 'Centre' }, { 'right', 'Right' } }
    vc.section('ALIGNMENT', nil, function() reset_look(s, base, { 'name_align', 'time_align' }) end)
    local pick = seg_row('nal_' .. p.id, 'Name', ALIGN, s.name_align or 'left', 'Where the name sits in its row. The offsets below move it from there.')
    if pick ~= nil then s.name_align = pick end
    pick = seg_row('tal_' .. p.id, 'Countdown', ALIGN, s.time_align or 'right', 'Where the countdown sits in its row. The offsets below move it from there.')
    if pick ~= nil then s.time_align = pick end

    vc.section('NAME OFFSET', nil, function() reset_look(s, base, { 'name_font_offset_x', 'name_font_offset_y' }) end)
    n = slider('nx_' .. p.id, 'X', s.name_font_offset_x, -250, 250, 1, '%d px')
    if n then s.name_font_offset_x = n end
    n = slider('ny_' .. p.id, 'Y', s.name_font_offset_y, -250, 250, 1, '%d px')
    if n then s.name_font_offset_y = n end

    vc.section('COUNTDOWN OFFSET', nil, function() reset_look(s, base, { 'timer_font_offset_x', 'timer_font_offset_y' }) end)
    n = slider('tx_' .. p.id, 'X', s.timer_font_offset_x, -250, 250, 1, '%d px')
    if n then s.timer_font_offset_x = n end
    n = slider('ty_' .. p.id, 'Y', s.timer_font_offset_y, -250, 250, 1, '%d px')
    if n then s.timer_font_offset_y = n end
end

local function page_icons(p, g, s, base)
    local y = yuna.is_theme(base)
    vc.title(p.label, 'Icons')
    theme_note(g)

    vc.section('ICONS', nil, function() reset_look(s, base, { 'enable_icons', 'icon_scale', 'icon_offset_x', 'icon_offset_y' }) end)
    local v = switch('ic_' .. p.id, 'Show icons', s.enable_icons, 'The status icon beside each timer (recasts use the icon of a status with the same name, when there is one).')
    if v ~= nil then s.enable_icons = v end
    local n = slider('isc_' .. p.id, 'Scale', s.icon_scale, y and 0.3 or 0.1, y and 1.5 or 1.0, 0.01, '%.2f',
                     y and 'Of the row\'s height (1.00: as tall as the name and its bar).' or nil)
    if n then s.icon_scale = n end
    n = slider('ix_' .. p.id, 'X offset', s.icon_offset_x, -50, 50, 1, '%d px')
    if n then s.icon_offset_x = n end
    n = slider('iy_' .. p.id, 'Y offset', s.icon_offset_y, -50, 50, 1, '%d px')
    if n then s.icon_offset_y = n end
end

-- Filters --------------------------------------------------------------------

local gCatalogs = {}
local gSearch   = {}
local gView     = {}
local gCache    = {}
local VIEW_ACTIVE = 3   -- the timers the panel has right now
local VIEWS     = { { 0, 'All' }, { VIEW_ACTIVE, 'Active' }, { 1, 'Shown' }, { 2, 'Hidden' } }

-- Names (spells/abilities/effects) the filter list offers for each panel.  Built once.
local function get_catalog(name)
    if gCatalogs[name] == nil then
        local ok, list = pcall(function()
            if name == 'recasts' then
                return gRecast.GetCatalog()
            elseif name == 'durations' then
                return gBuff.GetCatalog()
            else
                return gDebuff.GetCatalog()
            end
        end)
        gCatalogs[name] = (ok and list) or {}
    end
    return gCatalogs[name]
end

local function filter_names(group, name, query, view, f)
    -- Active: the names running on the panel right now, shown or hidden (they change every
    -- frame, so this list isn't cached; it is short)
    if view == VIEW_ACTIVE then
        local names, set = {}, {}
        for k, n in pairs(group.live or {}) do
            if query == '' or k:find(query, 1, true) then
                set[k] = true
                names[#names + 1] = n
            end
        end
        table.sort(names, function(a, b) return a:lower() < b:lower() end)
        return { names = names, set = set }
    end

    -- Rebuild the (sorted) list only when something that affects it changed
    local seen_count = 0
    for _ in pairs(group.seen) do seen_count = seen_count + 1 end
    local key = table.concat({ query, view, tostring(f.only_checked), group.filter_version or 0, seen_count }, '|')

    local cache = gCache[name]
    if cache == nil or cache.key ~= key then
        local names, set = {}, {}
        local function add(n)
            n = tostring(n)
            local k = n:lower()
            if set[k] then return end
            if query ~= '' and not k:find(query, 1, true) then return end
            if view ~= 0 then
                local vis = group:is_name_visible(n)
                if (view == 1 and not vis) or (view == 2 and vis) then return end
            end
            set[k] = true
            table.insert(names, n)
        end

        -- Everything the game knows about, plus anything seen/configured that isn't in it
        for _, n in ipairs(get_catalog(name)) do add(n) end
        for _, n in pairs(group.seen) do add(n) end
        for _, n in ipairs(f.show) do add(n) end
        for _, n in ipairs(f.hide) do add(n) end

        table.sort(names, function(a, b) return a:lower() < b:lower() end)
        cache = { key = key, names = names, set = set }
        gCache[name] = cache
    end
    return cache
end

local function page_filters(p)
    local g, name = group_of(p), p.id
    local f = g:get_filter()
    vc.title(p.label, 'Filters')

    vc.section('MODE')
    local v = switch('only_' .. name, 'Only show checked items', f.only_checked, 'Off: everything shows except the items you hide. On: only the items you show are shown.')
    if v ~= nil then f.only_checked = v end
    if vc.button('Show all##fa_' .. name, nil, 90) then g:reset_filter(false) end
    tip('Reset the list and show everything.')
    imgui.SameLine()
    if vc.button('Hide all##fh_' .. name, nil, 90) then g:reset_filter(true) end
    tip('Reset the list and hide everything; then show the items you want.')

    gSearch[name] = gSearch[name] or { '' }
    gView[name] = gView[name] or 0
    local raw   = tostring(gSearch[name][1] or ''):gsub('\0', '')
    local query = raw:lower()
    local cache = filter_names(g, name, query, gView[name], f)
    local names = cache.names

    vc.section('ITEMS', ('%d item%s'):format(#names, #names == 1 and '' or 's'))
    vc.search_box('##fs_' .. name, gSearch[name], 'Search names', 240)
    vc.right(seg_w(VIEWS))
    local pick = vc.seg('fv_' .. name, VIEWS, gView[name])
    tip('All: everything. Active: the timers this panel has right now (hidden ones too). Shown / Hidden: by filter.')
    if pick ~= nil then gView[name] = pick end
    imgui.Dummy({ 1, 2 })

    local active = (gView[name] == VIEW_ACTIVE)
    local can_add = not active and query ~= '' and not cache.set[query] and #raw > 0
    vc.list('##fl_' .. name, can_add and 40 or 4, function()
        local n = #names
        if n == 0 then
            imgui.TextColored(C.mute, active and ((query ~= '') and 'No active timers match.' or 'No timers on this panel right now.')
                                             or 'No items match.')
            return
        end
        -- Only the rows in view are drawn; the rest are spacers (the catalog has thousands)
        local ROW_H = vc.row_height()
        local sy = 0
        pcall(function() sy = imgui.GetScrollY() end)
        local _, vh = vc.xy(imgui.GetWindowSize())
        local first = math.max(1, math.floor(sy / ROW_H) + 1)
        local last  = math.min(n, first + math.ceil(vh / ROW_H) + 1)
        if first > 1 then imgui.Dummy({ 1, (first - 1) * ROW_H }) end
        for i = first, last do
            local nm = names[i]
            local vis = g:is_name_visible(nm)
            if vc.row('##fr_' .. name .. '_' .. i, { no_icon = true, name = nm, dim = not vis,
                    right = vis and 'Shown' or 'Hidden', right_col = vis and C.good or C.bad }) then
                g:set_name_visible(nm, not vis)
            end
        end
        if last < n then imgui.Dummy({ 1, (n - last) * ROW_H }) end
    end)

    if can_add then
        if vc.button(('Add "%s"##fadd_%s'):format(raw, name), 'primary') then
            g:set_name_visible(raw, true)
        end
        tip('Add this exact name even though it isn\'t in the list.')
    end
end

local SUB_DRAW = {
    layout  = page_layout,
    bars    = function(p) edit_look(p, page_bars) end,
    text    = function(p) edit_look(p, page_text) end,
    icons   = function(p) edit_look(p, page_icons) end,
    filters = page_filters,
}

--------------------------------------------------------------------------------
-- Theme page
--------------------------------------------------------------------------------
-- The Theme page: each panel's theme, and your custom themes (themes.lua)
local gTh = { pick = nil, name = { '' }, save = { '' }, msg = '', ok = true, confirm = nil }

local function th_say(ok, msg) gTh.ok, gTh.msg = ok, msg end

local function page_theme()
    vc.title('Theme', 'how the panels look')
    local choices = themes.choices()

    vc.section('PANELS', nil, function()
        for _, p in ipairs(PANELS) do group_of(p).settings.theme = 'default' end
    end)
    for _, p in ipairs(PANELS) do
        local s = group_of(p).settings
        local pick = combo_row('tht_' .. p.id, p.label, choices, s.theme or 'default')
        if pick ~= nil then s.theme = pick end
    end
    local all = combo_row('tht_all', 'All panels', choices, nil, 'Give every panel this theme.', 'Choose a theme...')
    if all ~= nil then
        for _, p in ipairs(PANELS) do group_of(p).settings.theme = all end
    end
    local start = combo_row('tht_start', 'Start with', choices, themes.start or 'default',
        'The theme every character\'s panels start with: new characters, and any still on Default. A character that picks its own theme keeps it. Default: no start theme.')
    if start ~= nil then
        local ok, err = themes.set_start(start)
        th_say(ok, ok and ((start == 'default') and 'No start theme.' or ('Characters start with "%s".'):format(themes.label(start)))
                      or ('Could not save it: %s'):format(tostring(err)))
    end

    local names = themes.names()
    vc.section('YOUR THEMES', ('%d'):format(#names))
    vc.note('The built-in themes never change. Change any bar, text or icon setting while a panel uses one, and a custom theme is made from it ("Classic (custom)") for every panel using it. Custom themes are files in this addon\'s themes folder, saved as you change them, so every character can use them.')

    -- Save as: the look the panels have now, as a new theme with this name, which they then use
    vc.label_row('Save as', COMBO_W + 108)
    imgui.PushItemWidth(vc.z(COMBO_W))
    imgui.InputText('##th_save', gTh.save, 48)
    imgui.PopItemWidth()
    tip('Type a name, then Save: the panels\' look now (each panel\'s bars, text and icons) becomes a theme of yours with that name, and every panel uses it. Letters, numbers, spaces and - _ . ( ) only.')
    imgui.SameLine()
    if vc.button('Save##th_save_btn', 'primary', 100) then
        local name = themes.clean_name(gTh.save[1])
        if name == '' then
            th_say(false, 'Type a name for the theme first.')
        elseif themes.custom[name] then
            th_say(false, ('"%s" already exists: pick another name, or rename that one.'):format(name))
        else
            local looks, base = {}, nil
            for _, p in ipairs(PANELS) do
                local look, b = themes.look(group_of(p))
                looks[p.id] = look
                base = base or b
            end
            local ne = themes.create(base or 'default', name, looks)
            for _, p in ipairs(PANELS) do group_of(p).settings.theme = themes.custom_id(ne.name) end
            gTh.pick, gTh.confirm, gTh.name[1], gTh.save[1] = ne.name, nil, ne.name, ''
            th_say(true, ('Saved "%s"; every panel uses it.'):format(ne.name))
        end
    end

    local items = {}
    for _, n in ipairs(names) do items[#items + 1] = { n, n } end
    if gTh.pick and not themes.custom[gTh.pick] then gTh.pick = nil end
    local pick = combo_row('th_pick', 'Theme', items, gTh.pick, nil, (#names > 0) and 'Choose one...' or 'None yet')
    if pick ~= nil then gTh.pick, gTh.confirm, gTh.name[1] = pick, nil, pick end

    local e = gTh.pick and themes.custom[gTh.pick]
    if e then
        local used = {}
        for _, p in ipairs(PANELS) do
            if group_of(p).settings.theme == themes.custom_id(e.name) then used[#used + 1] = p.label end
        end
        vc.stat('Based on', themes.label(e.base))
        vc.stat('Used by', (#used > 0) and table.concat(used, ', ') or 'no panel (on this character)')

        if gTh.confirm == 'del' then
            imgui.TextColored(C.bad, ('Delete "%s"? Its file is removed; panels using it go back to %s.'):format(e.name, themes.label(e.base)))
            if vc.button('Yes, delete##th_del_yes', 'danger', 100) then
                local name = e.name
                local ok, err = themes.delete(name)
                th_say(ok, ok and ('Deleted "%s".'):format(name) or ('Could not delete it: %s'):format(tostring(err)))
                gTh.confirm = nil
                if ok then gTh.pick = nil end
            end
            imgui.SameLine()
            if vc.button('Cancel##th_del_no', nil, 80) then gTh.confirm = nil end
        else
            if vc.button('Use on all panels##th_use', 'primary', 140) then
                for _, p in ipairs(PANELS) do group_of(p).settings.theme = themes.custom_id(e.name) end
                th_say(true, ('Every panel uses "%s".'):format(e.name))
            end
            imgui.SameLine()
            if vc.button('Duplicate##th_dup', nil, 100) then
                local ne = themes.create(e.base, e.name, e.panels)
                gTh.pick, gTh.name[1] = ne.name, ne.name
                th_say(true, ('Made "%s", a copy of "%s".'):format(ne.name, e.name))
            end
            tip('A copy to try changes on: pick it for the panels, then change it.')
            imgui.SameLine()
            if vc.button('Delete##th_del', 'danger', 80) then gTh.confirm = 'del' end

            vc.label_row('Rename to', COMBO_W + 108)
            imgui.PushItemWidth(vc.z(COMBO_W))
            imgui.InputText('##th_name', gTh.name, 48)
            imgui.PopItemWidth()
            tip('Letters, numbers, spaces and - _ . ( ) only.')
            imgui.SameLine()
            if vc.button('Rename##th_ren', nil, 100) then
                local old, new = e.name, themes.clean_name(gTh.name[1])
                local ok, err = themes.rename(old, new)
                th_say(ok, ok and ('Renamed to "%s".'):format(new) or ('Could not rename it: %s'):format(tostring(err)))
                if ok then gTh.pick, gTh.name[1] = new, new end
            end
        end
    end
    if gTh.msg ~= '' then imgui.TextColored(gTh.ok and C.good or C.gold, gTh.msg) end
    if vc.button('Read the themes folder again##th_reload', nil, 220) then
        themes.load_all()
        th_say(true, 'Read the themes folder.')
    end
    tip('For theme files copied in by hand (or changed outside the game).')

    -- Copy to the other client: the button, then a confirmation with Yes clear of where it was
    vc.section('COPY TO YOUR OTHER CLIENT')
    vc.note('Gives every other client logged in on this PC the theme and layout of this one\'s three panels. Filters stay as they are, and a client that isn\'t running isn\'t changed.')
    if gTh.push then
        imgui.TextColored(C.gold, gTh.push_place and 'Replace the other client\'s panel themes, layout and positions? This can\'t be undone.'
                                                  or 'Replace the other client\'s panel themes and layout? This can\'t be undone.')
        if vc.button('Cancel##th_pushx', nil, 210) then gTh.push = nil end
        imgui.SameLine()
        if vc.button('Yes, copy now##th_push2', 'danger', 140) then
            gTh.push = nil
            local ok, err = themes.push(gTh.push_place)
            if not ok then th_say(false, ('Could not copy them: %s'):format(tostring(err))) end
        end
    else
        local v = switch('th_push_place', 'Panel positions too', gTh.push_place == true, 'Also copy where each panel sits, its Max height and which way it grows.')
        if v ~= nil then gTh.push_place = v end
        if vc.button('Copy to other client##th_push', 'primary', 200) then gTh.push = true end
    end
    if themes.pushed then
        if #themes.push_took > 0 then
            imgui.TextColored(C.good, ('Copied to %s.'):format(table.concat(themes.push_took, ', ')))
        else
            imgui.TextColored(C.mute, 'Sent. No other client has answered yet: it needs this version of Timers loaded.')
        end
    end

    vc.section('BUILT-IN THEMES')
    vc.stat('Default', 'Ashita\'s fonts and bars', nil, 110)
    vc.stat('YunaUI', 'YunaUI\'s Timers: thin glowing bars, the time in the bar\'s colour', nil, 110)
    vc.stat('YunaVEXWB', 'Vex mode\'s white HP / blue MP bars, on a dark plate', nil, 110)
    vc.stat('YunaVEXP', 'Vex mode\'s Damage Meter: thin pink-to-violet bars', nil, 110)
    vc.stat('YunaHEX', 'Hex link: gold and azure bars in a gold-edged frame', nil, 110)
    vc.stat('Classic', 'The game\'s blue menu window and square gauges', nil, 110)
    vc.note('A theme is how the bars, text and icons look; each panel\'s Layout page (size, padding, background) stays its own.')
    if not vc.has_fonts() then
        vc.note('The YunaUI fonts (TeX Gyre Adventor, Arial for Classic) load under VanaCore; elsewhere ImGui\'s own font is used.')
    end
end

--------------------------------------------------------------------------------
-- Filter Sets page
--------------------------------------------------------------------------------
local gSetName    = { '' }
local gSelectedSet = nil
local gSetMessage = ''

local function page_sets()
    local groups = {
        recasts   = ui.timers.recasts.timers,
        durations = ui.timers.buffs.timers,
        debuffs   = ui.timers.debuffs.timers,
    }

    vc.title('Filter Sets', 'per-job filters')
    if not gFilterSets.ready() then
        vc.note('Filter sets are not loaded yet.')
        return
    end

    local abbr = gFilterSets.JOB_ABBR
    local cur_job = AshitaCore:GetMemoryManager():GetPlayer():GetMainJob()
    local cur_abbr = abbr[cur_job]

    -- Copy to the other characters: the button, then a confirmation with Yes clear of where it was
    vc.section('COPY TO YOUR OTHER CLIENT')
    vc.note('Adds all your saved sets to your other characters on this PC: right away if logged in, else at their next login. They can then load them here. Their other sets stay, and their current filters don\'t change.')
    if gTh.fs_push then
        imgui.TextColored(C.gold, 'A set there with the same name is replaced. This can\'t be undone.')
        if vc.button('Cancel##fs_pushx', nil, 210) then gTh.fs_push = nil end
        imgui.SameLine()
        if vc.button('Yes, copy now##fs_push2', 'danger', 140) then
            gTh.fs_push = nil
            local ok, err = gFilterSets.push()
            gSetMessage = ok and '' or ('Could not copy them: %s'):format(tostring(err))
        end
    elseif #gFilterSets.data.sets == 0 then
        imgui.TextColored(C.mute, 'No saved sets to copy yet.')
    elseif vc.button('Copy to other client##fs_push', 'primary', 200) then
        gTh.fs_push = true
    end
    if gFilterSets.pushed then
        if #gFilterSets.push_took > 0 then
            imgui.TextColored(C.good, ('Copied to %s.'):format(table.concat(gFilterSets.push_took, ', ')))
        else
            imgui.TextColored(C.mute, 'Sent. No client has answered yet: a logged-in one needs this version of Timers.')
        end
    end

    vc.section('FILTER SETS')
    vc.note('A filter set stores the Recast, Duration and Debuff filters together. Save one per job, bind it to that job, and it is loaded when you change to that job.')
    local v = switch('fs_auto', 'Load on job change', gFilterSets.data.auto_load, 'When your main job changes, load the filter set bound to it (if there is one).')
    if v ~= nil then gFilterSets.set_auto_load(v) end

    vc.section('SAVE')
    vc.label_row('Set name', 220)
    imgui.PushItemWidth(220)
    imgui.InputText('##filterset_name', gSetName, 32)
    imgui.PopItemWidth()
    tip('Saving with the name of an existing set overwrites it.')
    local typed = tostring(gSetName[1] or ''):gsub('\0', '')

    if vc.button('Save current filters##fs_save', 'primary') then
        if typed:gsub('%s', '') ~= '' then
            if gFilterSets.save(typed, groups) then
                gSelectedSet = typed
                gSetMessage = ('Saved "%s".'):format(typed)
            end
        else
            gSetMessage = 'Enter a set name first.'
        end
    end
    if cur_abbr then
        imgui.SameLine()
        if vc.button(('Save as %s and bind to it##fs_savejob'):format(cur_abbr)) then
            if gFilterSets.save(cur_abbr, groups, cur_job) then
                gSelectedSet = cur_abbr
                gSetName[1] = cur_abbr
                gSetMessage = ('Saved "%s" and bound it to %s.'):format(cur_abbr, cur_abbr)
            end
        end
        tip('Save the current filters as a set named after your job, loaded whenever you change to it.')
    end
    if gSetMessage ~= '' then imgui.TextColored(C.dim, gSetMessage) end

    local sets = gFilterSets.list()
    vc.section('SAVED SETS', ('%d set%s'):format(#sets, #sets == 1 and '' or 's'))
    local selected = gSelectedSet and gFilterSets.get(gSelectedSet) or nil
    if selected then
        if vc.button('Load##fs_load', 'primary', 80) then
            gFilterSets.apply(selected, groups)
            gSetMessage = ('Loaded "%s".'):format(tostring(selected.name))
        end
        tip('Replace the current filters with this set.')
        imgui.SameLine()
        if vc.button('Delete##fs_delete', 'danger', 80) then
            gFilterSets.delete(selected.name)
            gSetMessage = ('Deleted "%s".'):format(tostring(selected.name))
            gSelectedSet = nil
            selected = nil
        end
        if selected then
            imgui.SameLine(0, 24)
            pcall(imgui.AlignTextToFramePadding)
            imgui.TextColored(C.dim, 'Load on job')
            imgui.SameLine()
            local job = selected.job or 0
            imgui.PushItemWidth(90)
            if imgui.BeginCombo('##fs_job', (job > 0 and abbr[job]) or 'None') then
                if imgui.Selectable('None', job == 0) then gFilterSets.set_job(selected.name, 0) end
                for i, a in ipairs(abbr) do
                    if imgui.Selectable(a, job == i) then gFilterSets.set_job(selected.name, i) end
                end
                imgui.EndCombo()
            end
            imgui.PopItemWidth()
            tip('Load this set when this becomes your main job. A job can only be bound to one set.')
        end
    else
        vc.note('Pick a set to load it, delete it or bind it to a job.')
    end
    imgui.Dummy({ 1, 2 })

    vc.list('##fs_list', 4, function()
        if #sets == 0 then
            imgui.TextColored(C.mute, 'No saved sets yet.')
            return
        end
        for i, st in ipairs(sets) do
            local job = (st.job and st.job > 0 and abbr[st.job]) or ''
            if vc.row('##fs_row' .. i, { no_icon = true, name = tostring(st.name), right = job, right_col = C.gold,
                                         selected = (gSelectedSet == st.name) }) then
                gSelectedSet = st.name
                gSetName[1] = st.name
                gSetMessage = ''
            end
        end
    end)
end

--------------------------------------------------------------------------------
-- About page
--------------------------------------------------------------------------------
local function page_about()
    vc.title('Timers', 'version ' .. tostring(addon.version))
    vc.section('TIMERS')
    vc.note('Timer bars for your recasts, the buffs you cast (Durations) and the debuffs you land on monsters (Debuffs). Each panel has its own pages in the menu.')
    vc.section('COMMANDS')
    vc.stat('/timers', 'Open or close this window')
    vc.stat('/timers lock', 'Stop the panels being dragged')
    vc.stat('/timers unlock', 'Let them be dragged again')
    vc.stat('Shift + drag', 'Move a panel')
    vc.section('CREDITS')
    vc.note(('By %s. %s'):format(addon.author, addon.link))
    vc.note('The YunaUI theme is based on YunaUI by Yunas - https://github.com/YunasXI/yunaui. Font: TeX Gyre Adventor (GUST Font License, see fonts/).')
    vc.note('The window uses the vcmenu library, inspired by the VanaCore menus by Vekien and Josh.Xero.')
end

--------------------------------------------------------------------------------
-- Test tool: sample timers
--------------------------------------------------------------------------------
local PREVIEW_DATA = {
    recasts = {
        names = { 'Berserk', 'Warcry', 'Haste', 'Stoneskin', 'Provoke', 'Aggressor', 'Defender', 'Flee', 'Meikyo Shisui', 'Blink' },
        kinds = { Haste = 'ma', Stoneskin = 'ma', Blink = 'ma', ['Meikyo Shisui'] = 'sp' },
    },
    durations = {
        names   = { 'Haste', 'Protect', 'Shell', 'Regen', 'Refresh', 'Berserk', 'Blink', 'Phalanx', 'Stoneskin', 'Aquaveil' },
        targets = { 'You', 'Tankguy', 'Healbot', 'Nukerdude' },
    },
    debuffs = {
        names   = { 'Slow', 'Paralyze', 'Bind', 'Poison', 'Dia', 'Sleep', 'Silence', 'Gravity', 'Bio', 'Blind' },
        targets = { 'Goblin Smithy', 'Orcish Warlord', 'Yagudo Cleric', 'Giant Bat' },
    },
}

local function build_preview(kind, rows)
    local data = PREVIEW_DATA[kind]

    -- Shuffle a copy of the names and take as many as Test shows
    local pool = {}
    for i, n in ipairs(data.names) do pool[i] = n end
    for i = #pool, 2, -1 do
        local j = math.random(i)
        pool[i], pool[j] = pool[j], pool[i]
    end

    local items = {}
    for i = 1, math.min(rows, #pool) do
        local name = pool[i]
        local target = data.targets and data.targets[math.random(#data.targets)] or nil

        -- The first timer is short so the blink behaviour is visible right away
        local seconds = (i == 1) and 12 or math.random(20, 240)

        items[i] = {
            name = target and ('%s (%s)'):format(name, target) or name,
            target = target,
            duration = seconds * 60,
            icon_id = GetStatusIconForName(name),
            mode = (kind == 'recasts') and TimerMode.LeftToRight or TimerMode.RightToLeft,
            start_time = math.random(1, 100000),
            overdue = (kind ~= 'recasts'),   -- durations/debuffs run past zero and blink before looping
            blink_last = (kind == 'recasts'), -- recasts blink during their last 5 seconds
            kind = data.kinds and (data.kinds[name] or 'ja') or nil,
        }
    end
    return items
end

local function test_groups()
    return {
        recasts = ui.timers.recasts.timers,
        durations = ui.timers.buffs.timers,
        debuffs = ui.timers.debuffs.timers,
    }
end

-- The gold names and outlines on the running sample timers, as the Test settings say
local function mark_test()
    local ps = ui.timers.recasts.settings
    local titles = { recasts = 'Recasts', durations = 'Buffs', debuffs = 'Debuffs' }
    for kind, group in pairs(test_groups()) do
        if group.preview then
            group.preview.title = (ps.test_titles ~= false) and titles[kind] or nil
            group.preview.outline = ps.test_outlines ~= false
        end
    end
end

local function set_testing(on)
    local rows = tonumber(ui.timers.recasts.settings.test_rows) or 5
    for kind, group in pairs(test_groups()) do
        if on then
            group:start_preview(build_preview(kind, rows))
        else
            group:stop_preview()
        end
    end
    mark_test()
    ui.testing = on
end

local function page_test()
    vc.title('Test', 'sample timers in each panel')
    if vc.button((ui.testing and 'Stop test' or 'Start test') .. '##test_run', (not ui.testing) and 'primary' or nil, 160) then
        set_testing(not ui.testing)
    end

    vc.section('SAMPLE TIMERS')
    local ps = ui.timers.recasts.settings
    local rows = slider('test_rows', 'How many', tonumber(ps.test_rows) or 5, 1, 10, 1, '%d', 'How many timers Test puts in each panel. A panel\'s Max height can still leave some off.')
    if rows then
        ps.test_rows = rows
        if ui.testing then set_testing(true) end
    end

    vc.section('MARKINGS')
    local on = switch('test_titles', 'Panel names', ps.test_titles ~= false, 'The gold Recasts, Buffs and Debuffs over each panel while Test runs.')
    if on ~= nil then ps.test_titles = on; mark_test() end
    on = switch('test_outlines', 'Outlines', ps.test_outlines ~= false, 'The gold line round each panel and the dashed Max height box while Test runs.')
    if on ~= nil then ps.test_outlines = on; mark_test() end
end

--------------------------------------------------------------------------------
-- Arrange page: line the panels up with each other, space them out, centre them on screen.
-- A panel's box is its Max height area (the dashed outline in Test), so it lines up the same
-- however many timers it has; for a panel that grows up, its anchor is that box's bottom.
--------------------------------------------------------------------------------
local gArr = { sel = { recasts = true, durations = true, debuffs = true }, gap = 10 }

local function box_of(g)
    local s, pad = g.settings, g.settings.padding
    local w = math.max(10, s.bar_width + (s.stretch or 0)) + pad[1] + pad[3]
    local x, y = s.background.position_x, s.background.position_y
    local top = s.grow_up and (y - s.max_height) or y
    return { g = g, l = x, t = top, w = w, h = s.max_height }
end

local function place_box(b, l, t)
    local s = b.g.settings
    b.g:move_to(math.floor(l + 0.5), math.floor((s.grow_up and (t + b.h) or t) + 0.5))
    b.l, b.t = l, t
end

local function chosen_boxes()
    local out = {}
    for _, p in ipairs(PANELS) do
        if gArr.sel[p.id] then out[#out + 1] = box_of(group_of(p)) end
    end
    return out
end

local function screen_size()
    local ok, io_ = pcall(imgui.GetIO)
    local d = ok and io_ and io_.DisplaySize
    if type(d) == 'table' or type(d) == 'userdata' then
        local w, h = d.x or d[1], d.y or d[2]
        if w and h then return w, h end
    end
    return nil
end

local arrange_moves

local function arrange(how)
    local bs = chosen_boxes()
    if #bs == 0 then gArr.msg = 'No panel is switched on above.'; return end
    local ok, err = pcall(arrange_moves, how, bs)
    -- What moved where (the panel's anchor: its top-left, or bottom-left when it grows up)
    local parts = {}
    for _, p in ipairs(PANELS) do
        if gArr.sel[p.id] then
            local bg = group_of(p).settings.background
            parts[#parts + 1] = ('%s %d, %d'):format(p.label, bg.position_x, bg.position_y)
        end
    end
    gArr.msg = ok and (table.concat(parts, '   ')) or ('Could not arrange them: ' .. tostring(err))
end

arrange_moves = function(how, bs)
    local L, T, R, B = math.huge, math.huge, -math.huge, -math.huge
    for _, b in ipairs(bs) do
        L, T = math.min(L, b.l), math.min(T, b.t)
        R, B = math.max(R, b.l + b.w), math.max(B, b.t + b.h)
    end
    if how == 'left' then for _, b in ipairs(bs) do place_box(b, L, b.t) end
    elseif how == 'right' then for _, b in ipairs(bs) do place_box(b, R - b.w, b.t) end
    elseif how == 'centre' then for _, b in ipairs(bs) do place_box(b, (L + R) / 2 - b.w / 2, b.t) end
    elseif how == 'top' then for _, b in ipairs(bs) do place_box(b, b.l, T) end
    elseif how == 'bottom' then for _, b in ipairs(bs) do place_box(b, b.l, B - b.h) end
    elseif how == 'middle' then for _, b in ipairs(bs) do place_box(b, b.l, (T + B) / 2 - b.h / 2) end
    elseif how == 'row' or how == 'column' then
        -- in their order on screen, each one gap after the last, from the first one's place
        local row = (how == 'row')
        table.sort(bs, function(a, b) if row then return a.l < b.l end return a.t < b.t end)
        local at = row and bs[1].l or bs[1].t
        for _, b in ipairs(bs) do
            if row then place_box(b, at, b.t); at = at + b.w + gArr.gap
            else place_box(b, b.l, at); at = at + b.h + gArr.gap end
        end
    elseif how == 'screen_x' or how == 'screen_y' then
        local sw, sh = screen_size()
        if not sw then return end
        local dx = (how == 'screen_x') and (sw / 2 - (L + R) / 2) or 0
        local dy = (how == 'screen_y') and (sh / 2 - (T + B) / 2) or 0
        for _, b in ipairs(bs) do place_box(b, b.l + dx, b.t + dy) end
    end
end

local function page_arrange()
    vc.title('Arrange', 'line the panels up')
    vc.note('Each panel counts as its Max height box: the dashed outline while Test runs. Turn Test on to watch the panels move.')

    vc.section('PANELS TO ARRANGE')
    for _, p in ipairs(PANELS) do
        local v = switch('arr_' .. p.id, p.label, gArr.sel[p.id])
        if v ~= nil then gArr.sel[p.id] = v end
    end

    local function buttons(list)
        for i, e in ipairs(list) do
            if i > 1 then imgui.SameLine() end
            local on = (gArr.mode == e[1])
            if vc.button(e[2] .. '##arr_' .. e[1], on and 'primary' or nil, 120) then
                arrange(e[1])
                -- Side by side / Stacked stay picked, so the Gap re-spaces them; anything else ends that
                gArr.mode = (e[1] == 'row' or e[1] == 'column') and e[1] or nil
            end
            tip(e[3])
        end
    end

    vc.section('ALIGN')
    buttons({ { 'left', 'Left', 'Every panel\'s left edge where the leftmost one\'s is.' },
              { 'centre', 'Centre', 'Every panel centred on the same line, across the middle of them all.' },
              { 'right', 'Right', 'Every panel\'s right edge where the rightmost one\'s is.' } })
    buttons({ { 'top', 'Top', 'Every panel\'s top where the highest one\'s is.' },
              { 'middle', 'Middle', 'Every panel centred on the same level, through the middle of them all.' },
              { 'bottom', 'Bottom', 'Every panel\'s bottom where the lowest one\'s is.' } })

    vc.section('SPACE OUT')
    local n = slider('arr_gap', 'Gap', gArr.gap, 0, 200, 1, '%d px', 'Space between the panels. After Side by side or Stacked, moving this re-spaces them that way as you drag.')
    if n then
        gArr.gap = n
        if gArr.mode then arrange(gArr.mode) end
    end
    buttons({ { 'row', 'Side by side', 'In their order from left to right, each one Gap after the last, starting where the leftmost one is.' },
              { 'column', 'Stacked', 'In their order from top to bottom, each one Gap under the last, starting where the highest one is.' } })
    if gArr.msg then imgui.TextColored(C.mute, 'Now at: ' .. gArr.msg) end

    vc.section('ON SCREEN')
    buttons({ { 'screen_x', 'Centre across', 'Moves the panels together so they are centred left to right on the screen.' },
              { 'screen_y', 'Centre up/down', 'Moves the panels together so they are centred top to bottom on the screen.' } })

    vc.section('POSITION')
    local sw, sh = screen_size()
    for _, p in ipairs(PANELS) do
        local g = group_of(p)
        local bg = g.settings.background
        n = slider('arrx_' .. p.id, p.label .. ' X', bg.position_x, 0, math.floor(sw or 4000), 1, '%d px', 'Its left edge.')
        if n then g:move_to(n, bg.position_y) end
        n = slider('arry_' .. p.id, p.label .. ' Y', bg.position_y, 0, math.floor(sh or 3000), 1, '%d px',
            g.settings.grow_up and 'Its bottom (it grows up from here).' or 'Its top (it grows down from here).')
        if n then g:move_to(bg.position_x, n) end
    end
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------
local PAGES = { about = page_about, theme = page_theme, sets = page_sets, arrange = page_arrange, test = page_test }
local PAGE_NAME = { about = 'About', theme = 'Theme', sets = 'Filter Sets', arrange = 'Arrange', test = 'Test' }
for _, p in ipairs(PANELS) do
    for _, sp in ipairs(SUBPAGES) do
        local id = p.id .. '.' .. sp[1]
        PAGES[id] = function() SUB_DRAW[sp[1]](p) end
        PAGE_NAME[id] = p.label .. ' / ' .. sp[2]
    end
end

local function sidebar(nav)
    if nav.head('test', ui.testing and 'Stop test' or 'Test: fill panels', ui.testing, 'test') then
        set_testing(not ui.testing)
    end
    nav.tip('Fill each panel with sample timers so you can see how it looks. They loop, and stop when this window closes.')
    nav.gap()
    if nav.head('gear', 'Test options', win.page == 'test', 'test_opts') then win.page = 'test' end
    nav.tip('How many sample timers, and the gold names and outlines')
    nav.gap()
    if nav.head('about', 'About', win.page == 'about') then win.page = 'about' end
    nav.gap()
    if nav.head('star', 'Theme', win.page == 'theme') then win.page = 'theme' end
    nav.tip('Default or YunaUI for each panel')
    nav.gap()
    if nav.head('widget', 'Arrange', win.page == 'arrange') then win.page = 'arrange' end
    nav.tip('Line the panels up: left, right, top, bottom, centre')

    nav.caption('PANELS')
    for _, p in ipairs(PANELS) do
        if nav.head(p.icon, p.label, false, 'p_' .. p.id) then win.page = p.id .. '.layout' end
        for _, sp in ipairs(SUBPAGES) do
            local id = p.id .. '.' .. sp[1]
            if nav.item(sp[2], win.page == id, id) then win.page = id end
        end
        nav.gap()
    end

    nav.caption('FILTERS')
    if nav.head('files', 'Filter Sets', win.page == 'sets') then win.page = 'sets' end
    nav.tip('Save the filters per job')
end

local WINDOW = {
    id       = 'timers',
    title    = 'Timers',
    size     = { 780, 620 },
    min      = { 640, 440 },
    pages    = PAGES,
    sidebar  = sidebar,
    sidebar_w = 210,
    scaler   = true,
    on_scale = function(s) ui.timers.recasts.settings.ui_scale = s end,
    subtitle = function(page) return PAGE_NAME[page] end,
    header_right = function()
        if ui.testing then return 'Test running', C.gold end
        return 'v' .. tostring(addon.version), C.mute
    end,
}

ui.render_config_ui = function(settings)
    ui.timers = settings

    if not win.open[1] then
        -- The sample timers only exist while the window is open
        if ui.testing then set_testing(false) end
        return
    end

    win.scale = tonumber(settings.recasts.settings.ui_scale) or 1
    vc.window(win, WINDOW)

    -- Push the edits into the panels (and keep the settings that are saved in step)
    for _, p in ipairs(PANELS) do
        group_of(p):update_settings()
    end
end

return ui
