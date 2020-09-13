--
-- TamblaNoteGen
--

local TamblaNoteGen = sky.Device:extend()

function TamblaNoteGen:new(model, controller)
  TamblaNoteGen.super.new(self)
  self.model = model
  self.controller = controller
  self.default_duration = 1/16
  self._scheduler = nil
  self._notes = {}
  self._next_notes = nil
  self._last_index = {}
  for i = 1, self.model.NUM_ROWS do
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

    local beat = event.beat
    local chance_off = not self.controller.chance_mod
    local chance_boost = self.model:chance_boost()
    local velocity_on = self.controller.velocity_mod
    local length_on = self.controller.length_mod

    for i, r in ipairs(self.model:slot().rows) do
      local idx = r:step_index(beat)
      if idx ~= self._last_index[i] then
        -- we are at a new step
        local step = r.steps[idx] -- which step within row
        local note = self._notes[i] -- note which matches row based on order held
        if note ~= nil then
          if chance_off or (math.random() < (step.chance + chance_boost)) then
            -- determine velocity
            local velocity = 127
            if velocity_on then
              velocity = math.floor(note.vel * step.velocity)
            end
            -- determine length
            local duration = self.default_duration
            if length_on then
              duration = clock.get_beat_sec(step.duration * (1 / (32 / r.res)))
            end
            -- requires a make_note device to produce note off
            local ev = sky.mk_note_on(note.note, velocity, note.ch, duration)
            ev.voice = i
            output(ev)
          end
          -- always output aux?
          local cc = util.linlin(0, 1, 0, 127, step.aux)
          local cc_ev = sky.mk_control_change(1, cc, note.ch)
          cc_ev.voice = i
          output(cc_ev)
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
-- Route
--

local Route = sky.Device:extend()

function Route:new(props)
  Route.super.new(self, props)
  self.property = props.key or 'route'
  self._count = 0
  for i, child in ipairs(props) do
    self[i] = child
    self._count = i
  end
end

function Route:process(event, output, state)
  local where = event[self.property]
  if where == nil then
    output(event)
    return
  end

  local chain = self[where]
  if chain ~= nil and not chain.bypass then
    chain:process(event)
  else
    output(event)
  end
end

--
-- Random
--

local Random = sky.Device:extend()

function Random:new(props)
  Random.super.new(self, props)
  self._active = {}
  self:set_scale(props.scale or 1)
  self:set_choices(props.choices or 1)
  self:set_chance(props.chance or 0.1)
  self:set_sign(props.sign or 'add')
end

function Random:set_scale(scale)
  self._scale = util.clamp(scale, 1, 24)
end

function Random:set_choices(choice)
  self._choices = util.clamp(choice, 1, 24)
end

function Random:set_chance(chance)
  self._chance = util.clamp(chance, 0, 1)
end

function Random:set_sign(sign)
  if sign == 'add' then self._sign = 'add'
  elseif sign == 'sub' then self._sign = 'sub'
  elseif sign == 'bi' then self._sign = 'bi'
  end
end

function Random:process(event, output, state)
  if not self.bypass then
    if sky.is_type(event, sky.types.NOTE_ON) then
      if math.random() < self._chance then
        local id = event.correlation
        local delta = math.floor(math.random() * self._choices * self._scale)
        if self._sign == 'sub' or (self._sign == 'bi' and math.random() < 0.5) then
          delta = -delta
        end
        local shifted = util.clamp(event.note + delta, 0, 127)
        self._active[id] = shifted
        event.note = shifted
      end
    elseif sky.is_type(event, sky.types.NOTE_OFF) then
      local id = event.correlation
      local shifted = self._active[id]
      if shifted then
        self._active[id] = nil
        event.note = shifted
      end
    end
  end
  output(event)
end

--
-- module
--
return {
  TamblaNoteGen = TamblaNoteGen,
  Route = Route,
  Random = Random,
}
