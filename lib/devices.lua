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

--
-- TODO: enable/disable chance evaluation
--

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
    -- print("ROUTE default")
    output(event)
  else
    local chain = self[where]
    -- print("ROUTE", where, chain)
    if chain ~= nil then
      chain:process(event)
    end
  end
end

--
-- module
--
return {
  TamblaNoteGen = TamblaNoteGen,
  Route = Route,
}
