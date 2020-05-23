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
Row.MAX_STEPS = 16

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
  for i = 1, self.MAX_STEPS do
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

function Row:store()
  local steps = {}
  for i, s in ipairs(self.steps) do
    table.insert(steps, s:store())
  end
  return { __type = 'Row', n = self.n, res = self.res, bend = self.bend, offset = self.offset, steps = steps }
end

function Row:load(props)
  if props.__type ~= 'Row' then
    error('cannot load row: incorrect type')
  end

  self:new(props)
  self.steps = {}
  for i, s in ipairs(props.steps) do
    local step = Step()
    step:load(s)
    table.insert(self.steps, step)
  end
end

--
-- Pattern
--

local Pattern = sky.Object:extend()
Pattern.NUM_ROWS = 4
Pattern.MODEL_VERSION = 1

function Pattern:new(props)
  self.rows = {
    Row{ n = 16 },
    Row{ n = 8  },
    Row{ n = 8  },
    Row{ n = 16 },
  }
end

function Pattern:randomize()
  for i, r in ipairs(self.rows) do
    r:randomize()
  end
end

function Pattern:store()
  local rows = {}
  for i, r in ipairs(self.rows) do
    table.insert(rows, r:store())
  end
  return { __type = 'Pattern', __version = self.MODEL_VERSION, rows = rows }
end

function Pattern:load(props)
  if props.__type ~= 'Pattern' and props.__version ~= self.MODEL_VERSION then
    error('cannot load pattern: incorrect type or version')
  end

  self:new(props)
  self.rows = {}
  for i, r in ipairs(props.rows) do
    local row = Row(r)
    row:load(r)
    table.insert(self.rows, row)
  end
end

--
-- Tambla
--
local Tambla = sky.Object:extend()
Tambla.NUM_ROWS = Pattern.NUM_ROWS
Tambla.NUM_SLOTS = 1 -- eventually 4 (or more)
Tambla.TICK_EVENT = 'TAMBLA_TICK'
Tambla.MODEL_VERSION = 1

function Tambla:new(props)
  self.tick_period = props.tick_period or 1/32
  self.slots = {}
  if props.slots then
    for _, p in ipairs(props.slots) do
      table.insert(self.slots, p)
    end
  else
    local p = Pattern()
    p:randomize()
    table.insert(self.slots, p)
  end
  self:select_slot(1)
end

function Tambla:slot(num)
  if num ~= nil then
    return self.slots[num]
  end
  return self.slots[self._selected_slot]
end

function Tambla:select_slot(i)
  self._selected_slot = util.clamp(math.floor(i), 1, Tambla.NUM_SLOTS)
end

function Tambla.mk_tick()
  return { type = Tambla.TICK_EVENT, beat = clock.get_beats() }
end

function Tambla.is_tick(event)
  return event.type == Tambla.TICK_EVENT
end

function Tambla:store()
  local slots = {}
  for i, s in ipairs(self.slots) do
    table.insert(slots, s:store())
  end
  return { __type = 'Tambla', __version = self.MODEL_VERSION, tempo = clock.get_tempo(), slots = slots, tick_period = self.tick_period }
end

function Tambla:load(props)
  if props.__type ~= 'Tambla' and props.__version ~= self.MODEL_VERSION then
    error('cannot load set: incorrect type or version')
  end

  self:new(props)
  self.slots = {}
  for i, s in ipairs(props.slots) do
    local p = Pattern(s)
    p:load(s)
    table.insert(self.slots, p)
  end
end



--
-- module
--
return {
  Tambla = Tambla,
  Pattern = Pattern,
  Row = Row,
  Step = Step,
}