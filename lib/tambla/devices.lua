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
    -- determine if a not should be generated
    local beat = event.beat
    for i, r in ipairs(self.model:slot().rows) do
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
-- module
--
return {
  TamblaNoteGen = TamblaNoteGen,
}
