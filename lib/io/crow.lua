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

  -- setup amp shape, must be done before dyn values can be set
  crow.output[2].action = "{ held{ to(dyn{amp=1}*10, dyn{attack=0}) }, to(0, dyn{release=0}) }"

  self:set_attack(props.attack or 0.0)
  self:set_release(props.release or 0.0)
end

function to_volts(note)
  -- TODO: this seems like it is wrong
  local v_semi = 1.0/12
  -- assumes note 60 == middle-C == 0V
  return (note - 60) * v_semi
end

function Mono:process(event, output)
  if sky.is_type(event, sky.types.NOTE_ON) then
    crow.output[1].volts = to_volts(event.note)
    -- TODO: pitch slew
    if self.velocity then
      local amp = util.linlin(0, 127, 0, 1, event.vel)
      crow.output[2].dyn.amp = amp
    end
    crow.output[2](true)
  elseif sky.is_type(event, sky.types.NOTE_OFF) then
    -- TODO: note tracking
    crow.output[2](false)
  end
  output(event)
end

function Mono:set_attack(attack)
  self.attack = attack
  crow.output[2].dyn.attack = attack
end

function Mono:set_release(release)
  self.release = release
  crow.output[2].dyn.release = release
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
