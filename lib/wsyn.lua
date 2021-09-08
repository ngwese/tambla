--
-- w/ syn support
--    adapted from less concepts 3:
--        https://github.com/linusschrab/less_concepts_3/blob/master/less_concepts_3.lua
--

-- local DEFAULT_AR_MODE = 2
-- local DEFAULT_VEL = 2
-- local DEFAULT_CURVE = 0
-- local DEFAULT_RAMP = 0
-- local DEFAULT_FM_INDEX = 0
-- ...

local PARAM_IDS = {
  'wsyn_ar_mode',
  'wsyn_vel',
  'wsyn_curve',
  'wsyn_ramp',
  'wsyn_fm_index',
  'wsyn_fm_env',
  'wsyn_fm_ratio_num',
  'wsyn_fm_ratio_den',
  'wsyn_lpg_time',
  'wsyn_lpg_symmetry',
}

local Controller = sky.Object:extend()

function Controller:new(props)
  Controller.super.new(self, props)
  self._device = props.device
end

function Controller:device()
  return self._device or crow.ii.wsyn
end

function Controller:send_params()
  for _, id in ipairs(PARAM_IDS) do
    local param = params:lookup_param(id)
    param:bang()
  end
end

function Controller:add_params(group)
  if group then
    params:add_group('wsyn', 12)
  else
    params:add_separator('wsyn')
  end

  params:add{type = 'option', id = 'wsyn_ar_mode', name = 'ar mode',
    options = {'off', 'on'},
    default = 2,
    action = function(v)
      self:device().ar_mode(v - 1)
    end
  }
  params:add{type = 'control', id = 'wsyn_vel', name = 'velocity',
    controlspec = controlspec.new(0, 5, 'lin', 0, 2, 'v'),
    action = function(v)
      self:device().velocity(v)
    end
  }
  params:add{type = 'control', id = 'wsyn_curve', name = 'curve',
    controlspec = controlspec.new(-5, 5, 'lin', 0, 0, 'v'),
    action = function(v)
      self:device().curve(v)
    end
  }
  params:add{type = 'control', id = 'wsyn_ramp', name = 'ramp',
    controlspec = controlspec.new(-5, 5, 'lin', 0, 0, 'v'),
    action = function(v)
      self:device().ramp(v)
    end
  }
  params:add{type = 'control', id = 'wsyn_fm_index', name = 'fm index',
    controlspec = controlspec.new(0, 5, 'lin', 0, 0, 'v'),
    action = function(v)
      self:device().fm_index(v)
    end
  }
  params:add{type = 'control', id = 'wsyn_fm_env', name = 'fm env',
    controlspec = controlspec.new(-5, 5, 'lin', 0, 0, 'v'),
    action = function(v)
      self:device().fm_env(v)
    end
  }
  params:add{type = 'control', id = 'wsyn_fm_ratio_num', name = 'fm ratio numerator',
    controlspec = controlspec.new(1, 20, 'lin', 1, 2),
    action = function(val)
      self:device().fm_ratio(val, params:get('wsyn_fm_ratio_den'))
    end
  }
  params:add{type = 'control', id = 'wsyn_fm_ratio_den', name = 'fm ratio denominator',
    controlspec = controlspec.new(1, 20, 'lin', 1, 1),
    action = function(v)
      self:device().fm_ratio(params:get('wsyn_fm_ratio_num'), v)
    end
  }
  params:add{type = 'control', id = 'wsyn_lpg_time', name = 'lpg time',
    controlspec = controlspec.new(-5, 5, 'lin', 0, 0, 'v'),
    action = function(v)
      self:device().lpg_time(v)
    end
  }
  params:add{type = 'control', id = 'wsyn_lpg_symmetry', name = 'lpg symmetry',
    controlspec = controlspec.new(-5, 5, 'lin', 0, 0, 'v'),
    action = function(v)
      self:device().lpg_symmetry(v)
    end
  }
  params:add{type = 'trigger', id = 'wsyn_randomize', name = 'randomize',
    action = function()
      params:set('wsyn_curve', math.random(-50, 50)/10)
      params:set('wsyn_ramp', math.random(-50, 50)/10)
      params:set('wsyn_fm_index', math.random(0, 50)/10)
      params:set('wsyn_fm_env', math.random(-50, 50)/10)
      params:set('wsyn_fm_ratio_num', math.random(1, 20))
      params:set('wsyn_fm_ratio_den', math.random(1, 20))
      params:set('wsyn_lpg_time', math.random(-50, 50)/10)
      params:set('wsyn_lpg_symmetry', math.random(-50, 50)/10)
    end
  }
  params:add{type = 'trigger', id = 'wsyn_init', name = 'init',
    action = function()
      self:send_params()
    end
  }

end

--
-- module
--

return {
  Controller = Controller
}