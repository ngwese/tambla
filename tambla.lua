include('sky/lib/prelude')
sky.use('sky/lib/device/make_note')

--
-- Step
--

local Step = {}
Step.__index = Step

function Step.new(chance, velocity, duration)
  local o = setmetatable({}, Step)
  o.chance = chance or 0      -- [0, 1] for probability
  o.velocity = velocity or 1  -- [0, 1]
  o.duration = duration or 1  -- [0, 1] where duration is a multiplier on 1/row.res
  return o
end

function Step:is_active()
  return self.chance > 0
end

function Step:clear()
  self.chance = 0
  self.velocity = 1
  self.duration = 1
end

--
-- Row
--

local Row = {}
Row.__index = Row

local MAX_STEPS = 16

function Row.new(props)
  local o = setmetatable(props or {}, Row)
  o:set_n(o.n or 8)
  o:set_res(o.res or 4)
  o:set_bend(o.bend or 1.0)
  o:set_offset(o.offset or 0)
  o.steps = {}
  o:steps_clear()
  o._scaler = sky.build_scalex(0, 1, 0, 1)
  return o
end

function Row:set_res(r)
  self.res = util.clamp(math.floor(r), 4, 32)
  return self
end

function Row:set_n(n)
  self.n = util.clamp(math.floor(n), 2, 32)
  return self
end

function Row:set_bend(b)
  self.bend = util.clamp(b, 0.2, 5)
  return self
end

function Row:set_offset(o)
  self.offset = math.floor(o)
  return self
end

function Row:steps_clear()
  for i = 1, MAX_STEPS do
    self.steps[i] = Step.new(0) -- zero chance
  end
end

function Row:randomize()
  for i, s in ipairs(self.steps) do
    local chance = math.random()
    --print(self, i, s, chance)
    if chance > 0.5 then chance = math.random() else chance = 0 end -- random chance for ~20% of steps (but not really)
    if chance > 0 then
      s.chance = chance
      s.velocity = util.linlin(0, 1, 0.2, 1, math.random())
      s.duration = util.linlin(0, 1, 0.25, 1, math.random())
      --tab.print(s)
    else
      s:clear()
    end
  end
end

function Row:head_position(beats)
  local _, f = math.modf(beats / self.res)
  return self._scaler(f, self.bend)
end

--
-- RowRender
--

local RowRender = {}
RowRender.__index = RowRender
RowRender.HEIGHT = 15
RowRender.STEP_WIDTH = 6
RowRender.BAR_WIDTH = 4
RowRender.BAR_HEIGHT = 10

function RowRender.new(x, y)
  local o = setmetatable({}, RowRender)
  o.topleft = {x or 1, y or 1}
  return o
end

function RowRender:width(row)
  return self.STEP_WIDTH * row.n
end

function RowRender:draw(row, beats)
  -- precaution, close any path which may have been left open
  --screen.close()
  -- draw from bottom, left
  local x = self.topleft[1]
  local y = self.topleft[2] + self.BAR_HEIGHT
  for i, step in ipairs(row.steps) do
    if i > row.n then break end -- FIXME: move this iteration detail to Row
    --screen.move(x, y)
    if step:is_active() then
      local width = math.floor(util.linlin(0, 1, 1, self.BAR_WIDTH, step.duration)) -- FIXME: 0 duration really?
      local height = math.floor(util.linlin(0, 1, 1, self.BAR_HEIGHT, step.velocity))
      --print("drawing", x, y, width, height)
      screen.rect(x, y - height, width, height)
      local level = math.floor(util.linlin(0, 1, 2, 12, step.chance))
      screen.level(level)
      screen.fill()
    end
    x = x + self.STEP_WIDTH
  end

  -- playhead
  x = self.topleft[1]
  y = self.topleft[2] + self.BAR_HEIGHT + 4
  screen.move(x, y)
  screen.line_rel(self:width(row) * row:head_position(beats), 0)
  screen.level(1)
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
-- script logic
--

rows = {
  Row.new{ n = 14 },
  Row.new{ n = 8  },
  Row.new{ n = 8  },
  Row.new{ n = 16 },
}

renderers = { RowRender.new(), RowRender.new(), RowRender.new(), RowRender.new() }

dirty = true

function redraw()
  --if not dirty then return end
  local beats = clock.get_beats()
  screen.clear()
  for i, r in ipairs(renderers) do
    --print("drawing", i, r)
    r:draw(rows[i], beats)
  end
  screen.update()
  dirty = false
end

function randomize()
  for i, r in ipairs(rows) do
    r:randomize()
  end
  dirty = true
  redraw()
end

function key(n, z)
  if n == 3 and z == 1 then
    randomize()
  end
end


function init()
  randomize()
  layout_vertical(0, 2, renderers)

  -- screen
  clock.run(function()
    while true do
      clock.sleep(1/32)
      redraw()
    end
  end)
end

