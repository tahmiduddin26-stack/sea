--!strict
-- Server creates every remote; clients wait for them. Use Remotes.event / Remotes.func by name.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local FOLDER = "Remotes"
local EVENTS = {
	"MiniGame", -- S->owner private Crab Cove round state
	"Snapshot", -- S->C full data snapshot
	"Toast", -- S->C (text, color?)
	"Battle", -- S->all (ownerUserId, kind, payload) battle beats so everyone can watch
	"FishingDive", -- C->S steering direction, S->owner gate results
	"Reveal", -- S->C (kind "hatch"|"fuse", monster info) big reveal card
	"Tutorial", -- S->C (step) tutorial moved on
	"IntroSeen", -- C->S intro cinematic finished (or skipped)
	"Offline", -- S->C (seconds, coins) earned while away
	"Track", -- C->S (kind, name) analytics: a vendor menu opened, an offer seen / prompted
	"Crates", -- S->all live crates + cannon shots (server/CrateService)
}
local FUNCTIONS = {
	"Action", -- C->S (name, arg) -> ok, message. Fight, Retreat, Speed, Fuse, Skip, Upgrade, BuyNest, Code, UnlockFloor
}

local folder: Folder

local function getFolder(): Folder
	if folder then
		return folder
	end
	if RunService:IsServer() then
		local f = ReplicatedStorage:FindFirstChild(FOLDER)
		if not f then
			f = Instance.new("Folder")
			f.Name = FOLDER
			f.Parent = ReplicatedStorage
		end
		for _, name in EVENTS do
			if not f:FindFirstChild(name) then
				local ev = Instance.new("RemoteEvent")
				ev.Name = name
				ev.Parent = f
			end
		end
		for _, name in FUNCTIONS do
			if not f:FindFirstChild(name) then
				local fn = Instance.new("RemoteFunction")
				fn.Name = name
				fn.Parent = f
			end
		end
		folder = f :: Folder
	else
		folder = ReplicatedStorage:WaitForChild(FOLDER) :: Folder
	end
	return folder
end

function Remotes.event(name: string): RemoteEvent
	return getFolder():WaitForChild(name) :: RemoteEvent
end

function Remotes.func(name: string): RemoteFunction
	return getFolder():WaitForChild(name) :: RemoteFunction
end

function Remotes.init()
	getFolder()
end

return Remotes
