--!strict
-- Named sound slots from Config.SOUNDS (0 = silent until uploaded). Each slot can list
-- several takes ("Hit" -> { id1, id2 }) and one is picked at random. Music crossfades
-- between the calm deck track and the battle track.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local Sound = {}

local folder = Instance.new("Folder")
folder.Name = "TideSfx"
folder.Parent = SoundService

local function ids(slot: string): { number }
	local v = (Config.SOUNDS :: any)[slot]
	if typeof(v) == "table" then
		return v
	elseif typeof(v) == "number" and v ~= 0 then
		return { v }
	end
	return {}
end

local cache: { [number]: Sound } = {}
local function soundFor(id: number): Sound
	local s = cache[id]
	if not s then
		s = Instance.new("Sound")
		s.SoundId = "rbxassetid://" .. id
		s.Parent = folder
		cache[id] = s
	end
	return s
end

function Sound.play(slot: string, volume: number?, pitch: number?)
	local list = ids(slot)
	if #list == 0 then
		return
	end
	local base = soundFor(list[math.random(1, #list)])
	local s = base:Clone()
	s.Volume = (volume or 0.6)
	s.PlaybackSpeed = (pitch or 1) * (0.95 + math.random() * 0.1)
	s.Parent = folder
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	task.delay(8, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

local music: { [string]: Sound } = {}
local current = ""
local function track(slot: string): Sound?
	if music[slot] then
		return music[slot]
	end
	local list = ids(slot)
	if #list == 0 then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. list[1]
	s.Looped = true
	s.Volume = 0
	s.Parent = folder
	music[slot] = s
	return s
end

-- "Music" (deck) or "BattleMusic"
function Sound.music(slot: string)
	if slot == current then
		return
	end
	current = slot
	local TweenService = game:GetService("TweenService")
	for name, s in music do
		if name ~= slot then
			TweenService:Create(s, TweenInfo.new(1.2), { Volume = 0 }):Play()
		end
	end
	local s = track(slot)
	if s then
		if not s.IsPlaying then
			s:Play()
		end
		TweenService:Create(s, TweenInfo.new(1.2), { Volume = 0.35 }):Play()
	end
end

return Sound
