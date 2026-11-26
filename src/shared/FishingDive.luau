--!strict
local RodAnim = require(script.Parent.RodAnim)

local FishingDive = {}

FishingDive.CAST = RodAnim.SPLASH
FishingDive.GRAB = 0.75
FishingDive.FLY = 0.7
FishingDive.SLIDE = 0.12
FishingDive.CENTER = 0.88
FishingDive.LIMIT = 11.5
FishingDive.GATE_INNER = 2
FishingDive.GATE_OUTER = 13
FishingDive.PENALTY = 0.9
FishingDive.GATES = {
	{ at = 0.34, boost = 1.1 },
	{ at = 0.58, boost = 1.2 },
	{ at = 0.82, boost = 1.5 },
}

export type Steering = { x: number, at: number, direction: number }
export type Cast = { slot: number, time: number, rod: string?, start: number, firstSide: number, practice: boolean }

function FishingDive.downTime(total: number): number
	return math.max(1, total - FishingDive.CAST - FishingDive.GRAB - FishingDive.FLY) * 0.64
end

function FishingDive.depth(progress: number): number
	return math.clamp((progress - FishingDive.SLIDE) / (1 - FishingDive.SLIDE), 0, 1)
end

function FishingDive.goodSide(firstSide: number, index: number): number
	return if index % 2 == 1 then firstSide else -firstSide
end

function FishingDive.steering(): Steering
	return { x = 0, at = FishingDive.SLIDE, direction = 0 }
end

function FishingDive.move(steering: Steering, progress: number, downTime: number): number
	local at = math.clamp(progress, steering.at, FishingDive.CENTER)
	steering.x = math.clamp(steering.x + (at - steering.at) * downTime * 24 * steering.direction, -FishingDive.LIMIT, FishingDive.LIMIT)
	steering.at = at
	return steering.x
end

function FishingDive.multiplier(firstSide: number, index: number, x: number): number
	if math.abs(x) < FishingDive.GATE_INNER then
		return 1
	end
	return if x * FishingDive.goodSide(firstSide, index) > 0 then FishingDive.GATES[index].boost else FishingDive.PENALTY
end

return FishingDive
