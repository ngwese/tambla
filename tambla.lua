include('sky/lib/prelude')
sky.use('sky/lib/device/make_note')
sky.use('sky/lib/device/arp')
sky.use('sky/lib/device/switcher')
sky.use('sky/lib/io/norns')
sky.use('sky/lib/engine/polysub')

local halfsecond = include('awake/lib/halfsecond')


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

function Row:set_res(r)
  self.res = util.clamp(math.floor(r), 4, 32)
  return self
end

function Row:set_n(n)
  self.n = util.clamp(math.floor(n), 2, 32)
  return self
end

function Row:set_bend(b)
  self.bend = util.clamp(b, 0.2, 5)
  return self
end

function Row:set_offset(o)
  self.offset = math.floor(o)
  return self
end

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
        if note ~= nil and step.chance > 0 then -- math.random() < step.chance then
          local velocity = math.floor(note.vel * step.velocity)
          local duration = 1/16 -- FIXME: this is based on row res, step count and step duration scaler
          local generated = sky.mk_note_on(note.note, velocity, note.ch)
          generated.duration = duration
          output(generated) -- requires a make_note device to produce note off
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
  layout_vertical(x, y, self.widgets)
end

function TamblaRender:render(event, props)
  local rows = self.model.rows
  local beat = event.beat -- MAINT: redraw events always have beats?
  for i, r in ipairs(self.widgets) do
    r:draw(rows[i], beat)
  end
end

--
--
--

tambla = Tambla{
  tick_period = 1/32,
}

main = sky.Chain{
  sky.Held{ debug = true },
  TamblaNoteGen(tambla),
  sky.MakeNote{},
  sky.Switcher{
    which = 1,
    sky.Output{},
    sky.PolySub{},
  },
  sky.Logger{
    filter = tambla.is_tick,
  },
  function(event, output)
    if tambla.is_tick(event) then output(sky.mk_redraw()) end
  end,
  sky.NornsDisplay{
    screen.clear,
    TamblaRender(0, 2, tambla),
    screen.update,
  }
}

input1 = sky.Input{
  name = "AXIS-64",
  chain = main,
}

input2 = sky.NornsInput{
  chain = sky.Chain{
    -- sky.Logger{},
    -- for testing purposes
    function(event, output)
      output(event)
      if sky.is_key(event) and event.num == 3 and event.z == 1 then
        tambla:randomize()
        output(sky.mk_redraw())
      end
    end,
    sky.Forward(main)
  },
}

--
-- script logic
--

function init()
  halfsecond.init()

  -- halfsecond
  params:set('delay', 0.13)
  params:set('delay_rate', 0.95)
  params:set('delay_feedback', 0.27)
  -- polysub
  params:set('amprel', 0.1)

  tambla:randomize()
end

