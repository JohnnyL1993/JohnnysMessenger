-- Flat black/white "modern" skin, ported from JohnnysAddonHub's Modules\Skin.lua
-- so this addon looks like part of the same suite. Single tinted 1x1 texture,
-- no custom art or external skinning library.
JM.Skin = {}
local Skin = JM.Skin

Skin.WHITE = "Interface\\Buttons\\WHITE8X8"

function Skin:StylePanel(frame, alpha)
	frame:SetBackdrop({ bgFile = self.WHITE, edgeFile = self.WHITE, edgeSize = 1 })
	frame:SetBackdropColor(0.03, 0.03, 0.03, alpha or 0.92)
	frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
end

function Skin:StyleButton(btn)
	btn:SetBackdrop({ bgFile = self.WHITE, edgeFile = self.WHITE, edgeSize = 1 })
	btn:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
	btn:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

	local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetTexture(self.WHITE)
	highlight:SetVertexColor(1, 1, 1, 0.12)
	btn:SetHighlightTexture(highlight)

	btn:SetScript("OnMouseDown", function(self)
		if self:IsEnabled() then
			self:SetBackdropColor(0.18, 0.18, 0.18, 0.95)
		end
	end)
	btn:SetScript("OnMouseUp", function(self)
		self:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
	end)
end

function Skin:CreateButton(parent, width, height, text, template)
	local btn = CreateFrame("Button", nil, parent, template)
	btn:SetSize(width, height)
	self:StyleButton(btn)

	local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("CENTER")
	fs:SetTextColor(1, 1, 1)
	if text then
		fs:SetText(text)
	end
	btn.text = fs

	return btn
end

-- A flat-skinned text entry: a StylePanel'd holder frame containing a plain
-- EditBox with no Blizzard InputBoxTemplate border art. Returns the holder;
-- the actual EditBox is at holder.editBox.
function Skin:CreateEditBox(parent, width, height)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(width, height)
	self:StylePanel(holder, 0.95)

	local edit = CreateFrame("EditBox", nil, holder)
	edit:SetPoint("LEFT", 4, 0)
	edit:SetPoint("RIGHT", -4, 0)
	edit:SetHeight(height)
	edit:SetAutoFocus(false)
	edit:SetFontObject(GameFontHighlightSmall)
	edit:SetTextColor(1, 1, 1)
	edit:SetScript("OnEscapePressed", edit.ClearFocus)
	holder.editBox = edit

	return holder
end

-- A pooled list row (contact list entries). Idle rows are transparent; a
-- selected row lightens to match the rest of the addon suite's selection
-- color. Only sets up the backdrop/highlight once per row (rowStyled flag)
-- since rows get recycled and restyled on every list refresh.
function Skin:StyleRow(row, selected)
	if not row.rowStyled then
		row:SetBackdrop({ bgFile = self.WHITE })
		local highlight = row:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetTexture(self.WHITE)
		highlight:SetVertexColor(1, 1, 1, 0.08)
		row.rowStyled = true
	end
	if selected then
		row:SetBackdropColor(0.2, 0.2, 0.2, 0.9)
	else
		row:SetBackdropColor(0, 0, 0, 0)
	end
end
