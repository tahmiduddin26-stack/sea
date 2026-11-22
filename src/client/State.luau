--!strict
-- Client mirror of the server snapshot, plus a Changed signal and small shared flags.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)

local State = {}

State.snapshot = nil :: any
State.cinematic = false -- intro playing: hide HUD
State.revealing = false

local changed = Instance.new("BindableEvent")
State.Changed = changed.Event -- (snapshot)

local clockOffset = 0
-- server os.time() estimate
function State.now(): number
	return os.time() + clockOffset
end

function State.init()
	Remotes.event("Snapshot").OnClientEvent:Connect(function(snap)
		State.snapshot = snap
		if snap.serverNow then
			clockOffset = snap.serverNow - os.time()
		end
		changed:Fire(snap)
	end)
end

function State.waitForData(): any
	while not State.snapshot do
		State.Changed:Wait()
	end
	return State.snapshot
end

function State.hasPass(name: string): boolean
	local s = State.snapshot
	return s ~= nil and s.passes ~= nil and s.passes[name] == true
end

-- Ask the server to do something; returns ok, message
function State.action(name: string, arg: any?): (boolean, string?)
	local ok, a, b = pcall(function()
		return Remotes.func("Action"):InvokeServer(name, arg)
	end)
	if not ok then
		return false, nil
	end
	return a, b
end

return State
