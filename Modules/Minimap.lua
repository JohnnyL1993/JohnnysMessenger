-- Minimap launcher button. Kept in the addon's own flat button style rather
-- than pulling in LibDBIcon, so it matches the rest of the black/white suite.
JM.Minimap = {}
local Minimap = JM.Minimap

local button
local RADIUS = 80

local function UpdatePosition()
	local angle = math.rad(JM.db.minimap.angle or 215)
	button:ClearAllPoints()
	button:SetPoint("CENTER", _G.Minimap, "CENTER", math.cos(angle) * RADIUS, math.sin(angle) * RADIUS)
end

local function OnDragUpdate(self)
	local mx, my = _G.Minimap:GetCenter()
	local px, py = GetCursorPosition()
	local scale = _G.Minimap:GetEffectiveScale()
	px, py = px / scale, py / scale
	JM.db.minimap.angle = math.deg(math.atan2(py - my, px - mx))
	UpdatePosition()
end

function Minimap:Init()
	if button then
		return
	end

	button = CreateFrame("Button", "JohnnysMessengerMinimapButton", _G.Minimap)
	button:SetSize(20, 20)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	JM.Skin:StyleButton(button)

	local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("CENTER")
	label:SetTextColor(1, 1, 1)
	label:SetText("M")

	button.badge = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.badge:SetPoint("BOTTOMRIGHT", 3, -3)
	button.badge:SetTextColor(1, 1, 1)

	button:RegisterForDrag("LeftButton")
	button:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", OnDragUpdate)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	button:SetScript("OnClick", function()
		JM.MainFrame:Toggle()
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Johnny's Messenger")
		GameTooltip:AddLine("Click to toggle | Drag to move", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	UpdatePosition()
	self:UpdateBadge()
end

function Minimap:UpdateBadge()
	if not button then
		return
	end
	local total = JM.Store:GetTotalUnread()
	if total > 0 then
		button.badge:SetText(total > 99 and "99+" or tostring(total))
	else
		button.badge:SetText("")
	end
end
