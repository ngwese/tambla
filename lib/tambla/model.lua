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
Tambla.NUM_ROWS = 4
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
  self:select_step(1)

  self.prop_codes = {'b', 'o', 'r', 'n',}
  self.prop_names = {'bend', 'offset', 'res', 'n'}
end

-- row selection state
function Tambla:select_row(i)
  self._selected_row = util.clamp(math.floor(i), 1, self.NUM_ROWS)
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
  return { __type = 'Tambla', tempo = clock.get_tempo(), rows = rows, tick_period = self.tick_period }
end

function Tambla:load(props)
  self:new(props)
  for i,r in ipairs(props.rows) do
    r:load(props.rows[i])
  end
end

--
-- module
--
return {
  Tambla = Tambla,
  Row = Row,
  Step = Step,
}