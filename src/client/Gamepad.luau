--!strict
-- Controller buttons (see DESIGN.md Controls):
--   X  Fight (or Retreat in a fight), unless a prompt is on screen (X triggers prompts)
--   Y  how to fuse     LB  Robux shop     B  close the open menu
--   View / touchpad    Roblox's free cursor (Platform.luau), which reaches everything else
-- The pad pictures on the buttons come from PadStickers; opening a menu turns the free
-- cursor on by itself (Platform.menuChanged).

local UserInputService = game:GetService("UserInputService")

local Gamepad = {}

local actions: { [Enum.KeyCode]: () -> () } = {}

function Gamepad.bind(key: Enum.KeyCode, fn: () -> ())
	actions[key] = fn
end

function Gamepad.init()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed and input.KeyCode ~= Enum.KeyCode.ButtonB then
			return
		end
		local fn = actions[input.KeyCode]
		if fn then
			fn()
		end
	end)
end

return Gamepad
