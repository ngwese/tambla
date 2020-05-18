include('sky/lib/prelude')
sky.use('sky/lib/device/make_note')
sky.use('sky/lib/device/arp')
sky.use('sky/lib/device/switcher')
sky.use('sky/lib/io/norns')
sky.use('sky/lib/engine/polysub')

--local halfsecond = include('awake/lib/halfsecond')
local fmt = require('formatters')
local cs = require('controlspec')

--
-- Step
--

local Step = sky.Object:extend()

function Step:new(chance, velocity, duration)
  self:set_chance(chance or 0)      -- [0, 1] for probability
  self:set_velocity(velocity or 0)  -- [0, 1]
  self:set_duration(duration or 1)  -- [0.1, 1] where duration is a multiplier on 1/row.res
end

function Step:set_chance(c) self.chance = util.clamp(c, 0, 1) end
function Step:set_velocity(v) self.velocity = util.clamp(v, 0, 1) end
function Step:set_duration(d) self.duration = util.clamp(d, 0.1, 1) end

function Step:is_active()
  return self.chance > 0 and self.velocity > 0
end

function Step:clear()
  self.chance = 0
  self.velocity = 0
  self.duration = 0.5
end

function Step:load(props)
  self:new(props.chance, props.velocity, props.duration)
end

function Step:store()
  return { __type = 'Step', chance = self.chance, velocity = self.velocity, duration = self.duration }
end

--
-- Row
--

local Row = sky.Object:extend()

local MAX_STEPS = 16

function Row:new(props)
  self:set_n(props.n or 8)
  self:set_res(props.res or 4)
  self:set_bend(props.bend or 1.0)
  self:set_offset(props.offset or 0)
  self.steps = {}
  self:clear()
  self._scaler = sky.build_scalex(0, 1, 0, 1)
end

function Row:set_res(r) self.res = util.clamp(math.floor(r), 4, 32) end
function Row:set_n(n) self.n = util.clamp(math.floor(n), 2, 32) end
function Row:set_bend(b) self.bend = util.clamp(b, 0.2, 5) end
function Row:set_offset(o) self.offset = math.floor(o) end

function Row:clear()
  for i = 1, MAX_STEPS do
    self.steps[i] = Step(0) -- zero chance
  end
end

function Row:randomize()
  for i, s in ipairs(self.steps) do
    local chance = math.random()
    if chance > 0.5 then chance = math.random() else chance = 0 end -- random chance for ~20% of steps (but not really)
    if chance > 0 then
      s.chance = chance
      s.velocity = util.linlin(0, 1, 0.2, 1, math.random())
      s.duration = util.linlin(0, 1, 0.25, 1, math.random())
    else
      s:clear()
    end
  end
end

function Row:head_position(beats)
  local _, f = math.modf(beats / self.res)
  return self._scaler(f, self.bend)
end

function Row:step_index(beats)
  return 1 + math.floor(self:head_position(beats) * self.n)
end

function Row:load(props)
  self:new(props)
  for i, s in ipairs(props.steps) do
    self.steps[i]:load(props.steps[i])
  end
end

function Row:store()
  local steps = {}
  for i, s in ipairs(self.steps) do
    table.insert(steps, s:store())
  end
  return { __type = 'Row', n = self.n, res = self.res, bend = self.bend, offset = self.offset, steps = steps }
end


--
-- Tambla
--

local Tambla = sky.Object:extend()
Tambla.TICK_EVENT = 'TAMBLA_TICK'
Tambla.MODE_CHANGE_EVENT = 'TAMBLA_MODE'
Tambla.MODE_PLAY = 1
Tambla.MODE_EDIT = 2
Tambla.MODE_MACRO = 3

function Tambla:new(props)
  self.rows = {
    Row{ n = 16 },
    Row{ n = 8  },
    Row{ n = 8  },
    Row{ n = 16 },
  }

  self.tick_period = props.tick_period or 1/32

  self:select_row(1)
  self:select_prop(1)
  self:select_step(1)

  self.prop_codes = {'b', 'o', 'r', 'n',}
  self.prop_names = {'bend', 'offset', 'res', 'n'}

  self.mode = Tambla.MODE_PLAY
  self.mode_codes = {'P', 'E', 'M'}
  self.mode_names = {'play', 'edit', 'macro'}
end

-- row selection state
function Tambla:select_row(i)
  self._selected_row = util.clamp(math.floor(i), 1, 4)
end

function Tambla:selected_row_idx() return self._selected_row end

function Tambla:selected_row() return self.rows[self._selected_row] end

function Tambla:selected_row_n() return self:selected_row().n end

-- step selection state
function Tambla:select_step(i)
  self._selected_step = util.clamp(math.floor(i), 1, self:selected_row_n())
end

function Tambla:selected_step_idx() return self._selected_step end

function Tambla:selected_step()
  local r = self:selected_row()
  return r.steps[self:selected_step_idx()]
end

-- property selection state
function Tambla:select_prop(i) self._selected_prop = util.clamp(math.floor(i), 1, 4) end

function Tambla:selected_prop_code()
  return self.prop_codes[self._selected_prop]
end

function Tambla:selected_prop_name()
  return self.prop_names[self._selected_prop]
end

function Tambla:selected_prop_value()
  local r = self:selected_row()
  local k = self.prop_names[self._selected_prop]
  return r[k]
end

function Tambla.mk_tick()
  return { type = Tambla.TICK_EVENT, beat = clock.get_beats() }
end

function Tambla.is_tick(event)
  return event.type == Tambla.TICK_EVENT
end

function Tambla.mk_mode_change(which)
  return { type = Tambla.MODE_CHANGE_EVENT, mode = which }
end

function Tambla.is_mode_change(event)
  return event.type == Tambla.MODE_CHANGE_EVENT
end

function Tambla:select_mode(which)
  self.mode = which
end

function Tambla:selected_mode_code()
  return self.mode_codes[self.mode]
end

function Tambla:selected_mode_name()
  return self.mode_names[self.mode]
end

function Tambla:randomize()
  for i, r in ipairs(self.rows) do
    r:randomize()
  end
end

function Tambla:store()
  local rows = {}
  for i, r in ipairs(self.rows) do
    table.insert(rows, r:store())
  end
  return { __type = 'Tambla', rows = rows, tick_period = self.tick_period }
end

function Tambla:load(props)
  self:new(props)
  for i,r in ipairs(props.rows) do
    r:load(props.rows[i])
  end
end

--
-- TamblaNoteGen
--

local TamblaNoteGen = sky.Device:extend()

function TamblaNoteGen:new(model)
  TamblaNoteGen.super.new(self)
  self.model = model
  self._scheduler = nil
  self._notes = {}
  self._last_index = {}
  for i = 1, #self.model.rows do
    self._last_index[i] = 0
  end
end

function TamblaNoteGen:device_inserted(chain)
  self._scheduler = chain:scheduler(self)
  self._scheduler:run(function(output)
    while true do
      clock.sleep(self.model.tick_period)
      output(self.model.mk_tick())
    end
  end)
end

function TamblaNoteGen:device_removed(chain)
  self._scheduler = nil
end

--
-- TODO: enable/disable chance evaluation
--

function TamblaNoteGen:process(event, output, state)
  if self.model.is_tick(event) then
    output(event) -- pass the tick along
    -- determine if a not should be generated
    local beat = event.beat
    for i, r in ipairs(self.model.rows) do
      local idx = r:step_index(beat)
      if idx ~= self._last_index[i] then
        -- we are at a new step
        -- print("row", i, "step", idx)
        local step = r.steps[idx] -- which step within row
        local note = self._notes[i] -- note which matches row based on order held
        if note ~= nil then
          --if math.random() < step.chance then
          if step.chance > 0 then
            local velocity = math.floor(note.vel * step.velocity)
            --local duration = 1/16 -- FIXME: this is based on row res, step count and step duration scaler
            --local duration = 1 / (step.duration * 32 / r.res) --- ??? waaaat
            local duration = step.duration * (1 / (32 / r.res)) --- ??? waaaat
            local generated = sky.mk_note_on(note.note, velocity, note.ch)
            generated.duration = duration
            output(generated) -- requires a make_note device to produce note off
          else
            --print("skip:", i, idx)
          end
        end
      end
      -- note that we've looked at this step
      self._last_index[i] = idx
    end
  elseif sky.is_type(event, sky.HELD_EVENT) then
    self._notes = event.notes
  else
    output(event)
  end
end

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
-- TamblaRender
--

local TamblaRender = sky.Object:extend()
TamblaRender.PARAM_LEFT = 128
TamblaRender.PARAM_SPACING = 8
TamblaRender.LABEL_LEVEL = 3
TamblaRender.VALUE_LEVEL = 12

function TamblaRender:new(x, y, model)
  self.topleft = { x, y }

  self.model = model
  self.widgets = {}
  for i, r in ipairs(self.model.rows) do
    table.insert(self.widgets, RowWidget())
  end
  layout_vertical(x + 4, y, self.widgets)

  self.mode_render = {self.render_play, self.render_edit, self.render_macro}
end

function TamblaRender:draw_mode()
  screen.level(self.LABEL_LEVEL)
  screen.font_face(0)
  screen.font_size(8)
  screen.move(self.PARAM_LEFT, 58)
  screen.text_right(self.model:selected_mode_code())
end

function TamblaRender:draw_rows(beat)
  local rows = self.model.rows
  for i, r in ipairs(self.widgets) do
    r:draw(rows[i], beat)
  end
end

function TamblaRender:draw_caret()
  -- selection carat
  local y = self.model._selected_row * RowWidget.HEIGHT - 2
  screen.level(15)
  screen.rect(self.topleft[1], y, 2, 2)
end

function TamblaRender:render_play(event, props)
  self:draw_rows(event.beat)
  self:draw_caret()
  self:draw_mode()
  self:draw_param(8, self.model:selected_prop_code(), self.model:selected_prop_value())
end

function TamblaRender:draw_step_select()
  local idx = self.model:selected_row_idx()
  local row = self.model:selected_row()
  local widget = self.widgets[idx]
  widget:draw_step_selection(row, self.model:selected_step_idx())
end

function TamblaRender:draw_param(y, name, value)
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

function TamblaRender:render_edit(event, props)
  self:draw_rows(event.beat)
  self:draw_step_select()
  self:draw_caret()
  self:draw_mode()

  local step = self.model:selected_step()
  local y = 8
  y = self:draw_param(y, 'v', util.round(step.velocity, 0.01))
  y = self:draw_param(y, 'd', util.round(step.duration, 0.01))
  y = self:draw_param(y, '%', util.round(step.chance, 0.01))
end

function TamblaRender:render_macro(event, props)
  self:draw_mode()
end

function TamblaRender:render(event, props)
  local f = self.mode_render[self.model.mode]
  f(self, event, props)
end

--
-- Model and event processing chain
--

tambla = Tambla{
  tick_period = 1/64,
}

display = sky.Chain{
  sky.NornsDisplay{
    screen.clear,
    TamblaRender(0, 2, tambla),
    screen.update,
  }
}

main = sky.Chain{
  sky.Held{ debug = false },
  TamblaNoteGen(tambla),
  sky.MakeNote{},
  sky.Switcher{
    which = 1,
    sky.Output{ name = "UM-ONE" },
    sky.Output{ name = "ContinuuMini" },
    -- sky.PolySub{},
  },
  sky.Logger{
    bypass = true,
    filter = tambla.is_tick,
  },
  function(event, output)
    if tambla.is_tick(event) then output(sky.mk_redraw()) end
  end,
  sky.Forward(display),
}

input1 = sky.Input{
  name = "AXIS-64",
  chain = main,
}

--
-- TamblaControl
--

local TamblaControl = sky.Device:extend()

function TamblaControl:new(model)
  TamblaControl.super.new(self)
  self.model = model

  self.row_count = #model.rows
  self.row_acc = 1

  self.step_acc = 1

  self.prop_count = 4 -- FIXME: get this from the model
  self.prop_acc = 1

  self.key_z = {0, 0, 0}

  self.mode_process_f = {self.process_play, self.process_edit, self.process_macro}
  self:switch_mode(Tambla.MODE_PLAY)
end

function TamblaControl:add_row_params(i)
  local n = tostring(i)
  params:add{type = 'option', id = 'chance' .. n, name = 'chance ' .. n,
    options = {'on', 'off'},
    default = 1
  }
  params:add{type = 'option', id = 'velocity_mod' .. n, name = 'velocity mod ' .. n,
    options = {'on', 'off'},
    default = 1
  }
  params:add{type = 'option', id = 'length_mod' .. n, name = 'length mod ' .. n,
    options = {'on', 'off'},
    default = 1
  }
  params:add{type = 'control', id = 'bend' .. n, name = 'bend ' .. n,
    controlspec = cs.new(0.2, 5.0, 'lin', 0.005, 1.0, ''),
    formatter = fmt.round(0.01),
    action = function(v) self.model.rows[i]:set_bend(v) end,
  }
  params:add{type = 'control', id = 'n' .. n, name = 'n ' .. n,
    controlspec = cs.new(2, 16, 'lin', 1, 16, ''),
    formatter = fmt.round(1),
    action = function(v) self.model.rows[i]:set_n(v) end,
  }
  params:add{type = 'control', id = 'res' .. n, name = 'res ' .. n,
    controlspec = cs.new(4, 32, 'lin', 1, 4, ''),
    formatter = fmt.round(1),
    action = function(v) self.model.rows[i]:set_res(v) end,
  }
  params:add{type = 'control', id = 'offset' .. n, name = 'offset ' .. n,
    controlspec = cs.new(-16, 16, 'lin', 1, 0, ''),
    formatter = fmt.round(1),
    action = function(v) self.model.rows[i]:set_offset(v) end,
  }
end

function TamblaControl:switch_mode(mode)
  local f = self.mode_process_f[mode]
  if f == nil then
    error('invalid mode: ' .. tostring(mode))
  end
  self.mode_process = f
  self.model:select_mode(mode)
  return self.model.mk_mode_change(mode)
end

function TamblaControl:process(event, output, state)
  if sky.is_key(event) then
    -- record key state for use in key chording ui
    self.key_z[event.num] = event.z
  end
  self.mode_process(self, event, output, state)
end

function TamblaControl:process_edit(event, output, state)
  output(event)
  if sky.is_key(event) then
    if event.num == 2 and event.z == 1 then
      if self.key_z[1] == 1 then
        -- key 2 w/ key 1 held
        output(self:switch_mode(Tambla.MODE_PLAY))
      elseif self.key_z[3] == 1 then
        -- key 2 w/ key 3 held
        print('randomize row')
        local row = self.model:selected_row()
        row:randomize()
      else
        -- key 2 action
        print('k2 action')
      end
    elseif event.num == 3 and event.z == 1 then
      if self.key_z[1] == 1 then
        -- key 3 w/ key 1 held
      elseif self.key_z[2] == 1 then
        -- key 3 w/ key 2 held
        print('clear row')
        local row = self.model:selected_row()
        row:clear()
      else
        -- key 3 action
        print('k3 action')
      end
    end
  elseif sky.is_enc(event) then
    if event.num == 1 then
      if self.key_z[1] == 0 then
        -- select step
        self.step_acc = util.clamp(self.step_acc + (event.delta / 5), 1, self.model:selected_row_n())
        self.model:select_step(self.step_acc)
      else
        -- select row
        self.row_acc = util.clamp(self.row_acc + (event.delta / 10), 1, self.row_count)
        self.model:select_row(self.row_acc)
      end
    elseif event.num == 2 then
      local step = self.model:selected_step()
      if self.key_z[2] == 1 then
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
      local step = self.model:selected_step()
      if step ~= nil then
        step:set_duration(step.duration + (event.delta / 20))
      end
    end
  end
end

function TamblaControl:process_macro(event, output, state)
  output(event)
  if sky.is_key(event) then
    if event.num == 3 and event.z == 1 then
      if self.key_z[1] == 1 then
        output(self:switch_mode(Tambla.MODE_PLAY))
      else
        -- key 3 action
      end
    end
  end
end

function TamblaControl:process_play(event, output, state)
  output(event)
  if sky.is_key(event) then
    if event.num == 2 and event.z == 1 then
      if self.key_z[1] == 1 then
        output(self:switch_mode(Tambla.MODE_MACRO))
        print("switch macro")
      elseif self.key_z[3] == 1 then
        -- key 2 w/ key 3 held
        self.model:randomize()
        output(sky.mk_redraw())
      else
        -- play, key 2 action
        print("play key 2 action")
      end
    elseif event.num == 3 and event.z == 1 then
      if self.key_z[1] == 1 then -- mode shift key
        print("switch edit")
        output(self:switch_mode(Tambla.MODE_EDIT))
      else
        -- play, key 3 action
        print("play key 3 action")
      end
    end
  elseif sky.is_enc(event) then
    if event.num == 1 then
      if self.key_z[1] == 1 then
        self.row_acc = util.clamp(self.row_acc + (event.delta / 10), 1, self.row_count)
        self.model:select_row(self.row_acc)
      end
    elseif event.num == 2 then
      self.prop_acc = util.clamp(self.prop_acc + (event.delta / 10), 1, self.prop_count)
      self.model:select_prop(self.prop_acc)
    elseif event.num == 3 then
      local idx = self.model:selected_row_idx()
      local id = self.model:selected_prop_name() .. tostring(idx) -- FIXME: avoid string construction?
      local delta = event.delta
      if self.key_z[3] == 1 then
        -- fine tuning
        delta = delta / 10.0
      end
      params:delta(id, event.delta)
    end
  end
end

controls = TamblaControl(tambla)

input2 = sky.NornsInput{
  chain = sky.Chain{
    --sky.Logger{},
    controls,
    sky.Forward(display)
  },
}

--
-- script logic
--

function init()
  -- halfsecond.init()

  -- halfsecond
  -- params:set('delay', 0.13)
  -- params:set('delay_rate', 0.95)
  -- params:set('delay_feedback', 0.27)
  -- polysub
  -- params:set('amprel', 0.1)

  -- tambla
  for i = 1,4 do
    controls:add_row_params(i)
  end

  tambla:randomize()
end

