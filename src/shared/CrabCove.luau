--!strict
local Config = require(script.Parent.Config)

local Cove = {}
Cove.deliveryRadius = 9
Cove.crabWarning = 0.15 -- the crab rears up for this long when you get close, then snaps: very quick
Cove.tick = 0.1 -- the server updates a round this often (it was 0.25, which made the snap feel late)
Cove.stun = 0.55 -- after a snap that hits, you are held still this long while the hit plays, then sent to the keeper
Cove.safeTime = 2.5 -- no more hits for this long after you are sent back
Cove.eggCount = 12
Cove.hatchBoost = 1.5
Cove.hatchBoostSeconds = 10 * 60
Cove.hatchRewardEggs = 5
Cove.hatchRewardText = "1.5× hatch speed for 10 minutes"
Cove.crabCount = 8 -- each crab guards an egg (it was 4: the island felt empty)
Cove.eggMinDistance = 42 -- every egg is at least this far from the Cove Keeper
Cove.eggSpread = 30 -- a re-spawned egg is at least this far from where it was before
Cove.lives = 3
Cove.pickupRadius = 5.5
Cove.duration = 90

-- Only count extra progress during the part of the hatch covered by the boost.
function Cove.boostedHatchDuration(seconds: number, boostSeconds: number): number
	local accelerated = math.min(seconds / Cove.hatchBoost, math.max(0, boostSeconds))
	return seconds - accelerated * (Cove.hatchBoost - 1)
end

function Cove.keeperCFrame(host: BasePart): CFrame
	return host.CFrame * CFrame.new(0, 0.5, 8)
end

function Cove.inPlayArea(pos: Vector3): boolean
	local island = math.abs(pos.X) <= Config.HUB_RADIUS and math.abs(pos.Z) <= Config.HUB_RADIUS
	return pos.Y > 0 and island
end

function Cove.atKeeper(pos: Vector3, keeper: Vector3): boolean
	local offset = pos - keeper
	return Vector2.new(offset.X, offset.Z).Magnitude <= Cove.deliveryRadius and math.abs(offset.Y) <= 6
end

return Cove
