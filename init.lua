local obj = {}
obj.__index = obj

obj.name = "ShowInAppleMusic"
obj.version = "0.2.0"
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
  local startTime = hs.timer.secondsSinceEpoch()
  local maxNodes = 500
  local maxDepth = 15
  local log = function(msg)
    hs.printf("[ShowInAppleMusic] %s", msg)
  end

  if not isAppleMusicFrontmost() then
    log("Not in Apple Music")
    return false, "Not in Apple Music"
  end
  local app = hs.application.frontmostApplication()
  if not app then
    log("No frontmost app")
    return false, "No frontmost app"
  end

  local axApp = ax.applicationElement(app)
  if not axApp then
    log("No AX app")
    return false, "No AX app"
  end

  -- Only use the frontmost window as the candidate root
  local wins = axApp:attributeValue("AXWindows") or {}
  local candidate = wins[1]
  if not candidate then
    local elapsed = hs.timer.secondsSinceEpoch() - startTime
    log(string.format("No frontmost window found after %.3fs", elapsed))
    return false, "No frontmost window"
  end

  local function isMenuContainer(el)
    local role = el and el:attributeValue("AXRole")
    return role == "AXMenu" or role == "AXMenuBar" or role == "AXUnknown"
  end

  local totalNodes = 0

  -- Only pass: find AXMenu -> AXMenuItem in the frontmost window
  local queue = { { el = candidate, depth = 1 } }
  local visited = {}
  visited[candidate] = true
  while #queue > 0 do
    if totalNodes >= maxNodes then
      log("Node limit reached")
      break
    end
    local item = table.remove(queue, 1)
    local el, depth = item.el, item.depth
    totalNodes = totalNodes + 1
    if depth > maxDepth then
      log("Depth limit reached at node " .. tostring(el))
      -- skip further traversal from this node
    else
      if isMenuContainer(el) then
        for _, mi in ipairs(childrenOf(el)) do
          if mi:attributeValue("AXRole") == "AXMenuItem" then
            local title = mi:attributeValue("AXTitle")
            if matches(title, self.matchText) then
              local elapsed = hs.timer.secondsSinceEpoch() - startTime
              log(string.format("Found menu item after %.3fs, nodes: %d", elapsed, totalNodes))
              return press(mi), title
            end
          end
        end
      end
      for _, ch in ipairs(childrenOf(el)) do
        if not visited[ch] then
          table.insert(queue, { el = ch, depth = depth + 1 })
          visited[ch] = true
        end
      end
    end
  end

  local elapsed = hs.timer.secondsSinceEpoch() - startTime
  log(string.format("Menu item not found after %.3fs, nodes: %d", elapsed, totalNodes))
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
      hs.notify.new({
        title = "ShowInAppleMusic",
        informativeText = "Menu item not found: " .. tostring(detail),
        autoWithdraw = true,
        withdrawAfter = 5
      }):send()
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
