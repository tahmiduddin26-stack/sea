--!strict
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Dive = require(Shared.FishingDive)
local Remotes = require(Shared.Remotes)

local Sound = require(script.Parent.Sound)
local UI = require(script.Parent.UI)

local FishingDiveView = {}
local C = UI.Colors
local GREEN = Color3.fromRGB(105, 255, 165)
local RED = Color3.fromRGB(255, 115, 120)
local ACTION = "SteerFishingHook"
local LEFT = { [Enum.KeyCode.A] = true, [Enum.KeyCode.Left] = true, [Enum.KeyCode.DPadLeft] = true }

local function luckText(mult: number): string
	return (string.format("%.2f", mult):gsub("0+$", ""):gsub("%.$", "")) .. "×"
end

local function glassPanel(parent: Instance, overlay: ScreenGui, cf: CFrame, width: number, good: boolean, mult: number)
	local color = if good then GREEN else RED
	UI.new("Part", {
		Name = if good then "LuckBoost" else "LuckPenalty",
		Size = Vector3.new(width, 0.06, 10),
		CFrame = cf,
		Color = color,
		Material = Enum.Material.Glass,
		Transparency = 0.58,
		Anchored = true,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		CastShadow = false,
		Parent = parent,
	})
	-- Project the rim and label to the HUD so they stay legible through trench geometry and water.
	local outline = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = overlay })
	local edges: { Frame } = {}
	local corners = { cf * Vector3.new(-width / 2, 0, -5), cf * Vector3.new(width / 2, 0, -5), cf * Vector3.new(width / 2, 0, 5), cf * Vector3.new(-width / 2, 0, 5) }
	for i = 1, #corners do
		edges[i] = UI.new("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Parent = outline }, { UI.corner(2) })
	end
	local badge = UI.panel({
		Color = if good then Color3.fromRGB(24, 121, 85) else Color3.fromRGB(152, 50, 64),
		Radius = 8,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = outline,
	})
	UI.label({
		Text = luckText(mult) .. " LUCK",
		TextColor3 = color,
		MaxText = 22,
		Stroke = 1.8,
		Size = UDim2.fromScale(0.96, 0.92),
		Position = UDim2.fromScale(0.02, 0.04),
		Parent = badge,
	})
	local projected: { Vector2 } = {}
	return function(camera: Camera, visible: boolean)
		outline.Visible = visible
		if not visible then
			return
		end
		for i, corner in corners do
			local point = camera:WorldToViewportPoint(corner)
			if point.Z <= 0.1 then
				outline.Visible = false
				return
			end
			projected[i] = Vector2.new(point.X, point.Y)
		end
		for i, edge in edges do
			local a, b = projected[i], projected[i % #edges + 1]
			local delta = b - a
			local mid = (a + b) / 2
			edge.Position = UDim2.fromOffset(mid.X, mid.Y)
			edge.Size = UDim2.fromOffset(delta.Magnitude + 2, 3)
			edge.Rotation = math.deg(math.atan2(delta.Y, delta.X))
		end
		local center = camera:WorldToViewportPoint(cf.Position)
		local labelWidth = math.clamp(math.min((projected[2] - projected[1]).Magnitude, (projected[3] - projected[4]).Magnitude) * 0.85, 48, 122)
		badge.Position = UDim2.fromOffset(center.X, center.Y)
		badge.Size = UDim2.fromOffset(labelWidth, math.clamp(labelWidth * 0.3, 18, 34))
	end
end

function FishingDiveView.new(fx: Folder, column: CFrame, outward: Vector3, cast: Dive.Cast, down: number, sea: number, bottom: number)
	local remote = Remotes.event("FishingDive")
	local start = cast.start
	local practice = cast.practice
	local right = Vector3.yAxis:Cross(outward)
	local cameraOffset = math.min(30, math.max(11, (sea - bottom) / down * 0.4))
	local panels: { Folder } = {}
	local drawPanels: { { (Camera, boolean) -> () } } = {}
	local overlay = UI.new("ScreenGui", {
		Name = "FishingGateOverlay",
		ResetOnSpawn = false,
		DisplayOrder = 5,
		ScreenInsets = Enum.ScreenInsets.None,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	for i, gate in Dive.GATES do
		local pair = Instance.new("Folder")
		pair.Name = "LuckGate" .. i
		panels[i] = pair
		drawPanels[i] = {}
		local goodSide = Dive.goodSide(cast.firstSide, i)
		local gateY = sea - 6 + (bottom - (sea - 6)) * Dive.depth(gate.at)
		local width = Dive.GATE_OUTER - Dive.GATE_INNER
		for _, side in { -1, 1 } do
			local center = Vector3.new(column.X, gateY, column.Z) + right * (side * (Dive.GATE_INNER + width / 2))
			table.insert(drawPanels[i], glassPanel(
				pair,
				overlay,
				CFrame.lookAt(center, center - outward),
				width,
				side == goodSide,
				if side == goodSide then gate.boost else Dive.PENALTY
			))
		end
	end

	local gui = UI.new("ScreenGui", {
		Name = "FishingDive",
		ResetOnSpawn = false,
		DisplayOrder = 6,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	local card = UI.panel({
		Color = C.Deep,
		Radius = 16,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.new(0.92, 0, 0, 78),
		Parent = gui,
	})
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(340, 78), Parent = card })
	local title = UI.label({
		Text = "Hit green gates. Dodge red!",
		MaxText = 22,
		Stroke = 1.8,
		Size = UDim2.new(1, -12, 0, 25),
		Position = UDim2.fromOffset(6, 5),
		Parent = card,
	})
	local hint = UI.label({
		Text = "",
		MaxText = 16,
		Stroke = 1.5,
		Size = UDim2.new(1, -12, 0, 19),
		Position = UDim2.fromOffset(6, 31),
		Parent = card,
	})
	local score = UI.label({
		Text = "",
		MaxText = 18,
		Stroke = 1.5,
		TextColor3 = C.Gold,
		Size = UDim2.new(1, -12, 0, 22),
		Position = UDim2.fromOffset(6, 51),
		Parent = card,
	})
	local controls = UI.new("Frame", {
		Name = "Steering",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -30),
		Size = UDim2.new(0.82, 0, 0, 47),
		Parent = gui,
	})
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(305, 47), Parent = controls })
	local left = UI.button({
		Name = "Left",
		Text = "◀  LEFT",
		Color = C.Sea,
		Size = UDim2.fromScale(0.47, 1),
		Selectable = false,
		Parent = controls,
	})
	local rightButton = UI.button({
		Name = "Right",
		Text = "RIGHT  ▶",
		Color = C.Sea,
		Size = UDim2.fromScale(0.47, 1),
		Position = UDim2.fromScale(0.53, 0),
		Selectable = false,
		Parent = controls,
	})
	controls.Visible = false

	local caught = false
	local function updateHint(input: Enum.UserInputType)
		if caught then
			return
		end
		if input.Name:match("^Gamepad") then
			hint.Text = "Use the left stick or D-pad"
		elseif input == Enum.UserInputType.Touch then
			hint.Text = "Hold LEFT or RIGHT to steer"
		else
			hint.Text = "Hold A / D or ← / → to steer"
		end
	end
	updateHint(UserInputService:GetLastInputType())
	local connections: { RBXScriptConnection } = { UserInputService.LastInputTypeChanged:Connect(updateHint) }
	local held: { [Enum.KeyCode]: number } = {}
	local pointers: { [InputObject]: number } = {}
	local stick = 0
	local steering = Dive.steering()
	local active = false
	local bound = false
	local shown = 0
	local totalLuck = 1
	local renderName = "FishingGateOverlay" .. start
	RunService:BindToRenderStep(renderName, Enum.RenderPriority.Camera.Value + 2, function()
		local camera = workspace.CurrentCamera
		if not camera then return end
		for i, pair in drawPanels do
			local visible = not caught and i == shown + 1 and panels[i].Parent ~= nil
			for _, draw in pair do draw(camera, visible) end
		end
	end)
	local function showGate(index: number)
		local gate = Dive.GATES[index]
		if not gate then
			return
		end
		local greenOnLeft = Dive.goodSide(cast.firstSide, index) == -1
		local green = '<font color="#69FFA5">' .. luckText(gate.boost) .. "</font>"
		local red = '<font color="#FF7378">' .. luckText(Dive.PENALTY) .. "</font>"
		UI.setText(left, "◀ LEFT  " .. (if greenOnLeft then green else red))
		UI.setText(rightButton, (if greenOnLeft then red else green) .. "  RIGHT ▶")
	end

	local function showScore(index: number)
		local text = if practice then ("Practice • " .. luckText(totalLuck) .. " Luck") else (luckText(totalLuck) .. " Egg Luck")
		score.Text = if caught then text else (text .. "   •   Gate " .. index .. " / " .. #Dive.GATES)
	end
	showScore(0)
	table.insert(
		connections,
		remote.OnClientEvent:Connect(function(id: number, index: number, multiplier: number, luck: number)
			if id ~= start then
				return
			end
			totalLuck = luck
			showScore(index)
			if not caught then
				title.Text = if multiplier > 1
					then "Green gate hit!"
					elseif multiplier < 1 then (luckText(multiplier) .. " luck • Dodge red gates!")
					else "Gate skipped • No change"
				title.TextColor3 = if multiplier > 1 then GREEN elseif multiplier < 1 then RED else C.White
				if multiplier ~= 1 then
					Sound.play("ZoneChime", 0.85, if multiplier > 1 then 1.15 + index * 0.14 else 0.6)
				end
			end
		end)
	)

	local function steer(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			stick = if state ~= Enum.UserInputState.End
					and state ~= Enum.UserInputState.Cancel
					and math.abs(input.Position.X) > 0.35
				then math.sign(input.Position.X)
				else 0
		elseif state == Enum.UserInputState.Begin then
			held[input.KeyCode] = if LEFT[input.KeyCode] then -1 else 1
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			held[input.KeyCode] = nil
		end
		return Enum.ContextActionResult.Sink
	end
	for direction, button in { [-1] = left, [1] = rightButton } do
		table.insert(
			connections,
			button.InputBegan:Connect(function(input: InputObject)
				if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
					pointers[input] = direction
				end
			end)
		)
	end
	table.insert(
		connections,
		UserInputService.InputEnded:Connect(function(input)
			pointers[input] = nil
		end)
	)
	table.insert(
		connections,
		UserInputService.WindowFocusReleased:Connect(function()
			table.clear(held)
			table.clear(pointers)
			stick = 0
		end)
	)

	local function stopSteering()
		if bound then
			ContextActionService:UnbindAction(ACTION)
			bound = false
		end
		controls.Visible = false
	end

	local view = {}
	function view.step(progress: number): Vector3
		if not active then
			active = true
			bound = true
			controls.Visible = true
			ContextActionService:BindActionAtPriority(
				ACTION,
				steer,
				false,
				3000,
				Enum.KeyCode.A,
				Enum.KeyCode.D,
				Enum.KeyCode.Left,
				Enum.KeyCode.Right,
				Enum.KeyCode.DPadLeft,
				Enum.KeyCode.DPadRight,
				Enum.KeyCode.Thumbstick1
			)
			for _, key in { Enum.KeyCode.A, Enum.KeyCode.D, Enum.KeyCode.Left, Enum.KeyCode.Right } do
				if UserInputService:IsKeyDown(key) then
					held[key] = if LEFT[key] then -1 else 1
				end
			end
		end
		local x = Dive.move(steering, progress, down)
		while shown < #panels and progress >= Dive.GATES[shown + 1].at do
			shown += 1
			panels[shown].Parent = nil
		end
		local current = panels[shown + 1]
		if current and not current.Parent then
			current.Parent = fx
			showGate(shown + 1)
		end
		if progress >= Dive.CENTER then
			stopSteering()
			local u = math.clamp((progress - Dive.CENTER) / (1 - Dive.CENTER), 0, 1)
			x *= 1 - u * u * (3 - 2 * u)
		else
			local direction = stick
			for _, value in held do
				direction += value
			end
			for _, value in pointers do
				direction += value
			end
			direction = math.sign(direction)
			if direction ~= steering.direction then
				steering.direction = direction
				remote:FireServer(start, direction)
			end
		end
		return right * x
	end

	function view.camera(center: Vector3, lateral: Vector3): CFrame
		local target = center + lateral * 0.22
		return CFrame.lookAt(
			target + outward * 13 + Vector3.yAxis * (8 + cameraOffset * 0.4),
			target - Vector3.yAxis * (cameraOffset * 0.72)
		)
	end

	function view.caught()
		caught = true
		stopSteering()
		title.Text = "Egg caught!"
		title.TextColor3 = C.Gold
		hint.Text = if practice then "Try the green gates on future catches" else "Reeling it up to your ship"
		showScore(#Dive.GATES)
	end

	function view.destroy()
		stopSteering()
		RunService:UnbindFromRenderStep(renderName)
		for _, connection in connections do
			connection:Disconnect()
		end
		for _, panel in panels do
			panel:Destroy()
		end
		gui:Destroy()
		overlay:Destroy()
	end
	return view
end

return FishingDiveView
