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
sky.use('io/arc')
sky.use('engine/polysub')

local halfsecond = include('awake/lib/halfsecond')

local model = include('lib/model')
local pages = include('lib/pages')
local devices = include('lib/devices')

tambla = model.Tambla{
  tick_period = 1/64,
  slots = {
    model.Pattern():randomize(),
    model.Pattern():randomize(),
    model.Pattern(),
    model.Pattern()
  }
}

main_logger = sky.Logger{
  bypass = true,
  filter = function(e)
    return tambla.is_tick(e) or sky.is_clock(e)
  end,
}

local function build_row_out(n)
  local out = sky.Chain{
    sky.Channel{ channel = n },
    main_logger,
    sky.Output{
      device = midi.connect(2)
    },
  }
  out.bypass = true
  return out
end

row_out1 = build_row_out(1)
row_out2 = build_row_out(2)
row_out3 = build_row_out(3)
row_out4 = build_row_out(4)

route_row = devices.Route{
  key = 'voice',
  row_out1,
  row_out2,
  row_out3,
  row_out4,
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

norns_display = sky.Chain{
  sky.NornsDisplay{
    screen.clear,
    ui:draw_router(),
    screen.update,
  }
}

main_outputs = sky.Switcher{
  which = 1,
  sky.Output{},
  sky.PolySub{},
}

main_pitch = sky.Pitch{}

main_channel = sky.Channel{
  channel = 1
}

held = sky.Held{}

random = devices.Random{
  bypass = true,
  choices = 1,
  scale = 4,
  sign = 'add',
  chance = 0.3,
}

main = sky.Chain{
  held,
  devices.TamblaNoteGen(tambla, controller),
  random,
  main_pitch,
  sky.MakeNote{},
  route_row,
  main_channel,
  main_outputs,
  main_logger,
  function(event, output)
    if tambla.is_tick(event) then output(sky.mk_redraw()) end
  end,
  sky.Forward(norns_display),
}

function hold_state_setter(state)
  main:process(held.mk_hold_state(state))
end

midi_input = sky.Input{ chain = main }

norns_input = sky.NornsInput{
  chain = sky.Chain{
    ui:event_router(),
    sky.Forward(norns_display)
  },
}

arc_input = sky.ArcInput{
  chain = sky.Chain{
    ui:event_router(),
    sky.ArcDialGesture{ which = 4 },
    sky.ArcDialSmoother{ which = 4, sr = 24, time = 0.5 },
    function(event, output)
      if sky.ArcDialGesture.is_dial(event) and event.n == 4 then
        tambla:set_chance_boost(event.normalized)
      end
      output(event)
    end,
    -- sky.ArcDialGesture{ which = 1 },
    -- sky.Logger{},
    sky.ArcDisplay{
      sky.ArcDialRender{ width = 1.2, mode = 'range' },
      sky.ArcDisplay.null_render(),
      sky.ArcDisplay.null_render(),
      sky.ArcDialRender{ which = 4, mode = 'segment' },
    }
  }
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
  controller:set_input_device(midi_input)
  controller:set_output_switcher(main_outputs)
  controller:set_channeler(main_channel)
  controller:set_transposer(main_pitch)
  controller:set_row_outputs({row_out1, row_out2, row_out3, row_out4})
  controller:set_logger(main_logger)
  controller:set_hold_state_setter(hold_state_setter)
  controller:add_params()

  arc_input.chain:init()
end

