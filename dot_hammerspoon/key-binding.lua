local wm = require('window-management')
local hk = require "hs.hotkey"

-- * Key Binding Utility
--- Bind hotkey for window management.
-- @function windowBind
-- @param {table} hyper - hyper key set
-- @param { ...{key=value} } keyFuncTable - multiple hotkey and function pairs
--   @key {string} hotkey
--   @value {function} callback function
local function windowBind(hyper, keyFuncTable)
  for key,fn in pairs(keyFuncTable) do
    hk.bind(hyper, key, fn)
  end
end

local function toggleInput(display, toInput)
  local cmd = '/usr/local/bin/m1ddc display ' .. tostring(display) .. ' set input ' .. tostring(toInput)
  hs.execute(cmd, true)
end

-- * Set monitor input
-- DDC/CI input-source codes, named after the VESA MCCS table. Panel firmware
-- deviates from that table often enough that the names describe the standard,
-- not a promise about which cable is physically lit; confirm against the
-- display before trusting a name over the number.
local INPUT_DP1 = 15
local INPUT_HDMI1 = 17

hk.bind({"ctrl", "shift"}, '1', function()
  toggleInput(2, INPUT_DP1)
  hs.timer.doAfter(0.5, function()
    toggleInput(1, INPUT_HDMI1)
  end)
end)
hk.bind({"ctrl", "shift"}, '2', function() toggleInput(1, INPUT_HDMI1) end)
hk.bind({"ctrl", "shift"}, '3', function() toggleInput(2, INPUT_HDMI1) end)

-- * Set window position on current display
windowBind({"ctrl", "cmd"}, {
  m = wm.maximizeWindow,    -- ⌃⌘ + M
  c = wm.centerOnScreen,    -- ⌃⌘ + C
  left = wm.leftHalf,       -- ⌃⌘ + ←
  right = wm.rightHalf,     -- ⌃⌘ + →
  up = wm.topHalf,          -- ⌃⌘ + ↑
  down = wm.bottomHalf      -- ⌃⌘ + ↓
})

-- * Throw window to screen
windowBind({"ctrl", "alt", "cmd"}, {
  left = wm.throwLeft,      -- ⌃⌥⌘ + ←
  right = wm.throwRight,    -- ⌃⌥⌘ + →
  j = wm.cycleLeft,         -- ⌃⌥⌘ + j
  k = wm.cycleRight         -- ⌃⌥⌘ + k
})

-- * Set Window Position on screen
windowBind({"ctrl", "alt", "shift"}, {
  left = wm.rightToLeft,     -- ⌃⌥⇧ + ←
  right = wm.rightToRight,   -- ⌃⌥⇧ + →
  up = wm.bottomUp,          -- ⌃⌥⇧ + ↑
  down = wm.bottomDown       -- ⌃⌥⇧ + ↓
})

-- * Set Window Position on screen
windowBind({"alt", "cmd", "shift"}, {
  left = wm.leftToLeft,      -- ⌥⌘⇧ + ←
  right = wm.leftToRight,    -- ⌥⌘⇧ + →
  up = wm.topUp,             -- ⌥⌘⇧ + ↑
  down = wm.topDown          -- ⌥⌘⇧ + ↓
})
