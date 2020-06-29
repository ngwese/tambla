-- bending rhythmic arpeggio
-- 1.0.0 @ngwese
-- <url>
--
-- E1 select slot
-- E2 row param
-- E3 row param value
--
-- K1 = ALT
-- ALT-E1 = select row
-- ALT-K2 = page left
-- ALT-K3 = page right
--

include('sky/unstable')
sky.use('device/make_note')
sky.use('device/arp')
sky.use('device/switcher')
sky.use('device/transform')
sky.use('io/norns')
sky.use('engine/polysub')

local halfsecond = include('awake/lib/halfsecond')

local model = include('lib/model')
local pages = include('lib/pages')
local devices = include('lib/devices')

tambla = model.Tambla{
  tick_period = 1/64,
  slots = {
    model.Pattern():randomize(),
    model.Pattern(),
    model.Pattern(),
    model.Pattern()
  }
}

controller = pages.Controller(tambla)

ui = sky.PageRouter{
  initial = 'play',
  pages = {
    macro = pages.MacroPage(tambla, controller),
    play = pages.PlayPage(tambla, controller),
    edit = pages.EditPage(tambla, controller),
  }
}

display = sky.Chain{
  sky.NornsDisplay{
    screen.clear,
    ui:draw_router(),
    screen.update,
  }
}

outputs = sky.Switcher{
  which = 1,
  sky.Output{},
  sky.PolySub{},
}

pitch = sky.Pitch{}
channel = sky.Channel{
  channel = 1
}

-- local function build_row_out(n)
--   return sky.Chain{
--     sky.Channel{ channel = n },
--     outputs,
--   }
-- end

  -- devices.Route{
  --   key = 'voice',
  --   build_row_out(1),
  --   build_row_out(2),
  --   build_row_out(3),
  --   build_row_out(4),
  -- },

main = sky.Chain{
  sky.Held{ debug = true },
  devices.TamblaNoteGen(tambla, controller),
  pitch,
  sky.MakeNote{},
  channel,
  outputs,
  sky.Logger{
    bypass = false,
    filter = function(e)
      return tambla.is_tick(e) or sky.is_clock(e)
    end,
  },
  function(event, output)
    if tambla.is_tick(event) then output(sky.mk_redraw()) end
  end,
  sky.Forward(display),
}

input1 = sky.Input{ chain = main }

input2 = sky.NornsInput{
  chain = sky.Chain{
    ui:event_router(),
    sky.Forward(display)
  },
}

--
-- script logic
--

function init()
  halfsecond.init()

  -- halfsecond
  params:set('delay', 0.13)
  params:set('delay_rate', 0.95)
  params:set('delay_feedback', 0.27)

  -- polysub
  params:set('amprel', 0.1)

  -- tambla
  controller:set_input_device(input1)
  controller:set_output_switcher(outputs)
  controller:set_channeler(channel)
  controller:set_transposer(pitch)
  controller:add_params()
end

