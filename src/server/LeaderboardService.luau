--!strict
-- Global "Deepest Divers" leaderboard: every player's best depth goes into an
-- OrderedDataStore; the top 10 are drawn on the big board in the harbour. Falls back to
-- this server's players when DataStores are unavailable (Studio without API access).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local DataService = require(script.Parent.DataService)
local WorldBuilder = require(script.Parent.WorldBuilder)

local LeaderboardService = {}

local REFRESH = 60
local store: OrderedDataStore? = nil
pcall(function()
	store = DataStoreService:GetOrderedDataStore(Config.DATASTORE_NAME .. "_BestDepth")
end)

-- row index -> one { name, depth } label pair per board face
local rows: { { { name: TextLabel, depth: TextLabel } } } = {}
local nameCache: { [number]: string } = {}

local TIMBER = Color3.fromRGB(46, 28, 18)

local function buildBoard()
	local face = WorldBuilder.leaderboardFace
	if not face then
		return
	end
	-- the same board is drawn on both faces, so it reads from the docks and the plaza
	for _, side in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = side
		gui.CanvasSize = Vector2.new(560, 560)
		gui.LightInfluence = 0
		gui.Parent = face
		-- one clean row per diver: rank | name (cut with ... if long) | depth, so nothing overlaps
		local function text(parent: Instance, str: string, x: number, w: number, color: Color3, align: Enum.TextXAlignment, size: number): TextLabel
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1
			t.Position = UDim2.new(0, x, 0, 0)
			t.Size = UDim2.new(0, w, 1, 0)
			t.Font = Enum.Font.FredokaOne
			t.TextSize = size
			t.TextScaled = false
			t.TextTruncate = Enum.TextTruncate.AtEnd
			t.Text = str
			t.TextColor3 = color
			t.TextXAlignment = align
			t.Parent = parent
			local st = Instance.new("UIStroke")
			st.Thickness = 2
			st.Color = TIMBER
			st.Parent = t
			return t
		end
		local back = Instance.new("Frame")
		back.Size = UDim2.fromScale(1, 1)
		back.BackgroundColor3 = Color3.fromRGB(34, 22, 14)
		back.BorderSizePixel = 0
		back.Parent = gui
		local header = Instance.new("Frame")
		header.Size = UDim2.new(1, -24, 0, 64)
		header.Position = UDim2.fromOffset(12, 10)
		header.BackgroundColor3 = Color3.fromRGB(150, 98, 56)
		header.BorderSizePixel = 0
		header.Parent = back
		local hc = Instance.new("UICorner")
		hc.CornerRadius = UDim.new(0, 14)
		hc.Parent = header
		local hs = Instance.new("UIStroke")
		hs.Thickness = 4
		hs.Color = TIMBER
		hs.Parent = header
		text(header, "DEEPEST DIVERS", 0, 536, Color3.fromRGB(255, 215, 60), Enum.TextXAlignment.Center, 40)
		for i = 1, 10 do
			local col = if i == 1 then Color3.fromRGB(255, 215, 60) elseif i == 2 then Color3.fromRGB(220, 230, 245) elseif i == 3 then Color3.fromRGB(240, 160, 90) else Color3.fromRGB(255, 255, 255)
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -24, 0, 42)
			row.Position = UDim2.fromOffset(12, 84 + (i - 1) * 46)
			row.BackgroundColor3 = if i % 2 == 0 then Color3.fromRGB(70, 46, 30) else Color3.fromRGB(86, 58, 38)
			row.BorderSizePixel = 0
			row.Parent = back
			local rc = Instance.new("UICorner")
			rc.CornerRadius = UDim.new(0, 8)
			rc.Parent = row
			text(row, tostring(i), 8, 44, col, Enum.TextXAlignment.Center, 28)
			local nameL = text(row, "", 58, 300, col, Enum.TextXAlignment.Left, 28)
			local depthL = text(row, "", 362, 164, col, Enum.TextXAlignment.Right, 26)
			rows[i] = rows[i] or {}
			table.insert(rows[i], { name = nameL, depth = depthL })
		end
	end
end

local function nameOf(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local n = if ok and name then name else ("Player " .. userId)
	nameCache[userId] = n
	return n
end

local function draw(entries: { { id: number, depth: number } })
	for i = 1, 10 do
		local e = entries[i]
		for _, l in rows[i] or {} do
			l.name.Text = if e then nameOf(e.id) else "---"
			l.depth.Text = if e then ("Depth " .. e.depth) else ""
		end
	end
end

local function refresh()
	-- push everyone here first
	if store then
		for _, p in Players:GetPlayers() do
			local data = DataService.get(p)
			if data and math.max(data.bestDepth, data.peakDepth or 0) > 0 and DataService.canSave(p) then
				pcall(function()
					(store :: OrderedDataStore):SetAsync(tostring(p.UserId), math.max(data.bestDepth, data.peakDepth or 0))
				end)
			end
		end
	end
	local entries = {}
	local ok = false
	if store then
		ok = pcall(function()
			local page = (store :: OrderedDataStore):GetSortedAsync(false, 10):GetCurrentPage()
			for _, item in page do
				table.insert(entries, { id = tonumber(item.key) :: number, depth = item.value })
			end
		end)
	end
	if not ok or #entries == 0 then
		-- this server only
		entries = {}
		for _, p in Players:GetPlayers() do
			local data = DataService.get(p)
			if data then
				nameCache[p.UserId] = p.DisplayName
				table.insert(entries, { id = p.UserId, depth = math.max(data.bestDepth, data.peakDepth or 0) })
			end
		end
		table.sort(entries, function(a, b)
			return a.depth > b.depth
		end)
	end
	draw(entries)
end

function LeaderboardService.init()
	buildBoard()
	task.spawn(function()
		task.wait(5)
		while true do
			refresh()
			task.wait(REFRESH)
		end
	end)
end

return LeaderboardService
