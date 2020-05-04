include('sky/lib/prelude')
sky.use('sky/lib/device/make_note')
sky.use('sky/lib/device/arp')
sky.use('sky/lib/io/norns')

--
-- Step
--

local Step = {}
Step.__index = Step

function Step.new(chance, velocity, duration)
  local o = setmetatable({}, Step)
  o.chance = chance or 0      -- [0, 1] for probability
  o.velocity = velocity or 1  -- [0, 1]
  o.duration = duration or 1  -- [0, 1] where duration is a multiplier on 1/row.res
  return o
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

local Row = {}
Row.__index = Row

local MAX_STEPS = 16

function Row.new(props)
  local o = setmetatable(props or {}, Row)
  o:set_n(o.n or 8)
  o:set_res(o.res or 4)
  o:set_bend(o.bend or 1.0)
  o:set_offset(o.offset or 0)
  o.steps = {}
  o:steps_clear()
  o._scaler = sky.build_scalex(0, 1, 0, 1)
  return o
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
    self.steps[i] = Step.new(0) -- zero chance
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

--
-- Tambla
--

local Tambla = {}
Tambla.__index = Tambla
Tambla.TICK_EVENT = 'TAMBLA_TICK'

function Tambla.new(props)
  local self = setmetatable({}, Tambla)
  self.rows = {
    Row.new{ n = 14 },
    Row.new{ n = 8  },
    Row.new{ n = 8  },
    Row.new{ n = 16 },
  }
  self.tick_period = props.tick_period or 1/32
  return self
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

local TamblaNoteGen = sky.Device()
TamblaNoteGen.__index = TamblaNoteGen

function TamblaNoteGen.new(model)
  local o = setmetatable({}, TamblaNoteGen)
  o._scheduler = nil
  o.model = model
  return o
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
    -- update tick
    --print("got tick")
    output(event)
  elseif sky.is_type(event, sky.HELD_EVENT) then
    -- consume held notes
    print("got held notes")
  else
    output(event)
  end
end


--
-- RowWidget
--

local RowWidget = {}
RowWidget.__index = RowWidget
RowWidget.HEIGHT = 15
RowWidget.STEP_WIDTH = 6
RowWidget.BAR_WIDTH = 4
RowWidget.BAR_HEIGHT = 10

function RowWidget.new(x, y)
  local o = setmetatable({}, RowWidget)
  o.topleft = {x or 1, y or 1}
  return o
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

local TamblaRender = {}
TamblaRender.__index = TamblaRender

function TamblaRender.new(x, y, model)
  local self = setmetatable({}, TamblaRender)
  self.topleft = { x, y }
  self.model = model
  self.widgets = {}
  for i, r in ipairs(self.model.rows) do
    table.insert(self.widgets, RowWidget.new())
  end
  layout_vertical(x, y, self.widgets)
  return self
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

tambla = Tambla.new{
  tick_period = 1/32,
}

main = sky.Chain{
  sky.Held{},
  TamblaNoteGen.new(tambla),
  sky.Output{},
  sky.Logger{
    filter = tambla.is_tick,
  },
  function(event, output)
    if tambla.is_tick(event) then output(sky.mk_redraw()) end
  end,
  sky.NornsDisplay{
    screen.clear,
    TamblaRender.new(0, 2, tambla),
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
  tambla:randomize()
end

