sky.use('sky/lib/core/page')

local fmt = require('formatters')
local cs = require('controlspec')
local fs = require('fileselect')

--
-- RowWidget
--

local RowWidget = sky.Object:extend()
RowWidget.HEIGHT = 15
RowWidget.STEP_WIDTH = 6
RowWidget.BAR_WIDTH = 4
RowWidget.BAR_HEIGHT = 10

function RowWidget:new(x, y)
  self.topleft = {x or 1, y or 1}
end

function RowWidget:width(row)
  return self.STEP_WIDTH * row.n
end

function RowWidget:draw(row, beats)
  -- draw from bottom, left
  local x = self.topleft[1]
  local y = self.topleft[2] + self.BAR_HEIGHT
  for i, step in ipairs(row.steps) do
    if i > row.n then break end -- FIXME: move this iteration detail to Row
    if step:is_active() then
      local width = math.floor(util.linlin(0, 1, 1, self.BAR_WIDTH, step.duration)) -- FIXME: 0 duration really?
      local height = math.floor(util.linlin(0, 1, 1, self.BAR_HEIGHT, step.velocity))
      screen.rect(x, y - height, width, height)
      local level = math.floor(util.linlin(0, 1, 2, 12, step.chance))
      screen.level(level)
      screen.fill()
    end
    x = x + self.STEP_WIDTH
  end

  -- playhead
  x = self.topleft[1]
  y = self.topleft[2] + self.BAR_HEIGHT + 3
  screen.move(x, y)
  screen.line_rel(self:width(row) * row:head_position(beats), 0)
  screen.level(1)
  screen.close()
  screen.stroke()
  screen.level(15)
  screen.pixel(self:width(row) + 3, y - 1)
  screen.fill()
end

function RowWidget:draw_step_selection(row, step)
  if step > row.n then
      -- limit selection ui to end of row
    step = row.n
  end
  local x = self.topleft[1] + ((step - 1) * self.STEP_WIDTH)
  local y = self.topleft[2] + self.BAR_HEIGHT + 2
  screen.level(5)
  screen.rect(x + 1, y, self.BAR_WIDTH - 1, 2)
  screen.close()
  screen.stroke()
end

local function layout_vertical(x, y, widgets)
  -- adjust the widget top/left origin such that they are arranged in a stack
  local top = y
  for i, w in ipairs(widgets) do
    w.topleft[1] = x
    w.topleft[2] = top
    top = top + w.HEIGHT
  end
end

--
-- PageBase
--

local PageBase = sky.Page:extend()
PageBase.PARAM_LEFT = 128
PageBase.PARAM_SPACING = 8
PageBase.LABEL_LEVEL = 3
PageBase.VALUE_LEVEL = 12
PageBase.TOP_LEFT = { 0, 2 }

function PageBase:new(model, control_state, topleft)
  PageBase.super.new(self, model)
  self.topleft = topleft or self.TOP_LEFT
  self.state = control_state

  self.page_code = '?'

  self.widgets = {}
  for i, r in ipairs(self.model.rows) do
    table.insert(self.widgets, RowWidget())
  end
  layout_vertical(self.topleft[1] + 4, self.topleft[2], self.widgets)
end

function PageBase:draw_mode()
  screen.level(self.LABEL_LEVEL)
  screen.font_face(0)
  screen.font_size(8)
  screen.move(self.PARAM_LEFT, 58)
  screen.text_right(self.page_code)
end

function PageBase:draw_rows(beat)
  local rows = self.model.rows
  for i, r in ipairs(self.widgets) do
    r:draw(rows[i], beat)
  end
end

function PageBase:draw_caret()
  -- selection carat
  local y = self.model:selected_row_idx() * RowWidget.HEIGHT - 2
  screen.level(15)
  screen.rect(self.topleft[1], y, 2, 2)
end

function PageBase:draw_param(y, name, value)
  screen.font_face(0)
  screen.font_size(8)
  screen.move(self.PARAM_LEFT, y)
  screen.level(self.LABEL_LEVEL)
  screen.text_right(name)
  y = y + self.PARAM_SPACING
  screen.move(self.PARAM_LEFT, y)
  screen.level(self.VALUE_LEVEL)
  screen.text_right(value)
  return y + self.PARAM_SPACING
end

function PageBase:process(event, output, state, props)
  self.state:process(event, output, state, props)
  output(event)
end

--
-- PlayPage
--

local PlayPage = PageBase:extend()

function PlayPage:new(model, control_state)
  PlayPage.super.new(self, model, control_state)
  self.page_code = 'P'
end

function PlayPage:draw(event, props)
  self:draw_rows(event.beat)
  self:draw_caret()
  self:draw_mode()
  self:draw_param(8, self.model:selected_prop_code(), self.model:selected_prop_value())
end

function PlayPage:process(event, output, state, props)
  PlayPage.super.process(self, event, output, state, props)

  local key_z = self.state.key_z
  local state = self.state

  if sky.is_key(event) then
    if event.num == 2 and event.z == 1 then
      if key_z[1] == 1 then
        props.select_page('macro')
      elseif key_z[3] == 1 then
        -- key 2 w/ key 3 held
        self.model:randomize()
        output(sky.mk_redraw())
      else
        -- play, key 2 action
        print("play key 2 action")
      end
    elseif event.num == 3 and event.z == 1 then
      if key_z[1] == 1 then -- mode shift key
        props.select_page('edit')
      else
        -- play, key 3 action
        print("play key 3 action")
      end
    end
  elseif sky.is_enc(event) then
    if event.num == 1 then
      if key_z[1] == 1 then
        state.row_acc = util.clamp(state.row_acc + (event.delta / 10), 1, state.row_count)
        self.model:select_row(state.row_acc)
      end
    elseif event.num == 2 then
      state.prop_acc = util.clamp(state.prop_acc + (event.delta / 10), 1, state.prop_count)
      self.model:select_prop(state.prop_acc)
    elseif event.num == 3 then
      local idx = self.model:selected_row_idx()
      local id = self.model:selected_prop_name() .. tostring(idx) -- FIXME: avoid string construction?
      local delta = event.delta
      if key_z[3] == 1 then
        -- fine tuning
        delta = delta / 10.0
      end
      params:delta(id, event.delta)
    end
  end
end

--
-- EditPage
--

local EditPage = PageBase:extend()

function EditPage:new(model, control_state)
  EditPage.super.new(self, model, control_state)
  self.page_code = 'E'
end

function EditPage:draw_step_select()
  local idx = self.model:selected_row_idx()
  local row = self.model:selected_row()
  local widget = self.widgets[idx]
  widget:draw_step_selection(row, self.model:selected_step_idx())
end

function EditPage:draw(event, props)
  self:draw_rows(event.beat)
  self:draw_step_select()
  self:draw_caret()
  self:draw_mode()

  local step = self.model:selected_step()
  local y = 8
  y = self:draw_param(y, 'v', util.round(step.velocity, 0.01))
  y = self:draw_param(y, 'd', util.round(step.duration, 0.01))
  y = self:draw_param(y, '%', util.round(step.chance, 0.01))
end

function EditPage:process(event, output, state, props)
  EditPage.super.process(self, event, output, state, props)

  local key_z = self.state.key_z
  local state = self.state

  if sky.is_key(event) then
    if event.num == 2 and event.z == 1 then
      if key_z[1] == 1 then
        -- key 2 w/ key 1 held
        props.select_page('play')
      elseif key_z[3] == 1 then
        -- key 2 w/ key 3 held
        print('randomize row')
        local row = self.model:selected_row()
        row:randomize()
      else
        -- key 2 action
        print('k2 action')
      end
    elseif event.num == 3 and event.z == 1 then
      if key_z[1] == 1 then
        -- key 3 w/ key 1 held
      elseif key_z[2] == 1 then
        -- key 3 w/ key 2 held
        print('clear row')
        local row = self.model:selected_row()
        row:clear()
      else
        -- key 3 action
        print('k3 action')
      end
    end
  elseif sky.is_enc(event) then
    if event.num == 1 then
      if key_z[1] == 0 then
        -- select step
        state.step_acc = util.clamp(state.step_acc + (event.delta / 5), 1, self.model:selected_row_n())
        self.model:select_step(state.step_acc)
      else
        -- select row
        state.row_acc = util.clamp(state.row_acc + (event.delta / 10), 1, state.row_count)
        self.model:select_row(state.row_acc)
      end
    elseif event.num == 2 then
      local step = self.model:selected_step()
      if key_z[2] == 1 then
        -- tweak chance
        if step ~= nil then
          step:set_chance(step.chance + (event.delta / 20))
        end
      else
        -- tweak velocity
        if step ~= nil then
          step:set_velocity(step.velocity + (event.delta / 20))
          if step.velocity > 0 and not step:is_active() then
            -- auto set chance to 100% steps if velocity is non-zero but step is
            -- inactive
            step:set_chance(1)
          end
        end
      end
    elseif event.num == 3 then
      -- tweak duration
      local step = self.model:selected_step()
      if step ~= nil then
        step:set_duration(step.duration + (event.delta / 20))
      end
    end
  end
end

--
-- MacroPage
--

local MacroPage = PageBase:extend()

function MacroPage:new(model, control_state)
  MacroPage.super.new(self, model, control_state)
  self.page_code = 'M'
end

function MacroPage:draw(event, props)
  self:draw_mode()
end

function MacroPage:process(event, output, state, props)
  MacroPage.super.process(self, event, output, state, props)
  local key_z = self.state.key_z
  if sky.is_key(event) then
    if event.num == 3 and event.z == 1 then
      if key_z[1] == 1 then
        --output(self:switch_mode(Tambla.MODE_PLAY))
        props.select_page('play')
      else
        -- key 3 action
      end
    end
  end
end

--
-- ControlState
--

local ControlState = sky.Object:extend()

function ControlState:new(model)
  self.model = model

  self.row_count = #model.rows
  self.row_acc = 1

  self.step_acc = 1

  self.prop_count = 4 -- FIXME: get this from the model
  self.prop_acc = 1

  self.key_z = {0, 0, 0}
end

function ControlState:add_row_params(i)
  local n = tostring(i)
  params:add_group('row ' .. n, 7)
  params:add{type = 'option', id = 'chance' .. n, name = 'chance',
    options = {'on', 'off'},
    default = 1
  }
  params:add{type = 'option', id = 'velocity_mod' .. n, name = 'velocity mod',
    options = {'on', 'off'},
    default = 1
  }
  params:add{type = 'option', id = 'length_mod' .. n, name = 'length mod',
    options = {'on', 'off'},
    default = 1
  }
  params:add{type = 'control', id = 'bend' .. n, name = 'bend',
    controlspec = cs.new(0.2, 5.0, 'lin', 0.005, 1.0, ''),
    formatter = fmt.round(0.01),
    action = function(v) self.model.rows[i]:set_bend(v) end,
  }
  params:add{type = 'control', id = 'n' .. n, name = 'n',
    controlspec = cs.new(2, 16, 'lin', 1, 16, ''),
    formatter = fmt.round(1),
    action = function(v) self.model.rows[i]:set_n(v) end,
  }
  params:add{type = 'control', id = 'res' .. n, name = 'res',
    controlspec = cs.new(4, 32, 'lin', 1, 4, ''),
    formatter = fmt.round(1),
    action = function(v) self.model.rows[i]:set_res(v) end,
  }
  params:add{type = 'control', id = 'offset' .. n, name = 'offset',
    controlspec = cs.new(-16, 16, 'lin', 1, 0, ''),
    formatter = fmt.round(1),
    action = function(v) self.model.rows[i]:set_offset(v) end,
  }
end

function ControlState:add_params()
  params:add_separator('tambla')

  params:add_file('pattern', 'pattern', 'foo.json')
  params:add_text('pattern_name', 'name', 'blah')

  --
  params:add_trigger('pattern_load', 'load...')
  params:set_action('pattern_load', function()
    local start = paths.this.data
    fs.enter(start, function(path)
      params:set('pattern_name', path)
      print('got: ', path)
    end)
  end)

  params:add_trigger('pattern_save', 'save')
  params:set_action('pattern_save', function()
    local name = params:string('pattern_name')
    print('save pattern:', name)
  end)

  for i = 1, self.model.NUM_ROWS do
    self:add_row_params(i)
  end
end

function ControlState:process(event, output, state)
  if sky.is_key(event) then
    -- record key state for use in key chording ui
    self.key_z[event.num] = event.z
  end
end

--
-- module
--
return {
  PlayPage = PlayPage,
  EditPage = EditPage,
  MacroPage = MacroPage,

  ControlState = ControlState,
}