--!strict
-- Animates every townsperson the server built (tag "Npc"): waving, reading, hovering.
-- Only rigs near the camera are stepped, and far ones are skipped entirely.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Npc = require(ReplicatedStorage:WaitForChild("Shared").Npc)

local NpcView = {}

local NEAR = 120
local frame = 0
local rigs: { [Model]: Npc.Rig } = {}

local function add(model: Instance)
	if not model:IsA("Model") or rigs[model] then
		return
	end
	-- wait a beat so every part has replicated before the rest pose is recorded
	task.defer(function()
		if model.Parent and not rigs[model] then
			local rig = Npc.register(model)
			if rig then
				rigs[model] = rig
			end
		end
	end)
end

function NpcView.init()
	for _, m in CollectionService:GetTagged("Npc") do
		add(m)
	end
	CollectionService:GetInstanceAddedSignal("Npc"):Connect(add)
	CollectionService:GetInstanceRemovedSignal("Npc"):Connect(function(m)
		rigs[m :: Model] = nil
	end)
	RunService.RenderStepped:Connect(function()
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		-- townsperson idles are gentle: 30 updates a second is plenty, and only ones you can see
		frame += 1
		if frame % 2 == 0 then
			return
		end
		local camPos = cam.CFrame.Position
		local look = cam.CFrame.LookVector
		local t = os.clock()
		for model, rig in rigs do
			if not model.Parent then
				rigs[model] = nil
			else
				local d = rig.restRoot.Position - camPos
				local dist = d.Magnitude
				if dist < NEAR and (dist < 24 or d.Unit:Dot(look) > -0.2) then
					Npc.step(rig, t)
				end
			end
		end
	end)
end

return NpcView
