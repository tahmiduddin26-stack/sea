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

-- Two mixer channels the Settings panel turns up and down: every track goes through Music,
-- every one-shot through Sfx. Their Volume is the player's slider (0..1); the per-sound
-- volumes below stay the mix.
-- The Music group's real Volume is the player's slider x a duck factor, so big moments
-- (a hatch, a win, a boss intro) can dip the soundtrack without touching the slider.
local musicGroup = Instance.new("SoundGroup")
musicGroup.Name = "Music"
musicGroup.Volume = 1
musicGroup.Parent = SoundService
local sfxGroup = Instance.new("SoundGroup")
sfxGroup.Name = "Sfx"
sfxGroup.Volume = 1
sfxGroup.Parent = SoundService

local musicSlider = 1
-- 0..1, tweened by Sound.duck; a NumberValue so TweenService can drive it
local duckFactor = Instance.new("NumberValue")
duckFactor.Value = 1
local function applyMusic()
	musicGroup.Volume = musicSlider * duckFactor.Value
end
duckFactor.Changed:Connect(applyMusic)

-- kind: "music" | "sfx"; v is clamped to 0..1
function Sound.setVolume(kind: string, v: number)
	if kind == "music" then
		musicSlider = math.clamp(v, 0, 1)
		applyMusic()
	else
		sfxGroup.Volume = math.clamp(v, 0, 1)
	end
end

function Sound.getVolume(kind: string): number
	return if kind == "music" then musicSlider else sfxGroup.Volume
end

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
		s.SoundGroup = sfxGroup
		s.Parent = folder
		cache[id] = s
	end
	return s
end

-- Music ducking. Every duck holds the music down until it is released; overlapping ducks
-- (Hatch then Win straight after) stack, and the music only swells back once the last ends.
local TweenService = game:GetService("TweenService")
local DUCK_LEVEL = 0.25 -- music volume while an event sound plays (x the player's slider)
local DUCK_DOWN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local DUCK_UP = TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
local DUCK_MAX = 8 -- seconds; safety net so a duck can never stick
local holds = 0

-- Slots that count as an "event" and duck the music on their own.
local DUCKS: { [string]: boolean } = {
	Hatch = true,
	EggPop = true,
	Fuse = true,
	Win = true,
	Lose = true,
	BossIntro = true,
	Upgrade = true,
}

-- Dip the music; returns a release function (safe to call more than once).
function Sound.duck(seconds: number?): () -> ()
	holds += 1
	if holds == 1 then
		TweenService:Create(duckFactor, DUCK_DOWN, { Value = DUCK_LEVEL }):Play()
	end
	local released = false
	local function release()
		if released then
			return
		end
		released = true
		holds = math.max(holds - 1, 0)
		if holds == 0 then
			TweenService:Create(duckFactor, DUCK_UP, { Value = 1 }):Play()
		end
	end
	task.delay(math.min(seconds or DUCK_MAX, DUCK_MAX), release)
	return release
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
	local release: (() -> ())? = nil
	if DUCKS[slot] then
		-- hold until the sound ends; the length is a fallback if Ended never fires
		local len = if s.TimeLength > 0 then s.TimeLength / s.PlaybackSpeed + 0.2 else DUCK_MAX
		release = Sound.duck(len)
	end
	s:Play()
	s.Ended:Once(function()
		if release then
			release()
		end
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
	s.SoundGroup = musicGroup
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
