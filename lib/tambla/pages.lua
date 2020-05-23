sky.use('sky/lib/io/norns')
sky.use('sky/lib/core/page')

local json = include('sky/lib/dep/rxi-json/json')

local fmt = require('formatters')
local cs = require('controlspec')
local fs = require('fileselect')
local te = require('textentry')

local PAT_EXTN = '.pat.json'
local SET_EXTN = '.set.json'

--
-- RowWidget
--

local RowWidget = sky.Object:extend()
RowWidget.HEIGHT = 15
RowWidget.STEP_WIDTH = 6
RowWidget.BAR_WIDTH = 4
RowWidget.BAR_HEIGHT = 10

function RowWidget:new(x, y)
  self.topleft = {x or 1, y or 1}
end

function RowWidget:width(row)
  return self.STEP_WIDTH * row.n
end

function RowWidget:draw(row, beats)
  -- draw from bottom, left
  local x = self.topleft[1]
  local y = self.topleft[2] + self.BAR_HEIGHT
  for i, step in ipairs(row.steps) do
    if i > row.n then break end -- FIXME: move this iteration detail to Row
    if step:is_active() then
      local width = math.floor(util.linlin(0, 1, 1, self.BAR_WIDTH, step.duration)) -- FIXME: 0 duration really?
      local height = math.floor(util.linlin(0, 1, 1, self.BAR_HEIGHT, step.velocity))
      screen.rect(x, y - height, width, height)
      local level = math.floor(util.linlin(0, 1, 2, 12, step.chance))
      screen.level(level)
      screen.fill()
    end
    x = x + self.STEP_WIDTH
  end

  -- playhead
  x = self.topleft[1]
  y = self.topleft[2] + self.BAR_HEIGHT + 3
  screen.move(x, y)
  screen.line_rel(self:width(row) * row:head_position(beats), 0)
  screen.level(1)
  screen.close()
  screen.stroke()
  screen.level(15)
  screen.pixel(self:width(row) + 3, y - 1)
  screen.fill()
end

function RowWidget:draw_step_selection(row, step)
  if step > row.n then
      -- limit selection ui to end of row
    step = row.n
  end
  local x = self.topleft[1] + ((step - 1) * self.STEP_WIDTH)
  local y = self.topleft[2] + self.BAR_HEIGHT + 2
  screen.level(5)
  screen.rect(x + 1, y, self.BAR_WIDTH - 1, 2)
  screen.close()
  screen.stroke()
end

local function layout_vertical(x, y, widgets)
  -- adjust the widget top/left origin such that they are arranged in a stack
  local top = y
  for i, w in ipairs(widgets) do
    w.topleft[1] = x
    w.topleft[2] = top
    top = top + w.HEIGHT
  end
end

--
-- PageBase
--

local PageBase = sky.Page:extend()
PageBase.PARAM_LEFT = 128
PageBase.PARAM_SPACING = 8
PageBase.LABEL_LEVEL = 3
PageBase.VALUE_LEVEL = 12
PageBase.TOP_LEFT = { 0, 2 }

function PageBase:new(model, controller, topleft)
  PageBase.super.new(self, model)
  self.topleft = topleft or self.TOP_LEFT
  self.controller = controller

  self.page_code = '?'

  self.widgets = {}
  for i, r in ipairs(self.model:slot().rows) do
    table.insert(self.widgets, RowWidget())
  end
  layout_vertical(self.topleft[1] + 4, self.topleft[2], self.widgets)
end

function PageBase:draw_mode()
  screen.level(self.LABEL_LEVEL)
  screen.font_face(0)
  screen.font_size(8)
  screen.move(self.PARAM_LEFT, 58)
  screen.text_right(self.page_code)
end

function PageBase:draw_rows(beat)
  local rows = self.model:slot().rows
  for i, w in ipairs(self.widgets) do
    w:draw(rows[i], beat)
  end
end

function PageBase:draw_caret()
  -- selection carat
  local y = self.controller:selected_row_idx() * RowWidget.HEIGHT - 2
  screen.level(15)
  screen.rect(self.topleft[1], y, 2, 2)
end

function PageBase:draw_param(y, name, value)
  screen.font_face(0)
  screen.font_size(8)
  screen.move(self.PARAM_LEFT, y)
  screen.level(self.LABEL_LEVEL)
  screen.text_right(name)
  y = y + self.PARAM_SPACING
  screen.move(self.PARAM_LEFT, y)
  screen.level(self.VALUE_LEVEL)
  screen.text_right(value)
  return y + self.PARAM_SPACING
end

function PageBase:process(event, output, state, props)
  self.controller:process(event, output, state, props)
  output(event)
end

--
-- PlayPage
--

local PlayPage = PageBase:extend()

function PlayPage:new(model, controller)
  PlayPage.super.new(self, model, controller)
  self.page_code = 'P'
end

function PlayPage:draw(event, props)
  self:draw_rows(event.beat)
  self:draw_caret()
  self:draw_mode()
  self:draw_param(8, self.controller:selected_prop_code(), self.controller:selected_prop_value())
end

function PlayPage:process(event, output, state, props)
  PlayPage.super.process(self, event, output, state, props)

  local key_z = self.controller.key_z
  local controller = self.controller

  if sky.is_key(event) then
    if event.num == 2 and event.z == 1 then
      if key_z[1] == 1 then
        props.select_page('macro')
      elseif key_z[3] == 1 then
        -- key 2 w/ key 3 held
        self.model:slot():randomize()
        output(sky.mk_redraw())
      else
        -- play, key 2 action
        print("play key 2 action")
      end
    elseif event.num == 3 and event.z == 1 then
      if key_z[1] == 1 then -- mode shift key
        props.select_page('edit')
      else
        -- play, key 3 action
        print("play key 3 action")
      end
    end
  elseif sky.is_enc(event) then
    if event.num == 1 then
      if key_z[1] == 1 then
        self.controller.row_acc = util.clamp(self.controller.row_acc + (event.delta / 10), 1, self.controller.row_count)
        self.controller:select_row(self.controller.row_acc)
      end
    elseif event.num == 2 then
      controller.prop_acc = util.clamp(controller.prop_acc + (event.delta / 10), 1, controller.prop_count)
      self.controller:select_prop(controller.prop_acc)
    elseif event.num == 3 then
      local idx = self.controller:selected_row_idx()
      local id = self.controller:selected_prop_name() .. tostring(idx) -- FIXME: avoid string construction?
      local delta = event.delta
      if key_z[3] == 1 then
        -- fine tuning
        delta = delta / 10.0
      end
      params:delta(id, event.delta)
    end
  end
end

--
-- EditPage
--

local EditPage = PageBase:extend()

function EditPage:new(model, controller)
  EditPage.super.new(self, model, controller)
  self.page_code = 'E'
end

function EditPage:draw_step_select()
  local idx = self.controller:selected_row_idx()
  local row = self.controller:selected_row()
  local widget = self.widgets[idx]
  widget:draw_step_selection(row, self.controller:selected_step_idx())
end

function EditPage:draw(event, props)
  self:draw_rows(event.beat)
  self:draw_step_select()
  self:draw_caret()
  self:draw_mode()

  local step = self.controller:selected_step()
  local y = 8
  y = self:draw_param(y, 'v', util.round(step.velocity, 0.01))
  y = self:draw_param(y, 'd', util.round(step.duration, 0.01))
  y = self:draw_param(y, '%', util.round(step.chance, 0.01))
end

function EditPage:process(event, output, state, props)
  EditPage.super.process(self, event, output, state, props)

  local key_z = self.controller.key_z
  -- local controller = self.controller

  if sky.is_key(event) then
    if event.num == 2 and event.z == 1 then
      if key_z[1] == 1 then
        -- key 2 w/ key 1 held
        props.select_page('play')
      elseif key_z[3] == 1 then
        -- key 2 w/ key 3 held
        print('randomize row')
        local row = self.controller:selected_row()
        row:randomize()
      else
        -- key 2 action
        print('k2 action')
      end
    elseif event.num == 3 and event.z == 1 then
      if key_z[1] == 1 then
        -- key 3 w/ key 1 held
      elseif key_z[2] == 1 then
        -- key 3 w/ key 2 held
        print('clear row')
        local row = self.controller:selected_row()
        row:clear()
      else
        -- key 3 action
        print('k3 action')
      end
    end
  elseif sky.is_enc(event) then
    if event.num == 1 then
      if key_z[1] == 0 then
        -- select step
        self.controller.step_acc = util.clamp(self.controller.step_acc + (event.delta / 5), 1, self.controller:selected_row_n())
        self.controller:select_step(self.controller.step_acc)
      else
        -- select row
        self.controller.row_acc = util.clamp(self.controller.row_acc + (event.delta / 10), 1, self.controller.row_count)
        self.controller:select_row(self.controller.row_acc)
      end
    elseif event.num == 2 then
      local step = self.controller:selected_step()
      if key_z[2] == 1 then
        -- tweak chance
        if step ~= nil then
          step:set_chance(step.chance + (event.delta / 20))
        end
      else
        -- tweak velocity
        if step ~= nil then
          step:set_velocity(step.velocity + (event.delta / 20))
          if step.velocity > 0 and not step:is_active() then
            -- auto set chance to 100% steps if velocity is non-zero but step is
            -- inactive
            step:set_chance(1)
          end
        end
      end
    elseif event.num == 3 then
      -- tweak duration
      local step = self.controller:selected_step()
      if step ~= nil then
        step:set_duration(step.duration + (event.delta / 20))
      end
    end
  end
end

--
-- SlotWidget
--
local SlotWidget = sky.Object:extend()
SlotWidget.BOX_DIM = 8
SlotWidget.BOX_SEP = 3
SlotWidget.BOX_PAD = 4
SlotWidget.SELECTED_LEVEL = 10

function SlotWidget:new(x, y)
  self.topleft = {x or 1, y or 1}
end

--
-- GlyphWidget
--

local GlyphWidget = SlotWidget:extend()

function GlyphWidget:new(x, y, levels)
  GlyphWidget.super.new(self, x, y)
  self.levels = levels or {1, 1, 1, 1}
end

function GlyphWidget:draw(levels, selected)
  local levels = level or self.levels
  local x = self.topleft[1]
  local y = self.topleft[2]

  if selected then
    local full_dim = self.BOX_PAD * 2 + self.BOX_SEP + self.BOX_DIM * 2
    local dx = x + full_dim
    screen.move(x, y + full_dim)
    screen.line_rel(full_dim - 1, 0)
    screen.level(self.SELECTED_LEVEL)
    screen.close()
    screen.stroke()
  end

  -- inner
  local d = self.BOX_DIM
  local w = d + self.BOX_SEP
  local n = 1
  for bx = 0, 1 do
    for by = 0, 1 do
      local x1 = x + (bx * w) + self.BOX_PAD
      local y1 = y + (by * w) + self.BOX_PAD
      local l = levels[n]
      screen.level(levels[n])
      if l > 1 then
        --screen.rect(x1 - 0.5, y1, d + 0.5, d) -- MATIN: compensate for weird offset when filling
        screen.rect(x1, y1, d, d) -- MATIN: compensate for weird offset when filling
        screen.fill()
        screen.stroke()
      else
        screen.rect(x1, y1, d, d) -- MATIN: compensate for weird offset when filling
        screen.stroke()
      end
      n = n + 1
    end
  end
end

local NumWidget = SlotWidget:extend()

function NumWidget:new(x, y, num)
  NumWidget.super.new(self, x, y)
  self.num = num
end

function NumWidget:draw(levels, selected)
  local levels = level or self.levels
  local x = self.topleft[1]
  local y = self.topleft[2]
  local full_dim = self.BOX_PAD * 2 + self.BOX_SEP + self.BOX_DIM * 2
  local half_dim = full_dim / 2

  -- outer
  screen.move(x, y + 3)
  screen.line_rel(0, -3)
  screen.line_rel(full_dim - 1, 0)
  screen.line_rel(0, 3)
  screen.level(2)
  screen.stroke()
  screen.move(x + half_dim - 2, y + half_dim + 4)
  if selected then screen.level(self.SELECTED_LEVEL) end
  screen.font_size(14)
  screen.text_center(self.num)

  if selected then
    local dx = x + full_dim
    screen.move(x, y + full_dim)
    screen.line_rel(full_dim - 1, 0)
    screen.level(self.SELECTED_LEVEL)
    screen.close()
    screen.stroke()
  end
end


--
-- Selector
--

local Selector = sky.Object:extend()

function Selector:new(values_f, action_f)
  self.values_f = values_f
  self.action_f = action_f

  self.values = nil
  self.acc = 1
  self.selection = 1
  self.len = 0
end

function Selector:refresh()
  self.values = self.values_f()
  self.len = #self.values
end

function Selector:select(v)
  self.selection = util.clamp(math.floor(v), 1, self.len)
end

function Selector:value()
  if self.values then
    return self.values[self.selection]
  end
end

function Selector:bang()
  if self.action_f then
    self.action_f(self:value())
  end
end

local function gather_files(dir, glob, static)
  local t = {}
  local extn = string.gsub(glob, '*', '')
  local filter = function(results)
    for path in results:gmatch("[^\r\n]+") do
      local p = string.gsub(path, dir, '')
      p = string.gsub(p, extn, '')
      table.insert(t, p)
    end
  end
  local cmd = 'find ' .. dir .. ' -name "' .. glob .. '" | sort'
  filter(util.os_capture(cmd, true))
  if static then
    for _, v in ipairs(static) do
      table.insert(t, v)
    end
  end
  return t
end

local PatternSelector = Selector(function()
  return gather_files(paths.this.data, '*.pat.json', {'...'})
end)

local SetSelector = Selector(function()
  return gather_files(paths.this.data, '*.set.json', {'...'})
end)

--
-- MacroPage
--

local MacroPage = PageBase:extend()

function MacroPage:new(model, controller)
  MacroPage.super.new(self, model, controller)
  self.slots = {
    NumWidget(5, 10, 1),
    NumWidget(35, 10, 2),
    NumWidget(65, 10, 3),
    NumWidget(95, 10, 4),
    -- GlyphWidget(5, 10, {10, 2, 1, 1}),
    -- GlyphWidget(35, 10, {1, 2, 10, 1}),
    -- GlyphWidget(65, 10, {1, 2, 1, 10}),
    -- GlyphWidget(95, 10, {2, 1, 1, 10}),
  }

  self:select_slot(1)
  self.slot_acc = 1

  self.actions = {
    -- {'copy', nil},
    -- {'paste', nil},
    {'pattern load:', PatternSelector, self.do_load_pat},
    {'pattern save:', PatternSelector, self.do_save_pat},
    -- {'set load:', SetSelector, self.do_load_set},
    -- {'set save:', SetSelector, self.do_save_set}
    -- {'algo:' nil},
  }
  self:select_action(1)
  self.action_acc = 1

  self.page_code = 'M'
end

function MacroPage:enter(props)
  print('refresh start')
  SetSelector:refresh()
  PatternSelector:refresh()
  print('refresh end')
end

function MacroPage:select_slot(i)
  self._slot = util.clamp(math.floor(i), 1, self.model.NUM_SLOTS)
end

function MacroPage:selected_slot()
  return self._slot
end

function MacroPage:select_action(i)
  self._action = util.clamp(math.floor(i), 1, #self.actions)
  self._selector = self:selected_action()[2]
end

function MacroPage:selected_action()
  return self.actions[self._action]
end

function MacroPage:selected_action_name()
  return self.actions[self._action][1]
end

function MacroPage:selected_action_value()
  if self._selector then
    return self._selector:value()
  end
  return ''
end

function MacroPage:selected_action_handler()
  return self.actions[self._action][3]
end

function MacroPage:draw_action()
  screen.level(4)
  screen.font_face(0)
  screen.font_size(8)
  screen.move(4, 48)
  screen.text(self:selected_action_name())
end

function MacroPage:draw_action_value()
  local v = self:selected_action_value()
  if v then
    screen.level(10)
    screen.font_face(0)
    screen.font_size(8)
    screen.move(10, 58)
    screen.text(v)
  end
end

function MacroPage:draw(event, props)
  local selected = self:selected_slot()
  for n = 1,self.model.NUM_SLOTS do
    self.slots[n]:draw(nil, n == selected)
  end
  self:draw_action()
  self:draw_action_value()
  self:draw_mode()
end

function MacroPage:process(event, output, state, props)
  MacroPage.super.process(self, event, output, state, props)

  local key_z = self.controller.key_z
  local controller = self.controller

  if sky.is_key(event) then
    if event.num == 3 and event.z == 1 then
      if key_z[1] == 1 then
        props.select_page('play')
      else
        local action = self:selected_action_handler()
        if action then
          action(self, self:selected_action_value())
        end
      end
    end
  elseif sky.is_enc(event) then
    if event.num == 1 then
      if key_z[1] == 0 then
        self.slot_acc = util.clamp(self.slot_acc + (event.delta / 10), 1, self.model.NUM_SLOTS)
        self:select_slot(self.slot_acc)
      end
    elseif event.num == 2 then
      self.action_acc = util.clamp(self.action_acc + (event.delta / 10), 1, #self.actions)
      self:select_action(self.action_acc)
    elseif event.num == 3 then
      local selector = self:selected_action()[2]
      if selector then
        selector.acc = util.clamp(selector.acc + (event.delta / 10), 1, selector.len)
        selector:select(selector.acc)
      end
    end
  end
end

local function expand_path(p, prefix, extension)
  if p[1] ~= '/' then
    p = prefix .. p
  end
  if string.find(p, extension, -#extension, true) == nil then
    p = p .. extension
  end
  return p
end

function MacroPage:do_load_pat(what)
  print('do_load_pat(' .. what .. ')')

  local _load = function(path)
    if path and path ~= 'cancel' then
      local src = expand_path(path, paths.this.data, PAT_EXTN)
      print('loading:', src)
      local f = io.open(src, 'r')
      local data = f:read()
      f:close()
      local props = json.decode(data)
      self.model:slot():load(props)
    end
  end

  if what == '...' then
    -- MAINT: fileselect does not change the `redraw` callback like the menu does
    -- so sky.NornsDisplay can detect that it has lost focus and should stop
    -- drawing. Here we manually enable/display our drawing.
    sky.set_focus(false)
    fs.enter(paths.this.data, function(path)
      print('selected:', path)
      _load(path)
      sky.set_focus(true)
    end)
  else
    _load(what)
  end
end

function MacroPage:do_save_pat(what)
  print('do_save_pat(' .. what .. ')')

  local _save = function(path)
    if path and path ~= 'cancel' then
      local dest = expand_path(path, paths.this.data, PAT_EXTN)
      print('saving:', dest)
      local data = json.encode(self.model:slot():store()) -- FIXME: this should be a pattern
      local f = io.open(dest, 'w+')
      f:write(data)
      f:close()
    end
  end

  if what == '...' then
    sky.set_focus(false)
    te.enter(function(path)
      if path then _save(path) end
      sky.set_focus(true)
    end, 'pat')
  else
    _save(what)
  end
end

function MacroPage:do_load_set(what)
  print('load set', what)
end

function MacroPage:do_save_set(what)
  print('save set', what)
  if what == '...' then
  end
end


--
-- Controller
--

local Controller = sky.Object:extend()

function Controller:new(model)
  self.model = model

  self.row_count = model.NUM_ROWS
  self.row_acc = 1
  self:select_row(1)

  self.step_acc = 1
  self:select_step(1)

  self.prop_codes = {'b', 'o', 'r', 'n',}
  self.prop_names = {'bend', 'offset', 'res', 'n'}
  self.prop_count = 4 -- FIXME: get this from the model
  self.prop_acc = 1
  self:select_prop(1)

  self.key_z = {0, 0, 0}
end

-- row selection state

function Controller:select_row(i)
  self._selected_row = util.clamp(math.floor(i), 1, self.model.NUM_ROWS)
end

function Controller:selected_row_idx()
  return self._selected_row
end

function Controller:selected_row()
  local p = self.model:slot()
  --print(p)
  return p.rows[self._selected_row]
end

function Controller:selected_row_n()
  return self:selected_row().n
end

-- step selection state

function Controller:select_step(i)
  self._selected_step = util.clamp(math.floor(i), 1, self:selected_row_n())
end

function Controller:selected_step_idx()
  return self._selected_step
end

function Controller:selected_step()
  local r = self:selected_row()
  return r.steps[self:selected_step_idx()]
end

-- property selection state

function Controller:select_prop(i)
  self._selected_prop = util.clamp(math.floor(i), 1, self.prop_count)
end

function Controller:selected_prop_code()
  return self.prop_codes[self._selected_prop]
end

function Controller:selected_prop_name()
  return self.prop_names[self._selected_prop]
end

function Controller:selected_prop_value()
  local r = self:selected_row()
  local k = self.prop_names[self._selected_prop]
  return r[k]
end

-- parameters

function Controller:add_row_params(i)
  local n = tostring(i)
  params:add_group('row ' .. n, 7)
  params:add{type = 'option', id = 'chance' .. n, name = 'chance',
    options = {'on', 'off'},
    default = 1
  }
  params:add{type = 'option', id = 'velocity_mod' .. n, name = 'velocity mod',
    options = {'on', 'off'},
    default = 1
  }
  params:add{type = 'option', id = 'length_mod' .. n, name = 'length mod',
    options = {'on', 'off'},
    default = 1
  }
  params:add{type = 'control', id = 'bend' .. n, name = 'bend',
    controlspec = cs.new(0.2, 5.0, 'lin', 0.005, 1.0, ''),
    formatter = fmt.round(0.01),
    action = function(v) self.model:slot().rows[i]:set_bend(v) end,
  }
  params:add{type = 'control', id = 'n' .. n, name = 'n',
    controlspec = cs.new(2, 16, 'lin', 1, 16, ''),
    formatter = fmt.round(1),
    action = function(v) self.model:slot().rows[i]:set_n(v) end,
  }
  params:add{type = 'control', id = 'res' .. n, name = 'res',
    controlspec = cs.new(4, 32, 'lin', 1, 4, ''),
    formatter = fmt.round(1),
    action = function(v) self.model:slot().rows[i]:set_res(v) end,
  }
  params:add{type = 'control', id = 'offset' .. n, name = 'offset',
    controlspec = cs.new(-16, 16, 'lin', 1, 0, ''),
    formatter = fmt.round(1),
    action = function(v) self.model:slo().rows[i]:set_offset(v) end,
  }
end

function Controller:add_params()
  params:add_separator('tambla')

  -- params:add_file('file', 'file', 'foo.json')

  -- params:add_trigger('state_load', 'load...')
  -- params:set_action('state_load', function()
  --   local start = paths.this.data
  --   fs.enter(start, function(path)
  --     params:set('pattern_name', path)
  --     print('got: ', path)
  --   end)
  -- end)

  -- params:add_trigger('state_save', 'save...')
  -- params:set_action('state_save', function()
  --   local name = params:string('pattern')
  --   local cb = function(result)
  --     print('got: ', result)
  --   end
  --   te.enter(cb, name, 'save')
  --   --print('save Controller:', name)
  -- end)

  params:add{type = 'control', id = 'pattern', name = 'pattern',
    controlspec = cs.new(1, 4, 'lin', 1, 4, ''),
    formatter = fmt.round(1),
    action = function(v)
      -- FIXME: restore slot selection state on model so that it can be a
      -- performance control via parameter mapping
      --self.controller:select_slot(v)
    end,
  }

  for i = 1, self.model.NUM_ROWS do
    self:add_row_params(i)
  end
end

function Controller:process(event, output, state)
  if sky.is_key(event) then
    -- record key state for use in key chording ui
    self.key_z[event.num] = event.z
  end
end

--
-- module
--
return {
  PlayPage = PlayPage,
  EditPage = EditPage,
  MacroPage = MacroPage,

  Controller = Controller,
}