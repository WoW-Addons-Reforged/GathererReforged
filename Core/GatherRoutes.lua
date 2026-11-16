----------------------------------------------------------
-- Gatherer Reforged - Farm Route Solver & Session Tracker
----------------------------------------------------------

local Gatherer = _G.Gatherer
if not Gatherer then return end

Gatherer.Routes = Gatherer.Routes or {}
Gatherer.Session = Gatherer.Session or {}

local Routes = Gatherer.Routes
local Session = Gatherer.Session

Routes.activeRoute = nil
local routeLines = {}
local worldMapHooked = false

local function distSq(a, b)
	local dx = (a.x or 0) - (b.x or 0)
	local dy = (a.y or 0) - (b.y or 0)
	return dx * dx + dy * dy
end

local function solveNearestNeighbor(pts, startX, startY)
	local n = #pts
	if n <= 2 then return pts end
	local used = {}
	local order = {}
	local cx, cy = startX or pts[1].x, startY or pts[1].y

	for _ = 1, n do
		local bestIdx, bestD
		for i = 1, n do
			if not used[i] then
				local dx = pts[i].x - cx
				local dy = pts[i].y - cy
				local d = dx * dx + dy * dy
				if not bestD or d < bestD then
					bestD = d
					bestIdx = i
				end
			end
		end
		if bestIdx then
			used[bestIdx] = true
			table.insert(order, pts[bestIdx])
			cx, cy = pts[bestIdx].x, pts[bestIdx].y
		end
	end
	return order
end

local function twoOpt(pts)
	local n = #pts
	if n < 4 then return pts end
	local improved = true
	local passes = 0
	while improved and passes < 20 do
		improved = false
		passes = passes + 1
		for i = 1, n - 2 do
			for j = i + 2, n do
				local a = pts[i]
				local b = pts[i + 1]
				local c = pts[j]
				local d = pts[(j % n) + 1]
				if (distSq(a, b) + distSq(c, d)) > (distSq(a, c) + distSq(b, d)) then
					local l, r = i + 1, j
					while l < r do
						pts[l], pts[r] = pts[r], pts[l]
						l = l + 1
						r = r - 1
					end
					improved = true
				end
			end
		end
	end
	return pts
end

local function hideRouteLines()
	for _, line in ipairs(routeLines) do
		line:Hide()
	end
end

function Routes.DrawWorldMapRoute()
	hideRouteLines()
	local route = Routes.activeRoute
	if not route or not route.points or #route.points < 2 then return end
	if not _G.WorldMapFrame or not _G.WorldMapFrame:IsShown() then return end

	local canvas = _G.WorldMapFrame.GetCanvas and _G.WorldMapFrame:GetCanvas()
	local mapID = _G.WorldMapFrame.GetMapID and _G.WorldMapFrame:GetMapID()
	if not canvas or not mapID or mapID ~= route.mapID then return end

	local cw, ch = canvas:GetWidth(), canvas:GetHeight()
	if not cw or cw <= 0 or not ch or ch <= 0 then return end

	local pts = route.points
	local n = #pts
	for i = 1, n do
		local p1 = pts[i]
		local p2 = pts[(i % n) + 1]
		local line = routeLines[i]
		if not line then
			line = canvas:CreateLine(nil, "OVERLAY")
			line:SetThickness(2.2)
			line:SetColorTexture(1.0, 0.82, 0.15, 0.85)
			routeLines[i] = line
		end
		line:ClearAllPoints()
		line:SetStartPoint("TOPLEFT", canvas, p1.x * cw, -p1.y * ch)
		line:SetEndPoint("TOPLEFT", canvas, p2.x * cw, -p2.y * ch)
		line:Show()
	end
end

local function ensureWorldMapHook()
	if worldMapHooked or not _G.WorldMapFrame then return end
	worldMapHooked = true
	if _G.WorldMapFrame.HookScript then
		_G.WorldMapFrame:HookScript("OnShow", Routes.DrawWorldMapRoute)
	end
	if _G.WorldMapFrame.SetMapID then
		hooksecurefunc(_G.WorldMapFrame, "SetMapID", Routes.DrawWorldMapRoute)
	end
end

function Routes.BuildZoneRoute(gatherType, maxNodes)
	if not Gatherer.Util or not Gatherer.Util.GetPositionInCurrentZone or not Gatherer.Storage then
		return nil, "NO_ZONE"
	end
	local zToken, px, py = Gatherer.Util.GetPositionInCurrentZone()
	if not zToken then return nil, "NO_ZONE" end

	local typesToScan = (gatherType and gatherType ~= "ALL") and { gatherType } or { "MINE", "HERB", "OPEN" }
	local pts = {}
	local limit = maxNodes or 80

	for _, gType in ipairs(typesToScan) do
		if Gatherer.Storage.ZoneGatherNodes then
			for _, xPos, yPos in Gatherer.Storage.ZoneGatherNodes(zToken, gType) do
				if xPos and yPos then
					table.insert(pts, { x = xPos, y = yPos, gType = gType })
					if #pts >= limit then break end
				end
			end
		end
		if #pts >= limit then break end
	end

	if #pts < 2 then
		return nil, "TOO_FEW_NODES"
	end

	pts = solveNearestNeighbor(pts, px, py)
	pts = twoOpt(pts)

	local mapID = (Gatherer.ZoneTokens and Gatherer.ZoneTokens.GetZoneMapID and Gatherer.ZoneTokens.GetZoneMapID(zToken))
		or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
	local mapInfo = mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)

	Routes.activeRoute = {
		zoneToken = zToken,
		zoneName = mapInfo and mapInfo.name or tostring(zToken),
		mapID = mapID,
		gatherType = gatherType or "ALL",
		points = pts,
		cursor = 1,
	}

	ensureWorldMapHook()
	Routes.DrawWorldMapRoute()
	return Routes.activeRoute
end

function Routes.ClearRoute()
	Routes.activeRoute = nil
	hideRouteLines()
end

function Routes.SetNextWaypoint()
	local route = Routes.activeRoute
	if not route or not route.points or #route.points == 0 or not route.mapID then
		return false
	end
	local idx = route.cursor or 1
	if idx > #route.points then idx = 1 end
	local pt = route.points[idx]
	route.cursor = (idx % #route.points) + 1

	local title = string.format("Gatherer Route (%d/%d)", idx, #route.points)
	if _G.TomTom and _G.TomTom.AddWaypoint then
		_G.TomTom:AddWaypoint(route.mapID, pt.x, pt.y, {
			title = title,
			persistent = false,
			minimap = true,
			world = true,
		})
		return true
	elseif C_Map and C_Map.SetUserWaypoint and UiMapPoint then
		C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(route.mapID, pt.x, pt.y))
		if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
			C_SuperTrack.SetSuperTrackedUserWaypoint(true)
		end
		return true
	end
	return false
end

-- =========================================================
-- Gathering Session Tracker
-- =========================================================
Session.data = Session.data or {
	active = true,
	startedAt = time(),
	total = 0,
	byType = {},
	items = {},
}

function Session.Reset()
	Session.data.startedAt = time()
	Session.data.total = 0
	Session.data.byType = {}
	Session.data.items = {}
end

function Session.Record(gatherType, lootTable, wasGathered)
	if not Session.data.active or not wasGathered then return end
	Session.data.total = (Session.data.total or 0) + 1
	if gatherType then
		Session.data.byType[gatherType] = (Session.data.byType[gatherType] or 0) + 1
	end
	if type(lootTable) == "table" then
		for _, entry in ipairs(lootTable) do
			local itemID = entry and entry.id
			local count = entry and tonumber(entry.count) or 1
			if itemID then
				local rec = Session.data.items[itemID]
				if not rec then
					local name = (C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(itemID)) or ("Item #" .. tostring(itemID))
					rec = { id = itemID, name = name, count = 0 }
					Session.data.items[itemID] = rec
				end
				rec.count = rec.count + count
			end
		end
	end
	if Gatherer.RouteSessionUI and Gatherer.RouteSessionUI.RefreshIfShown then
		Gatherer.RouteSessionUI.RefreshIfShown()
	end
end

if Gatherer.Api and Gatherer.Api.AddGather then
	hooksecurefunc(Gatherer.Api, "AddGather", function(_, gatherType, _, _, _, gatherLoot, wasGathered)
		Session.Record(gatherType, gatherLoot, wasGathered)
	end)
end
