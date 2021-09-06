sky.use('device/arp') -- ensure the Held device is loaded

local Singleton = nil

-- sky.Chain{
--   sky.crow.Mono{
--     velocity = true,
--     attack = 0.01,
--     release = 0.5,
--   }
-- }

--
-- mono voice:
--  out[1]: pitch
--  out[2]: shape [trigger, gate, or env] (optionally scaled by velocity)
--  out[3]: mod
--  out[4]: key track

local Mono = sky.Device:extend()

function Mono:new(props)
  Mono.super.new(self, props)
  self.velocity = props.velocity or false

  self:set_pitch_output(props.pitch_output or 1)
  -- setup amp shape, must be done before dyn values can be set
  self:set_shape_output(props.shape_output or 2)
  self:set_attack(props.attack or 0.0)
  self:set_release(props.release or 0.0)

  -- build an internal chain to re-use Held note tracker
  self._chain = sky.Chain{
    sky.Held{},
    function(event, output)
      self:_do(event, output)
    end,
  }
end

function to_volts(note)
  -- TODO: this seems like it is wrong
  local v_semi = 1.0/12
  -- assumes note 60 == middle-C == 0V
  return (note - 60) * v_semi
end

function Mono:process(event, output)
  local processed = self._chain:process(event)
  output(event)

  -- FIXME: if the sub-chain generated any event, pass them through. a convience
  -- function seems appropriate here
  local c = processed:count()
  if c > 0 then
    print("mono: ", processed:count())
    for i, e in processed:ipairs() do
      print(i, sky.to_string(e))
    end
  end
end

function Mono:_do(event, output)
  if sky.is_type(event, sky.HELD_EVENT) then
    local last = event.notes[#event.notes]
    if last ~= nil then
      -- have a note, set pitch and trigger
      self:_pitch().volts = to_volts(last.note)
      if self.velocity then
        local amp = util.linlin(0, 127, 0, 1, last.vel)
        self:_shape().dyn.amp = amp
      end
      self:_shape()(true)
    else
      -- no note, key was lifed
      self:_shape()(false)
    end
  else
    output(event)
  end
end

function Mono:set_pitch_output(n)
  if n < 0 or n > 4 then
    error("pitch output number must be between 1-4")
  end

  self.pitch_output = n
end

function Mono:set_shape_output(n)
  if n < 0 or n > 4 then
    error("shape output number must be between 1-4")
  end

  if self.shape_output ~= n then
    -- output changed, configure ita
    crow.output[n].action = "{ held{ to(dyn{amp=1}*10, dyn{attack=0}) }, to(0, dyn{release=0}) }"
    self.shape_output = n
  end
end

function Mono:_shape()
  return crow.output[self.shape_output]
end

function Mono:_pitch()
  return crow.output[self.pitch_output]
end

function Mono:set_attack(attack)
  self.attack = attack
  self:_shape().dyn.attack = attack
end

function Mono:set_release(release)
  self.release = release
  self:_shape().dyn.release = release
end

--
-- two voice
--

local Duo = sky.Device:extend()

function Duo:new(props)
  Duo.super.new(self, props)
end

function Duo:process(event, output)
  -- TODO:
  output(event)
end


function singleton(class)
  return function(props)
    if Singleton == nil then
      Singleton = class(props)
    elseif not Singleton:is(class) then
      -- TODO: verify this catches the construct different class case
      error("only one crow output class can be used at one time")
    end
    return Singleton
  end
end

return {
  crow = {
    Mono = singleton(Mono),
    Duo = singleton(Duo),
  },
}
