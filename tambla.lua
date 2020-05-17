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
  self.chance = chance or 0      -- [0, 1] for probability
  self.velocity = velocity or 1  -- [0, 1]
  self.duration = duration or 1  -- [0, 1] where duration is a multiplier on 1/row.res
end

function Step:is_active()
  return self.chance > 0
end

function Step:clear()
  self.chance = 0
  self.velocity = 1
  self.duration = 1
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
  self:steps_clear()
  self._scaler = sky.build_scalex(0, 1, 0, 1)
end

function Row:set_res(r) self.res = util.clamp(math.floor(r), 4, 32) end
function Row:set_n(n) self.n = util.clamp(math.floor(n), 2, 32) end
function Row:set_bend(b) self.bend = util.clamp(b, 0.2, 5) end
function Row:set_offset(o) self.offset = math.floor(o) end

function Row:steps_clear()
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

--
-- Tambla
--

local Tambla = sky.Object:extend()
Tambla.TICK_EVENT = 'TAMBLA_TICK'

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
  self.prop_codes = {'b', 'o', 'r', 'n',}
  self.prop_names = {'bend', 'offset', 'res', 'n'}
end

-- row selection state
function Tambla:select_row(i) self._selected_row = util.clamp(math.floor(i), 1, 4) end

function Tambla:selected_row_idx() return self._selected_row end

function Tambla:selected_row() return self.rows[self._selected_row] end

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

function Tambla:randomize()
  for i, r in ipairs(self.rows) do
    r:randomize()
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

function TamblaRender:new(x, y, model)
  self.topleft = { x, y }
  self.model = model
  self.widgets = {}
  for i, r in ipairs(self.model.rows) do
    table.insert(self.widgets, RowWidget())
  end
  layout_vertical(x + 4, y, self.widgets)
  screen.font_face(0)
  screen.font_size(8)
end

function TamblaRender:render(event, props)
  local rows = self.model.rows
  local beat = event.beat -- MAINT: redraw events always have beats?
  for i, r in ipairs(self.widgets) do
    r:draw(rows[i], beat)
  end

  -- selection carat
  local y = self.model._selected_row * RowWidget.HEIGHT - 2
  screen.level(15)
  screen.rect(self.topleft[1], y, 2, 2)

  -- property label
  local t = self.model:selected_prop_code()
  screen.move(110, 7)
  screen.text(t)

  -- property value
  local v = self.model:selected_prop_value()
  screen.move(110, 16)
  screen.text(v)
end

--
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

local TamblaControl = sky.Device:extend()

function TamblaControl:new(model)
  TamblaControl.super.new(self)
  self.model = model

  self.row_count = #model.rows
  self.row_acc = 1

  self.prop_count = 4 -- FIXME: get this from the model
  self.prop_acc = 1
end

function TamblaControl:add_row_params(i)
  local n = tostring(i)
  -- params:add_separator('row ' .. n)
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

function TamblaControl:process(event, output, state)
  output(event)
  if sky.is_key(event) then
    if event.num == 3 and event.z == 1 then
      self.model:randomize()
      output(sky.mk_redraw())
    end
  elseif sky.is_enc(event) then
    if event.num == 1 then
      self.row_acc = util.clamp(self.row_acc + (event.delta / 10), 1, self.row_count)
      self.model:select_row(self.row_acc)
      --print("select", self.model._selected_row)
    elseif event.num == 2 then
      self.prop_acc = util.clamp(self.prop_acc + (event.delta / 20), 1, self.prop_count)
      self.model:select_prop(self.prop_acc)
      --print("prop", self.model:selected_prop_name())
    elseif event.num == 3 then
      -- local row = self.model:selected_row()
      -- row:set_bend(row.bend + (event.delta / 100))
      -- print("bend", self.model._selected_row, row.bend)
      local idx = self.model:selected_row_idx()
      local id = self.model:selected_prop_name() .. tostring(idx)
      params:delta(id, event.delta)
    end
  end
end

controls = TamblaControl(tambla)

input2 = sky.NornsInput{
  chain = sky.Chain{
    -- sky.Logger{},
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

