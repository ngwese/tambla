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
function Step:set_duration(d) self.duration = util.clamp(d, 0.1, 4) end
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
-- Follow
--

function action_null(row_num, model)
end

function build_action_relative(offset)
  return function(row_num, model)
    -- NOTE: select_row_slot clamps but here we wrap
    local slot_num = model.row_slot[row_num]
    print("ROW REL: slot_num", slot_num)
    -- local n = ((slot_num + offset) % model.MAX_SLOTS) + 1
    local n = util.wrap(slot_num + offset, 1, model.MAX_SLOTS)
    print("ROW REL", row_num, slot_num)
    model:select_row_slot(row_num, n)
  end
end

function build_action_goto(slot_num)
  return function(row_num, model)
    print("ROW GOTO", row_num, slot_num)
    model:select_row_slot(row_name, slot_name)
  end
end

function action_stop(row_num, model)
  -- FIXME: is this really stop?
  print("STOPING ROW", row_num)
  model:set_row_is_running(row_num, false)
end


local Follow = sky.Object:extend()

function Follow:new(action)
  self.action = action or action_null;
end

function Follow:next(rows, current_index)
  return self.action(rows, current_index)
end

--
-- Follow: RepeatThen
--

local RepeatThen = Follow:extend()

function RepeatThen:new(bars, action)
  RepeatThen.super.new(self, action)
  self.bars = bars
  self:reset()
end

function RepeatThen:reset()
  self.count = self.bars
end

function RepeatThen:next(row_num, model)
  self.count = self.count - 1
  if count <= 0 then
    self:reset()
    self.action(row_num, model)
  end
end

-- local forward = RepeatThen:new(1, build_action_relative(1))
-- local backward = RepeatThen:new(1, build_action_relative(-1))

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
  self:set_follow(props.follow)
  self.steps = {}
  self:clear()
  self._scaler = sky.build_scalex(0, 1, 0, 1)
end

function Row:set_res(r, queued)
  self.next_res = util.clamp(math.floor(r), 4, 32)
  if not queued then self.res = self.next_res end
end

function Row:set_n(n, queued)
  self.next_n = util.clamp(math.floor(n), 2, 32)
  if not queued then self.n = self.next_n end
end

function Row:set_bend(b, queued)
  self.next_bend = util.clamp(b, 0.2, 5)
  if not queued then self.bend = self.next_bend end
end

function Row:set_offset(o, queued)
  self.next_offset = math.floor(o)
  if not queued then self.offset = self.next_offset end
end

function Row:set_follow(f)
  self.follow = f
end

function Row:do_follow(row_num, model)
  if self.follow then self.follow:next(row_num, model) end
end

function Row:apply_queued()
  self.res = self.next_res
  self.n = self.next_n
  self.bend = self.next_bend
  self.offset = self.next_offset
end

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
  -- local _, f = math.modf(beats / self.res)
  local b, f = math.modf(beats / self.res)
  -- return f
  return self._scaler(f, self.bend), b
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
Tambla.MODEL_VERSION = 2

function Tambla:new(props)
  self.tick_period = props.tick_period or 1/32
  self.slots = {}
  self.row_sync = {}
  self.row_voice = {}
  self.row_running = {}
  self.next_row_running = {}
  self.row_slot = {}
  self.next_row_slot = {}

  self.beat_offset = 0
  self.beat_stopped = 0
  self.running = true

  if props.slots then
    for _, p in ipairs(props.slots) do
      table.insert(self.slots, p)
      table.insert(self.row_sync, 0)
      table.insert(self.row_running, true)
      table.insert(self.next_row_running, true)
    end
  else
    local p = Pattern()
    p:randomize()
    table.insert(self.slots, p)
    table.insert(self.row_sync, 0)
    table.insert(self.row_running, true)
    table.insert(self.next_row_running, true)
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

function Tambla:select_slot(i, queued)
  self._next_selected_slot = util.clamp(math.floor(i), 1, self._slot_count)
  if not queued then self._selected_slot = self._next_selected_slot end
  for r = 1, self.NUM_ROWS do
    self.next_row_slot[r] = self._next_selected_slot
    if not queued then self.row_slot[r] = self._next_selected_slot end
  end
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

function Tambla:set_voice(i, v)
  self.row_voice[i] = v
end

function Tambla:select_row_slot(i, s, queued)
  local r = util.clamp(math.floor(i), 1, self.NUM_ROWS)
  local s = util.clamp(math.floor(s), 1, self._slot_count)
  self.next_row_slot[r] = s
  if not queued then self.row_slot[r] = s end
end

function Tambla:row(i)
  return self.slots[self.row_slot[i]].rows[i], self.row_running[i]
end

function Tambla:row_is_running(i)
  return self.row_running[i]
end

function Tambla:set_row_is_running(i, state, queued)
  self.next_row_running[i] = state
  if not queued then self.row_running[i] = state end
end

function Tambla:apply_queued()
  self._selected_slot = self._next_selected_slot
  for i = 1, self.NUM_ROWS do
    self.row_running[i] = self.next_row_running[i]
    self.row_slot[i] = self.next_row_slot[i]
    local r = self:row(i)
    -- allow queued changes to override the action?
    r:apply_queued()
    r:do_follow(i, self)
  end
end

function Tambla:voice(i)
  -- if voice == nil then event should go to the default destination
  return self.row_voice[i] or 0
end

function Tambla:transport_start()
  -- local _, f = math.modf(clock.get_beats())
  self.beat_offset = 0
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
  action_null = action_null,
  build_action_relative = build_action_relative,
  build_action_goto = build_action_goto,
  action_stop = action_stop,
  Follow = Follow,
  RepeatThen = RepeatThen,
}