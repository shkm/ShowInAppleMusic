local obj = {}
obj.__index = obj

obj.name = "ShowInAppleMusic"
obj.version = "0.1.0"
obj.author = "Jamie Schembri"
obj.homepage = "https://github.com/shkm/ShowInAppleMusic"
obj.license = "MIT"

-- Overridables
obj.matchText = "Show in Apple Music" -- menu item to click
obj.openDelay = 0.10                  -- delay after right-click before searching
obj.clickModifiers = { alt = true }   -- which modifiers must be held with left click (e.g., {alt=true}, {cmd=true}, {ctrl=true, shift=true})

-- Internals (fixed)
local ax = require("hs.axuielement")

local function isAppleMusicFrontmost()
  local app = hs.application.frontmostApplication()
  if not app then return false end
  local bid = app:bundleID()
  return bid == "com.apple.Music" or bid == "com.apple.iTunes"
end

local function matches(text, target)
  if not text or not target then return false end
  return text:lower() == target:lower()
end

local function press(el)
  if not el then return false end
  if el:performAction("AXPress") then return true end
  local _ = el:setAttributeValue("AXFocused", true)
  return el:performAction("AXPress") or false
end

local function childrenOf(el)
  return (el and el:attributeValue("AXChildren")) or {}
end

-- Find the context menu and press the matching item
function obj:_selectItemFromContextMenu()
  if not isAppleMusicFrontmost() then
    return false, "Not in Apple Music"
  end
  local app = hs.application.frontmostApplication()
  if not app then return false, "No frontmost app" end

  local axApp = ax.applicationElement(app)
  if not axApp then return false, "No AX app" end

  local candidates = {}
  local function push(v) if v then table.insert(candidates, v) end end

  -- Windows, app root, and system-wide element
  local wins = axApp:attributeValue("AXWindows") or {}
  for _, w in ipairs(wins) do push(w) end
  push(axApp)
  push(ax.systemWideElement())

  local function isMenuContainer(el)
    local role = el and el:attributeValue("AXRole")
    return role == "AXMenu" or role == "AXMenuBar" or role == "AXUnknown"
  end

  -- Pass 1: find AXMenu -> AXMenuItem
  for _, root in ipairs(candidates) do
    if root then
      local queue = { root }
      local visited = hs.fnutils.copy(queue)
      local function seen(e)
        for _, x in ipairs(visited) do if x == e then return true end end
        return false
      end
      while #queue > 0 do
        local el = table.remove(queue, 1)
        if isMenuContainer(el) then
          for _, mi in ipairs(childrenOf(el)) do
            if mi:attributeValue("AXRole") == "AXMenuItem" then
              local title = mi:attributeValue("AXTitle")
              if matches(title, self.matchText) then
                return press(mi), title
              end
            end
          end
        end
        for _, ch in ipairs(childrenOf(el)) do
          if not seen(ch) then
            table.insert(queue, ch)
            table.insert(visited, ch)
          end
        end
      end
    end
  end

  -- Pass 2: transient windows containing menus
  for _, root in ipairs(candidates) do
    local queue = { root }
    local visited = hs.fnutils.copy(queue)
    local function seen(e)
      for _, x in ipairs(visited) do if x == e then return true end end
      return false
    end
    while #queue > 0 do
      local el = table.remove(queue, 1)
      local role = el and el:attributeValue("AXRole")
      if role == "AXWindow" or role == "AXSheet" or role == "AXPopover" or role == "AXDrawer" then
        for _, k in ipairs(childrenOf(el)) do
          if k:attributeValue("AXRole") == "AXMenu" then
            for _, mi in ipairs(childrenOf(k)) do
              if mi:attributeValue("AXRole") == "AXMenuItem" then
                local title = mi:attributeValue("AXTitle")
                if matches(title, self.matchText) then
                  return press(mi), title
                end
              end
            end
          end
        end
      end
      for _, ch in ipairs(childrenOf(el)) do
        if not seen(ch) then
          table.insert(queue, ch)
          table.insert(visited, ch)
        end
      end
    end
  end

  return false, "No matching item"
end

-- Main action: right-click at cursor, then select item
function obj:rightClickThenSelect()
  if not isAppleMusicFrontmost() then return end
  local pos = hs.mouse.absolutePosition()
  hs.eventtap.rightClick(pos)
  hs.timer.doAfter(self.openDelay or 0.10, function()
    local ok, detail = self:_selectItemFromContextMenu()
    if not ok then
      hs.alert.show("Menu item not found: " .. tostring(detail), 1, {}, 1, 5)
    end
  end)
end

-- Modifier check helper
local function flagsMatch(mods, flags)
  -- mods is a table like {alt=true, cmd=false, ctrl=true, shift=false}
  local want = {
    alt = mods.alt or false,
    cmd = mods.cmd or false,
    ctrl = mods.ctrl or false,
    shift = mods.shift or false,
    fn = mods.fn or false,
  }
  local have = {
    alt = flags.alt or false,
    cmd = flags.cmd or false,
    ctrl = flags.ctrl or false,
    shift = flags.shift or false,
    fn = flags.fn or false,
  }
  -- Require exact match: keys set true in want must be pressed; others must be not pressed
  return want.alt == have.alt
      and want.cmd == have.cmd
      and want.ctrl == have.ctrl
      and want.shift == have.shift
      and want.fn == have.fn
end

-- Bind to mouse left click with configurable modifiers; never consume the click
function obj:start()
  if self._tap then
    self._tap:stop()
    self._tap = nil
  end
  self._tap = hs.eventtap.new({ hs.eventtap.event.types.leftMouseDown }, function(e)
    if not isAppleMusicFrontmost() then return false end
    local f = e:getFlags()
    if flagsMatch(self.clickModifiers or {}, f) then
      -- Do not consume: return false so the app still receives the click
      hs.timer.doAfter(0.01, function()
        self:rightClickThenSelect()
      end)
    end
    return false
  end)
  self._tap:start()
  return self
end

function obj:stop()
  if self._tap then
    self._tap:stop()
    self._tap = nil
  end
  return self
end

return obj
