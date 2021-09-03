--
-- Step
--

local Step = sky.Object:extend()

function Step:new(chance, velocity, duration, aux)
  self:set_chance(chance or 0)      -- [0, 1] for probability
  self:set_velocity(velocity or 0)  -- [0, 1]
  self:set_duration(duration or 1)  -- [0.1, 1] where duration is a multiplier on 1/row.res
  self:set_aux(aux or 0)
end

function Step:set_chance(c) self.chance = util.clamp(c, 0, 1) end
function Step:set_velocity(v) self.velocity = util.clamp(v, 0, 1) end
function Step:set_duration(d) self.duration = util.clamp(d, 0.1, 1) end
function Step:set_aux(v) self.aux = util.clamp(v, 0, 1) end

function Step:is_active()
  return self.chance > 0 and self.velocity > 0
end

function Step:clear()
  self.chance = 0
  self.velocity = 0
  self.duration = 0.5
  self.aux = 0
end

function Step:load(props)
  self:new(props.chance, props.velocity, props.duration, props.aux)
end

function Step:store()
  return { __type = 'Step', chance = self.chance, velocity = self.velocity, duration = self.duration, aux = self.aux }
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
      s:set_chance(chance)
      s:set_velocity(util.linlin(0, 1, 0.2, 1, math.random()))
      s:set_duration(util.linlin(0, 1, 0.25, 1, math.random()))
      s:set_aux(math.random())
    else
      s:clear()
    end
  end
  return self
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
  return self
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
Tambla.MAX_SLOTS = 4
Tambla.TICK_EVENT = 'TAMBLA_TICK'
Tambla.MODEL_VERSION = 1

function Tambla:new(props)
  self.tick_period = props.tick_period or 1/32
  self.slots = {}
  self.row_sync = {}

  self.beat_offset = 0
  self.beat_stopped = 0
  self.running = true

  if props.slots then
    for _, p in ipairs(props.slots) do
      table.insert(self.slots, p)
      table.insert(self.row_sync, 0)
    end
  else
    local p = Pattern()
    p:randomize()
    table.insert(self.slots, p)
    table.insert(self.row_sync, 0)
  end
  self._slot_count = #self.slots
  self:select_slot(1)
  self:set_chance_boost(0)
  self:set_velocity_scale(1)
end

function Tambla:slot(num)
  if num ~= nil then
    return self.slots[num]
  end
  return self.slots[self._selected_slot]
end

function Tambla:slot_count()
  return self._slot_count
end

function Tambla:select_slot(i)
  self._selected_slot = util.clamp(math.floor(i), 1, self._slot_count)
end

function Tambla:selected_slot_idx()
  return self._selected_slot
end

function Tambla:set_sync(i, beat)
  self.row_sync[i] = math.floor(beat)
end

function Tambla:sync(i, beat)
  return beat - (self.row_sync[i] or 0)
end

function Tambla:transport_start()
  local _, f = math.modf(clock.get_beats())
  self.beat_offset = f
  self.running = true
  print("Tambla:transport_start", self.running, self.beat_offset)
end

function Tambla:transport_stop()
  if self.running then
    self.running = false
    self.beat_stopped = clock.get_beats() - self.beat_offset
    print("Tambla:transport_stop", self.running, self.beat_stopped)
  end
end

function Tambla:set_chance_boost(boost)
  self._chance_boost = boost
end

function Tambla:chance_boost()
  return self._chance_boost
end

function Tambla:set_velocity_scale(scale)
  self._velocity_scale = scale
end

function Tambla:velocity_scale()
  return self._velocity_scale
end

function Tambla:mk_tick()
  local tick = nil
  if self.running then
    tick = { type = Tambla.TICK_EVENT, beat = clock.get_beats() - self.beat_offset }
  else
    tick = { type = Tambla.TICK_EVENT, beat = self.beat_stopped }
  end
  return tick
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

  -- NB: alters global clock tempo, this might need to behavior which can be
  -- toggled off
  if props.tempo then
    params:set('clock_tempo', props.tempo)
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