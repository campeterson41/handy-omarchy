-- Handy dictation shortcuts. Edit freely; the installer will not overwrite this file.
local toggle = os.getenv("HOME") .. "/.local/bin/handy-toggle"

-- Hold F9 to talk: press starts recording, release stops and pastes. [f9]
pcall(hl.unbind, "F9") -- [f9]
hl.bind("F9", hl.dsp.exec_cmd(toggle), { transparent = true }) -- [f9]
hl.bind("F9", hl.dsp.exec_cmd(toggle), { release = true, transparent = true }) -- [f9]

-- Super+Ctrl+X: press once to start, again to stop.
pcall(hl.unbind, "SUPER + CTRL + X")
o.bind("SUPER + CTRL + X", "Toggle Handy dictation", toggle)
