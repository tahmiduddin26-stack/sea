--!strict
-- Animates every townsperson the server built (tag "Npc"): waving, reading, hovering.
-- Only rigs near the camera are stepped, and far ones are skipped entirely.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Players = game:GetService("Players")
local Npc = require(ReplicatedStorage:WaitForChild("Shared").Npc)
local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local Sound = require(script.Parent.Sound)
local State = require(script.Parent.State)

local NpcView = {}

local NEAR = 120
local frame = 0
local rigs: { [Model]: Npc.Rig } = {}
-- Walk up to a townsperson and they greet you with their own little sound (Config.NPC_SOUNDS), once
-- every GREET_EVERY seconds each, so standing next to one never turns into a noise
local GREET_RADIUS = 11
local GREET_EVERY = 25
local lastGreet: { [Model]: number } = {}

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
		local char = Players.LocalPlayer.Character
		local me = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		for model, rig in rigs do
			if not model.Parent then
				rigs[model] = nil
			else
				local d = rig.restRoot.Position - camPos
				local dist = d.Magnitude
				if dist < NEAR and (dist < 24 or d.Unit:Dot(look) > -0.2) then
					Npc.step(rig, t)
				end
				-- a hello when you walk up (not during a cutscene)
				if me and not State.cinematic and (rig.restRoot.Position - me.Position).Magnitude < GREET_RADIUS and t - (lastGreet[model] or -GREET_EVERY) >= GREET_EVERY then
					lastGreet[model] = t
					local slot = (Config.NPC_SOUNDS :: any)[model.Parent and model.Parent.Name or ""]
					if slot then
						Sound.play(slot, 0.35, 0.9 + (#model.Name % 5) * 0.05)
					end
				end
			end
		end
	end)
end

return NpcView
