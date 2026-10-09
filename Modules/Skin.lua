-- Flat black/white "modern" skin, ported from JohnnysAddonHub's Modules\Skin.lua
-- so this addon looks like part of the same suite. Tinted flat textures plus
-- one white circle for rounded corners; no external skinning library.
JM.Skin = {}
local Skin = JM.Skin

Skin.WHITE = "Interface\\Buttons\\WHITE8X8"
Skin.CIRCLE = "Interface\\AddOns\\JohnnysMessenger\\Media\\Circle"

local function RoundedSetColor(bg, r, g, b, a)
	for _, tex in ipairs(bg.textures) do
		tex:SetVertexColor(r, g, b, a)
	end
end

-- A rounded-rectangle background (3.3.5a has no corner masks): the four
-- quarters of Media\Circle as corners, plus three flat strips filling the
-- rest. Pieces never overlap, so a translucent color stays even. The frame
-- must be at least 2 * radius in each direction. Tint with bg:SetColor().
function Skin:CreateRoundedBackground(frame, radius, layer)
	layer = layer or "BACKGROUND"
	local function Piece(file)
		local tex = frame:CreateTexture(nil, layer)
		tex:SetTexture(file)
		return tex
	end

	local textures = {}
	local tl, tr, bl, br = Piece(), Piece(), Piece(), Piece()
	-- SetTexture returns nil when the file can't be loaded - e.g. the client
	-- was only /reloaded after the addon gained Media\Circle.tga, since WoW
	-- only sees new files after a restart.
	local haveCircle = tl:SetTexture(self.CIRCLE)
	for _, corner in ipairs({ tl, tr, bl, br }) do
		corner:SetSize(radius, radius)
		if haveCircle then
			corner:SetTexture(self.CIRCLE)
			table.insert(textures, corner)
		else
			corner:SetTexture(nil)
		end
	end
	tl:SetTexCoord(0, 0.5, 0, 0.5)
	tr:SetTexCoord(0.5, 1, 0, 0.5)
	bl:SetTexCoord(0, 0.5, 0.5, 1)
	br:SetTexCoord(0.5, 1, 0.5, 1)
	tl:SetPoint("TOPLEFT")
	tr:SetPoint("TOPRIGHT")
	bl:SetPoint("BOTTOMLEFT")
	br:SetPoint("BOTTOMRIGHT")

	if not haveCircle then
		-- Fallback: draw each corner's quarter circle as 1px-tall rows.
		for k = 0, radius - 1 do
			local dy = radius - k - 0.5
			local w = math.floor(math.sqrt(radius * radius - dy * dy) + 0.5)
			if w > 0 then
				for _, c in ipairs({ { tl, "TOPRIGHT", -k }, { tr, "TOPLEFT", -k }, { bl, "BOTTOMRIGHT", k }, { br, "BOTTOMLEFT", k } }) do
					local row = Piece(self.WHITE)
					row:SetSize(w, 1)
					row:SetPoint(c[2], c[1], c[2], 0, c[3])
					table.insert(textures, row)
				end
			end
		end
	end

	local top, bottom, middle = Piece(self.WHITE), Piece(self.WHITE), Piece(self.WHITE)
	top:SetPoint("TOPLEFT", tl, "TOPRIGHT")
	top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
	bottom:SetPoint("TOPLEFT", bl, "TOPRIGHT")
	bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
	middle:SetPoint("TOPLEFT", tl, "BOTTOMLEFT")
	middle:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
	table.insert(textures, top)
	table.insert(textures, bottom)
	table.insert(textures, middle)

	return { textures = textures, SetColor = RoundedSetColor }
end

function Skin:StylePanel(frame, alpha)
	frame:SetBackdrop({ bgFile = self.WHITE, edgeFile = self.WHITE, edgeSize = 1 })
	frame:SetBackdropColor(0.03, 0.03, 0.03, alpha or 0.92)
	frame:SetBackdropBorderColor(0.180, 0.224, 0.243, 1)
end

function Skin:StyleButton(btn)
	btn:SetBackdrop({ bgFile = self.WHITE, edgeFile = self.WHITE, edgeSize = 1 })
	btn:SetBackdropColor(0.090, 0.114, 0.125, 0.95)
	btn:SetBackdropBorderColor(0.243, 0.298, 0.322, 1)

	local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetTexture(self.WHITE)
	highlight:SetVertexColor(0.725, 0.886, 0.290, 0.14)
	btn:SetHighlightTexture(highlight)

	btn:SetScript("OnMouseDown", function(self)
		if self:IsEnabled() then
			self:SetBackdropColor(0.160, 0.200, 0.220, 0.95)
		end
	end)
	btn:SetScript("OnMouseUp", function(self)
		self:SetBackdropColor(0.090, 0.114, 0.125, 0.95)
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

	-- Grey hint text shown only while the box is empty and unfocused.
	local placeholder = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	placeholder:SetPoint("LEFT", 6, 0)
	placeholder:SetPoint("RIGHT", -6, 0)
	placeholder:SetJustifyH("LEFT")
	placeholder:SetTextColor(0.45, 0.45, 0.45)
	holder.placeholder = placeholder

	local function UpdatePlaceholder()
		if edit:HasFocus() or (edit:GetText() or "") ~= "" then
			placeholder:Hide()
		else
			placeholder:Show()
		end
	end
	holder.UpdatePlaceholder = UpdatePlaceholder
	edit:HookScript("OnEditFocusGained", UpdatePlaceholder)
	edit:HookScript("OnEditFocusLost", UpdatePlaceholder)
	edit:HookScript("OnTextChanged", UpdatePlaceholder)

	return holder
end

-- Flat checkbox: a bordered square that fills white when checked, with a
-- label to its right. onChange(checked) fires on user clicks only.
function Skin:CreateCheckbox(parent, label, onChange)
	local cb = CreateFrame("CheckButton", nil, parent)
	cb:SetSize(14, 14)
	cb:SetBackdrop({ bgFile = self.WHITE, edgeFile = self.WHITE, edgeSize = 1 })
	cb:SetBackdropColor(0.090, 0.114, 0.125, 0.95)
	cb:SetBackdropBorderColor(0.243, 0.298, 0.322, 1)

	local check = cb:CreateTexture(nil, "ARTWORK")
	check:SetTexture(self.WHITE)
	check:SetPoint("TOPLEFT", 3, -3)
	check:SetPoint("BOTTOMRIGHT", -3, 3)
	check:SetVertexColor(0.725, 0.886, 0.290, 1)
	cb:SetCheckedTexture(check)

	local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("LEFT", cb, "RIGHT", 8, 0)
	fs:SetText(label)
	cb.label = fs
	-- Let the label be clickable too.
	cb:SetHitRectInsets(0, -(fs:GetStringWidth() + 8), 0, 0)

	cb:SetScript("OnClick", function(self)
		if onChange then
			onChange(self:GetChecked() and true or false)
		end
	end)
	return cb
end

-- Flat horizontal slider with a label above-left and the value above-right.
-- format(value) -> display string; onChange(value) fires as it moves.
function Skin:CreateSlider(parent, label, minV, maxV, step, format, onChange)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(220, 34)

	local fs = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", 0, 0)
	fs:SetText(label)

	local valueText = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	valueText:SetPoint("TOPRIGHT", 0, 0)
	valueText:SetTextColor(0.7, 0.7, 0.7)

	local slider = CreateFrame("Slider", nil, holder)
	slider:SetPoint("TOPLEFT", 0, -16)
	slider:SetPoint("TOPRIGHT", 0, -16)
	slider:SetHeight(12)
	slider:SetOrientation("HORIZONTAL")
	slider:SetBackdrop({ bgFile = self.WHITE, edgeFile = self.WHITE, edgeSize = 1 })
	slider:SetBackdropColor(0.090, 0.114, 0.125, 0.95)
	slider:SetBackdropBorderColor(0.243, 0.298, 0.322, 1)
	slider:SetThumbTexture(self.WHITE)
	local thumb = slider:GetThumbTexture()
	thumb:SetSize(8, 12)
	thumb:SetVertexColor(0.725, 0.886, 0.290, 1)
	slider:SetMinMaxValues(minV, maxV)
	slider:SetValueStep(step)
	slider:EnableMouseWheel(false)

	local function Round(v)
		return math.floor(v / step + 0.5) * step
	end

	slider:SetScript("OnValueChanged", function(self, value)
		value = Round(value)
		valueText:SetText(format and format(value) or tostring(value))
		if holder.ready and onChange then
			onChange(value)
		end
	end)

	function holder:SetValue(value)
		holder.ready = false
		slider:SetValue(value)
		valueText:SetText(format and format(Round(value)) or tostring(value))
		holder.ready = true
	end

	holder.slider = slider
	return holder
end

-- Small white count badge (black text on white), used for unread counts.
function Skin:CreateBadge(parent)
	local badge = CreateFrame("Frame", nil, parent)
	badge:SetSize(16, 14)
	badge:SetBackdrop({ bgFile = self.WHITE })
	badge:SetBackdropColor(0.725, 0.886, 0.290, 1)
	local fs = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("CENTER", 0, 0)
	fs:SetTextColor(0, 0, 0)
	badge.text = fs

	function badge:SetCount(n)
		if not n or n <= 0 then
			self:Hide()
			return
		end
		fs:SetText(n > 99 and "99+" or tostring(n))
		self:SetWidth(math.max(16, fs:GetStringWidth() + 8))
		self:Show()
	end
	badge:Hide()
	return badge
end

-- Small square presence dot. Colors mirror WhisperMessenger's status palette.
Skin.STATUS_COLORS = {
	online = { 0.30, 0.82, 0.40 },
	afk = { 0.90, 0.72, 0.20 },
	dnd = { 0.85, 0.25, 0.25 },
	offline = { 0.45, 0.45, 0.50 },
}

function Skin:CreateStatusDot(parent, size)
	local dot = CreateFrame("Frame", nil, parent)
	dot:SetSize(size or 8, size or 8)
	dot:SetBackdrop({ bgFile = self.WHITE, edgeFile = self.WHITE, edgeSize = 1 })
	dot:SetBackdropBorderColor(0, 0, 0, 1)

	function dot:SetStatus(status)
		local c = status and Skin.STATUS_COLORS[status]
		if not c then
			self:Hide()
			return
		end
		self:SetBackdropColor(c[1], c[2], c[3], 1)
		self:Show()
	end
	dot:Hide()
	return dot
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
		row:SetBackdropColor(0.122, 0.153, 0.169, 0.9)
	elseif row.pinned then
		row:SetBackdropColor(1, 1, 1, 0.05)
	else
		row:SetBackdropColor(0, 0, 0, 0)
	end
	if row.selectBar then
		if selected then
			row.selectBar:Show()
		else
			row.selectBar:Hide()
		end
	end
end
