----------------------------------------------------------
-- Gatherer Reforged - Route & Session Tracker Window
----------------------------------------------------------

local Gatherer = _G.Gatherer
if not Gatherer then return end

Gatherer.RouteSessionUI = Gatherer.RouteSessionUI or {}
local UI = Gatherer.RouteSessionUI

local frame
local selectedType = "ALL"

local function formatDuration(secs)
	secs = math.max(0, math.floor(secs or 0))
	local h = math.floor(secs / 3600)
	local m = math.floor((secs % 3600) / 60)
	local s = secs % 60
	if h > 0 then
		return string.format("%dh %02dm %02ds", h, m, s)
	end
	return string.format("%02dm %02ds", m, s)
end

local function ensureFrame()
	if frame then return frame end

	local f = CreateFrame("Frame", "GathererRouteSessionFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	f:SetSize(440, 380)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	tinsert(UISpecialFrames, "GathererRouteSessionFrame")

	if f.SetBackdrop then
		f:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = "Interface\\Buttons\\WHITE8x8",
			edgeSize = 1,
		})
		f:SetBackdropColor(0.08, 0.09, 0.12, 0.96)
		f:SetBackdropBorderColor(0.79, 0.64, 0.15, 0.9)
	end

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
	title:SetText("|cffffd100Gatherer Reforged — Routes & Session|r")

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)

	-- Route Type Buttons
	f._typeBtns = {}
	local types = {
		{ key = "ALL", label = "All" },
		{ key = "MINE", label = "Mining" },
		{ key = "HERB", label = "Herbs" },
		{ key = "OPEN", label = "Fishing/Chest" },
	}
	local prev
	for _, t in ipairs(types) do
		local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		b:SetSize(96, 22)
		if prev then
			b:SetPoint("LEFT", prev, "RIGHT", 4, 0)
		else
			b:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -34)
		end
		b:SetText(t.label)
		b:SetScript("OnClick", function()
			selectedType = t.key
			UI.Refresh()
		end)
		f._typeBtns[t.key] = b
		prev = b
	end

	local buildBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	buildBtn:SetSize(130, 24)
	buildBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -62)
	buildBtn:SetText("Build Zone Route")
	buildBtn:SetScript("OnClick", function()
		if Gatherer.Routes then
			local route, err = Gatherer.Routes.BuildZoneRoute(selectedType)
			if not route then
				Gatherer.Util.ChatPrint("Route: " .. tostring(err or "No nodes in current zone"))
			else
				Gatherer.Util.ChatPrint(string.format("Route built for %s (%d nodes).", route.zoneName, #route.points))
			end
			UI.Refresh()
		end
	end)

	local wpBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	wpBtn:SetSize(130, 24)
	wpBtn:SetPoint("LEFT", buildBtn, "RIGHT", 6, 0)
	wpBtn:SetText("Next Waypoint")
	wpBtn:SetScript("OnClick", function()
		if Gatherer.Routes then
			Gatherer.Routes.SetNextWaypoint()
			UI.Refresh()
		end
	end)

	local clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	clearBtn:SetSize(130, 24)
	clearBtn:SetPoint("LEFT", wpBtn, "RIGHT", 6, 0)
	clearBtn:SetText("Clear Route")
	clearBtn:SetScript("OnClick", function()
		if Gatherer.Routes then
			Gatherer.Routes.ClearRoute()
			UI.Refresh()
		end
	end)

	local routeStatus = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	routeStatus:SetPoint("TOPLEFT", buildBtn, "BOTTOMLEFT", 0, -8)
	routeStatus:SetTextColor(0.85, 0.85, 0.85)
	f._routeStatus = routeStatus

	local sessHdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	sessHdr:SetPoint("TOPLEFT", routeStatus, "BOTTOMLEFT", 0, -14)
	sessHdr:SetText("|cffffd100Gathering Session|r")

	local resetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	resetBtn:SetSize(100, 22)
	resetBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -110)
	resetBtn:SetText("Reset Session")
	resetBtn:SetScript("OnClick", function()
		if Gatherer.Session then
			Gatherer.Session.Reset()
			UI.Refresh()
		end
	end)

	local sessSummary = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sessSummary:SetPoint("TOPLEFT", sessHdr, "BOTTOMLEFT", 0, -6)
	sessSummary:SetTextColor(0.85, 0.95, 0.85)
	f._sessSummary = sessSummary

	local itemList = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	itemList:SetPoint("TOPLEFT", sessSummary, "BOTTOMLEFT", 0, -8)
	itemList:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
	itemList:SetJustifyH("LEFT")
	itemList:SetJustifyV("TOP")
	f._itemList = itemList

	frame = f
	return f
end

function UI.Refresh()
	local f = ensureFrame()
	for k, b in pairs(f._typeBtns) do
		b:SetAlpha(k == selectedType and 1.0 or 0.65)
	end

	local route = Gatherer.Routes and Gatherer.Routes.activeRoute
	if route and route.points then
		f._routeStatus:SetText(string.format("Active: %s (%s) — %d nodes (next #%d)",
			route.zoneName, route.gatherType, #route.points, route.cursor or 1))
	else
		f._routeStatus:SetText("No active route. Click 'Build Zone Route' in any zone with nodes.")
	end

	local s = Gatherer.Session and Gatherer.Session.data
	if s then
		local elapsed = math.max(1, time() - (s.startedAt or time()))
		local perHr = math.floor((s.total or 0) * 3600 / elapsed + 0.5)
		f._sessSummary:SetText(string.format("Time: %s  |  Nodes: %d (%d/hr)  |  Mine: %d  Herb: %d  Open: %d",
			formatDuration(elapsed), s.total or 0, perHr,
			s.byType.MINE or 0, s.byType.HERB or 0, s.byType.OPEN or 0))

		local sorted = {}
		for _, rec in pairs(s.items or {}) do
			table.insert(sorted, rec)
		end
		table.sort(sorted, function(a, b)
			if a.count ~= b.count then return a.count > b.count end
			return (a.name or "") < (b.name or "")
		end)
		local lines = {}
		for i = 1, math.min(12, #sorted) do
			lines[#lines + 1] = string.format("• %s x%d", sorted[i].name, sorted[i].count)
		end
		f._itemList:SetText(#lines > 0 and table.concat(lines, "\n") or "|cff888888No items gathered yet this session.|r")
	end
end

function UI.RefreshIfShown()
	if frame and frame:IsShown() then
		UI.Refresh()
	end
end

function UI.Toggle()
	local f = ensureFrame()
	if f:IsShown() then
		f:Hide()
	else
		UI.Refresh()
		f:Show()
	end
end
