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
sky.use('device/transpose')
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

transpose = sky.Transpose{}

main = sky.Chain{
  sky.Held{ debug = false },
  devices.TamblaNoteGen(tambla, controller),
  transpose,
  sky.MakeNote{},
  outputs,
  sky.Logger{
    bypass = true,
    filter = tambla.is_tick,
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
  controller:set_transposer(transpose)
  controller:add_params()
end

