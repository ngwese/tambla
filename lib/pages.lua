sky.use('core/page')
sky.use('io/norns')

local json = include('lib/dep/rxi-json/json')

local fmt = require('formatters')
local cs = require('controlspec')
local fs = require('fileselect')
local te = require('textentry')
local mu = require('musicutil')

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
    w:draw(rows[i], self.model:sync(i, beat))
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

function PageBase:draw_slot_num()
  local num = self.model:selected_slot_idx()
  screen.font_size(16)
  screen.move(118, 40)
  --screen.level(self.VALUE_LEVEL)
  screen.level(2)
  screen.text_center(num)
end

function PageBase:process(event, output, state, props)
  -- MAINT: this is goofy, currently state of key 1 is held in the controller so that it is
  -- accessible to all pages... so we have to process that here.
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

  self.slot_acc = 1
end

function PlayPage:draw(event, props)
  self:draw_rows(event.beat)
  self:draw_caret()
  self:draw_mode()
  self:draw_param(8, self.controller:selected_prop_code(), self.controller:selected_prop_value())
  self:draw_slot_num()
end

function PlayPage:process(event, output, state, props)
  PlayPage.super.process(self, event, output, state, props)

  local key_z = self.controller.key_z
  local controller = self.controller

  if sky.is_key(event) then
    if event.n == 2 and event.z == 1 then
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
    elseif event.n == 3 and event.z == 1 then
      if key_z[1] == 1 then -- mode shift key
        props.select_page('edit')
      else
        -- play, key 3 action
        print("play key 3 action")
      end
    end
  elseif sky.is_enc(event) then
    if event.n == 1 then
      if key_z[1] == 1 then
        self.controller.row_acc = util.clamp(self.controller.row_acc + (event.delta / 10), 1, self.controller.row_count)
        self.controller:select_row(self.controller.row_acc)
      else
        self.slot_acc = util.clamp(self.slot_acc + (event.delta / 10), 1, self.model:slot_count())
        self.model:select_slot(self.slot_acc)
        params:set('active_pattern', self.model:selected_slot_idx(), true)
      end
    elseif event.n == 2 then
      controller.prop_acc = util.clamp(controller.prop_acc + (event.delta / 10), 1, controller.prop_count)
      self.controller:select_prop(controller.prop_acc)
    elseif event.n == 3 then
      local idx = self.controller:selected_row_idx()
      local id = self.controller:selected_prop_name() .. tostring(idx) -- FIXME: avoid string construction?
      local delta = event.delta
      if key_z[3] == 1 then
        -- fine tuning
        delta = delta * 0.01
      end
      params:delta(id, delta)
    end
  elseif sky.ArcInput.is_enc(event) then
    if event.n == 1 then
      self.controller.row_acc = util.clamp(self.controller.row_acc + (event.delta / 50), 1, self.controller.row_count)
      self.controller:select_row(self.controller.row_acc)

      output(sky.ArcDialGesture.mk_dial(1, self.controller.row_acc, math.floor(self.controller.row_acc) / self.controller.row_count))
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
    if event.n == 2 and event.z == 1 then
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
    elseif event.n == 3 and event.z == 1 then
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
    if event.n == 1 then
      if key_z[1] == 0 then
        -- select step
        self.controller.step_acc = util.clamp(self.controller.step_acc + (event.delta / 5), 1, self.controller:selected_row_n())
        self.controller:select_step(self.controller.step_acc)
      else
        -- select row
        self.controller.row_acc = util.clamp(self.controller.row_acc + (event.delta / 10), 1, self.controller.row_count)
        self.controller:select_row(self.controller.row_acc)
      end
    elseif event.n == 2 then
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
    elseif event.n == 3 then
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
  screen.font_size(16)
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

  self._clipboard = nil

  self.actions = {
    {'copy', nil, self.do_copy_pat},
    {'paste', nil, self.do_paste_pat},
    {'pattern load:', PatternSelector, self.do_load_pat},
    {'pattern save:', PatternSelector, self.do_save_pat},
    {'set load:', SetSelector, self.do_load_set},
    {'set save:', SetSelector, self.do_save_set}
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
  self._slot = util.clamp(math.floor(i), 1, self.model:slot_count())
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
  for n = 1,self.model:slot_count() do
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
    if event.n == 3 and event.z == 1 then
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
    if event.n == 1 then
      if key_z[1] == 0 then
        self.slot_acc = util.clamp(self.slot_acc + (event.delta / 10), 1, self.model:slot_count())
        self:select_slot(self.slot_acc)
      end
    elseif event.n == 2 then
      self.action_acc = util.clamp(self.action_acc + (event.delta / 10), 1, #self.actions)
      self:select_action(self.action_acc)
    elseif event.n == 3 then
      local selector = self:selected_action()[2]
      if selector then
        selector.acc = util.clamp(selector.acc + (event.delta / 10), 1, selector.len)
        selector:select(selector.acc)
      end
    end
  end
end

function MacroPage:do_copy_pat()
  self._clipboard = self.model:slot():store()
end

function MacroPage:do_paste_pat()
  if self._clipboard then
    self.model:slot(self._slot):load(self._clipboard)
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
      self.model:slot(self._slot):load(props)
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
      local data = json.encode(self.model:slot():store())
      local f = io.open(dest, 'w+')
      f:write(data)
      f:close()
    end
  end

  if what == '...' then
    sky.set_focus(false)
    te.enter(function(path)
      if path then _save(path) end
      PatternSelector:refresh()
      sky.set_focus(true)
    end, 'pat')
  else
    _save(what)
  end
end

function MacroPage:do_load_set(what)
  print('do_load_set(' .. what .. ')')

  local _load = function(path)
    if path and path ~= 'cancel' then
      local src = expand_path(path, paths.this.data, SET_EXTN)
      print('loading:', src)
      local f = io.open(src, 'r')
      local data = f:read()
      f:close()
      local props = json.decode(data)
      self.model:load(props)
    end
  end

  if what == '...' then
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

function MacroPage:do_save_set(what)
  print('do_save_set(' .. what .. ')')

  local _save = function(path)
    if path and path ~= 'cancel' then
      local dest = expand_path(path, paths.this.data, SET_EXTN)
      print('saving:', dest)
      local data = json.encode(self.model:store())
      local f = io.open(dest, 'w+')
      f:write(data)
      f:close()
    end
  end

  if what == '...' then
    sky.set_focus(false)
    te.enter(function(path)
      if path then _save(path) end
      SetSelector:refresh()
      sky.set_focus(true)
    end, 'set')
  else
    _save(what)
  end
end


--
-- Controller
--

local Controller = sky.Object:extend()

function Controller:new(model)
  self.model = model
  self.row_outs = nil
  self.logger = nil

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

  self.slot_acc = 1
  self.model:select_slot(1)

  self.chance_mod = false
  self.velocity_mod = true
  self.length_mod = true
  self.note_sync = false

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

-- input / output devices
function Controller:set_input_device(device)
  self.input_device = device
end

function Controller:set_output_router(device)
  self.output_router = device
end

function Controller:set_transposer(device)
  self.transposer = device
end

function Controller:set_midi_outputs(outputs)
  self.midi_outputs = outputs
end

function Controller:set_crow_outputs(outputs)
  self.crow_outputs = outputs
end

function Controller:set_logger(logger)
  self.logger = logger
end

function Controller:set_hold_state_setter(func)
  self.hold_setter = func
end

function Controller:set_random_device(device)
  self.random_device = device
end

function Controller:set_scale_device(device)
  self.scale_device = device
end


-- parameters

function Controller:add_row_params(i)
  local n = tostring(i)
  params:add_group(n, 5)
  params:add{type = 'option', id = 'destination' .. n, name = 'destination',
    options = {'default', 'polyperc', 'midi a', 'midi b', 'midi c', 'midi d', 'crow a', 'crow b', 'wsyn'},
    default = 1,
    action = function(v)
      self.model:set_voice(i, v - 1)
    end,
    allow_pmap = false,
  }
  params:add{type = 'control', id = 'bend' .. n, name = 'bend',
  controlspec = cs.new(0.2, 5.0, 'lin', 0.001, 1.0, ''),
    formatter = fmt.round(0.01),
    action = function(v) self.model:slot().rows[i]:set_bend(v) end,
  }
  params:add{type = 'control', id = 'n' .. n, name = 'n',
    controlspec = cs.new(2, 16, 'lin', 1, 16, ''),
    formatter = fmt.round(1),
    action = function(v) self.model:slot().rows[i]:set_n(v) end,
  }
  params:add{type = 'number', id = 'res' .. n, name = 'res',
    min = 4, max = 32, default = 4,
    action = function(v) self.model:slot().rows[i]:set_res(v) end,
  }
  params:add{type = 'number', id = 'offset' .. n, name = 'offset',
    min = -16, max = 16, default = 0,
    action = function(v) self.model:slot().rows[i]:set_offset(v) end,
  }
end

function Controller:add_midi_destination(i, c)
  params:add_group('midi ' .. c, 2)
  params:add{type = 'number', id = 'midi_out_device_' .. c, name = 'output device',
    min = 1, max = 4, default = 2,
    action = function(v)
      -- MAINT: assumes Output device is the second in the midi output chain
      local output_device = self.midi_outputs[i].devices[2]
      output_device:set_device(midi.connect(v))
    end,
    allow_pmap = false,
  }
  params:add{type = 'number', id = 'midi_out_ch_' .. c, name = 'output channel ',
    min = 1, max = 16, default = 1,
    action = function(v)
      -- MAINT: assumes Channel device is first in the midi output chain
      self.midi_outputs[i].devices[1]:set_channel(v)
    end,
  }
end

function Controller:add_crow_destination(i, c)
  params:add_group('crow ' .. c, 6)
  params:add{type = 'option', id = 'crow_velocity_' .. c, name = 'velocity',
    options = {'on', 'off'},
    default = 1,
    action = function(v)
      self.crow_outputs[i]:set_velocity(v == 1)
    end,
  }
  params:add{type = 'control', id = 'crow_amp_min' .. c, name = 'amp min',
    controlspec = cs.new(0, 1, 'lin', 0.001, 0, ''),
    formatter = fmt.round(0.01),
    action = function(v)
      self.crow_outputs[i]:set_amp_min(v)
    end,
  }
  params:add{type = 'control', id = 'crow_attack_' .. c, name = 'attack',
    controlspec = cs.new(0, 5, 'lin', 0.001, 0.025, ''),
    formatter = fmt.round(0.0001),
    action = function(v)
      self.crow_outputs[i]:set_attack(v)
    end,
  }
  params:add{type = 'control', id = 'crow_release_' .. c, name = 'release',
    controlspec = cs.new(0, 10, 'lin', 0.001, 0.1, ''),
    formatter = fmt.round(0.0001),
    action = function(v)
      self.crow_outputs[i]:set_release(v)
    end,
  }
  params:add{type = 'control', id = 'crow_pitch_slew_' .. c, name = 'pitch slew',
    controlspec = cs.new(0, 5, 'lin', 0.001, 0.0, ''),
    formatter = fmt.round(0.0001),
    action = function(v)
      self.crow_outputs[i]:set_pitch_slew(v)
    end,
  }
  local slew_shapes = {'linear', 'sine', 'logarithmic', 'exponential', 'now', 'wait', 'over', 'under', 'rebound'}
  params:add{type = 'option', id = 'crow_pitch_slew_shape_' .. c, name = 'slew shape',
    options = slew_shapes,
    default = 1,
    action = function(v)
      self.crow_outputs[i]:set_pitch_slew_shape(slew_shapes[v])
    end,
  }
end

function Controller:add_random_params()
  params:add_group('random', 5)
  params:add{type = 'option', id = 'random_enable', name = 'randomize pitch',
    options = {'off', 'on'},
    default = 1,
    action = function(v) self.random_device.bypass = v == 1 end,
  }
  params:add{type = 'number', id = 'random_choices', name = 'choice',
    min = 1, max = 24, default = 1,
    action = function(v) self.random_device:set_choices(v) end,
  }
  params:add{type = 'number', id = 'random_scale', name = 'scale',
    min = 1, max = 24, default = 1,
    action = function(v) self.random_device:set_scale(v) end,
  }
  local sign_options = {'add', 'sub', 'bi'}
  params:add{type = 'option', id = 'random_sign', name = 'sign',
    options = {'add', 'subtract', 'bidirectional'},
    default = 1,
    action = function(v) self.random_device:set_sign(sign_options[v]) end,
  }
  params:add{type = 'control', id = 'random_chance', name = 'chance',
    controlspec = cs.new(0, 1, 'lin', 0.01, 0.1, ''),
    formatter = fmt.round(0.01),
    action = function(v) self.random_device:set_chance(v) end,
  }
end

function Controller:get_scale_names()
  local names = {}
  for _, scale in ipairs(mu.SCALES) do
    table.insert(names, string.lower(scale.name))
  end
  return names
end

function Controller:add_scale_params()
  params:add_group('scale', 4)
  params:add{type = 'option', id = 'scale_enable', name = 'constrain to scale',
    options = {'off', 'on'},
    default = 1,
    action = function(v) self.scale_device.bypass = v == 1 end,
  }
  local scale_options = self:get_scale_names()
  params:add{type = 'option', id = 'scale_which', name = 'scale',
    options = scale_options,
    default = 1,
    action = function(v) self.scale_device:set_scale(scale_options[v]) end,
  }
  params:add{type = 'number', id = 'scale_root', name = 'root',
    min = 0, max = 127, default = 0,
    formatter = function(param) return mu.note_num_to_name(param:get(), true) end,
    action = function(v) self.scale_device:set_root(v) end,
  }
  params:add{type = 'number', id = 'scale_octaves', name = 'octaves',
    min = 1, max = 10, default = 10,
    action = function(v) self.scale_device:set_octaves(v) end,
  }
end

function Controller:add_params()
  params:add_separator('tambla')

  params:add{type = 'number', id = 'active_pattern', name = 'active pattern',
    min = 1, max = 4, default = 1,
    action = function(v) self.model:select_slot(v) end,
  }
  params:add{type = 'option', id = 'chance_mod', name = 'chance',
    options = {'off', 'on'},
    default = 1,
    action = function(v) self.chance_mod = v == 2 end,
  }
  params:add{type = 'control', id = 'chance_boost', name = 'chance boost',
    controlspec = cs.new(0, 1, 'lin', 0.01, 0, ''),
    formatter = fmt.round(0.01),
    action = function(v) self.model:set_chance_boost(v) end,
  }
  params:add{type = 'control', id = 'velocity_scale', name = 'velocity scale',
    controlspec = cs.new(0, 1, 'lin', 0.01, 1, ''),
    formatter = fmt.round(0.01),
    action = function(v) self.model:set_velocity_scale(v) end,
  }
  params:add{type = 'option', id = 'velocity_mod', name = 'velocity mod',
    options = {'off', 'on'},
    default = 2,
    action = function(v) self.velocity_mod = v == 2 end,
  }
  params:add{type = 'option', id = 'length_mod', name = 'length mod',
    options = {'off', 'on'},
    default = 2,
    action = function(v) self.length_mod = v == 2 end,
  }
  params:add{type = 'option', id = 'input_hold', name = 'input hold',
    options = {'off', 'on'},
    default = 1,
    action = function(v) self.hold_setter(v == 2) end,
  }
  params:add{type = 'number', id = 'transpose', name = 'transpose',
    min = -24, max = 24, default = 0,
    action = function(v)
      if self.transposer then
        self.transposer:set_semitones(v)
      end
    end,
  }
  params:add{type = 'option', id = 'playhead_sync', name = 'sync',
    options = {'all', 'note'},
    default = 1,
    action = function(v) self.note_sync = v == 2 end,
  }

  self:add_random_params()
  self:add_scale_params()

  params:add_separator('tambla: rows')

  for i = 1, self.model.NUM_ROWS do
    self:add_row_params(i)
  end

  params:add_separator('tambla: i/o')

  params:add{type = "number", id = "midi_in_device", name = "midi input device",
    min = 1, max = 4, default = 1,
    action = function(v)
      if self.input_device then
        self.input_device:set_device(midi.connect(v))
      end
    end,
  }

  params:add{type = 'option', id = 'output', name = 'output (default)',
    options = {'polyperc', 'midi a', 'midi b', 'midi c', 'midi d', 'crow a', 'crow b', 'wsyn'},
    default = 1,
    action = function(v) self.output_router:set_default(v) end,
    allow_pmap = false,
  }

  params:add{type = 'option', id = 'output_logging', name = 'output logging',
    options = {'off', 'on'},
    default = 1,
    action = function(v) self.logger.bypass = v == 1 end,
  }

  for i, c in ipairs({'a', 'b', 'c', 'd'}) do
    self:add_midi_destination(i, c)
  end

  for i, c in ipairs({'a', 'b'}) do
    self:add_crow_destination(i, c)
  end

end

function Controller:process(event, output, state)
  if sky.is_key(event) then
    -- record key state for use in key chording ui
    self.key_z[event.n] = event.z
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