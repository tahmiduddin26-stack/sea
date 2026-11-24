--!strict
-- Cannon Gallery ballistics: where each ship's two gallery cannons sit, how the barrel turns, and the
-- arc a cannonball flies (a launch speed and gravity, Config.LIVE_CRATES). Shared so the server
-- re-flies exactly the same arc to check a hit (server/CrateService) that the client drew (client/CannonView).

local Config = require(script.Parent.Config)

local Ballistics = {}

Ballistics.SCALE = 2.2 -- the Blender "Cannon" rig is built this big on the platform
Ballistics.PIVOT = Vector3.new(0, 1.15, 0.4) -- the rig's barrel bone pivot (unscaled)

-- the cannon's resting frame on its platform: barrel (-Z) pointing out over its rail
function Ballistics.base(shipCf: CFrame, side: string): CFrame
	local p = Config.CANNON_GAME_POS[side]
	local yaw = if side == "Port" then math.pi / 2 else -math.pi / 2
	return shipCf * CFrame.new(p.X, Config.DECK_Y + Config.CANNON_GAME_Y, p.Z) * CFrame.Angles(0, yaw, 0)
end

-- keep an aim inside what the cannon can turn to (radians in, radians out)
function Ballistics.clamp(yaw: number, pitch: number): (number, number)
	local L = Config.LIVE_CRATES
	if yaw ~= yaw then
		yaw = 0
	end
	if pitch ~= pitch then
		pitch = 0
	end
	return math.clamp(yaw, -math.rad(L.yaw), math.rad(L.yaw)), math.clamp(pitch, math.rad(L.pitchMin), math.rad(L.pitchMax))
end

-- the barrel's frame at its pivot, turned (yaw) and tilted up (pitch)
function Ballistics.barrel(base: CFrame, yaw: number, pitch: number): CFrame
	return base * CFrame.Angles(0, yaw, 0) * CFrame.new(Ballistics.PIVOT * Ballistics.SCALE) * CFrame.Angles(pitch, 0, 0)
end

-- where the ball leaves the muzzle and how fast it is going
function Ballistics.launch(base: CFrame, yaw: number, pitch: number): (Vector3, Vector3)
	local b = Ballistics.barrel(base, yaw, pitch)
	local S = Ballistics.SCALE
	return (b * CFrame.new(0, 0.1 * S, -2.5 * S)).Position, b.LookVector * Config.LIVE_CRATES.speed
end

-- the ball's position t seconds after it left the muzzle
function Ballistics.at(p0: Vector3, v0: Vector3, t: number): Vector3
	return p0 + v0 * t + Vector3.new(0, -0.5 * Config.LIVE_CRATES.gravity * t * t, 0)
end

-- how close the flight passes to a point (until it hits the water), and when (seconds after firing)
function Ballistics.closest(p0: Vector3, v0: Vector3, target: Vector3): (number, number)
	local best, bestT = math.huge, 0
	local t = 0
	while t < 8 do
		local p = Ballistics.at(p0, v0, t)
		local d = (p - target).Magnitude
		if d < best then
			best, bestT = d, t
		end
		if p.Y < Config.SEA_LEVEL - 3 then
			break
		end
		t += 1 / 120
	end
	return best, bestT
end

return Ballistics
