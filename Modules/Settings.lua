-- User-tunable options (JM.db.settings) and the in-window settings page that
-- replaces the conversation pane while it's open. Option set is a 3.3.5a-
-- friendly subset of WhisperMessenger's Behavior/General/Appearance tabs.
JM.Settings = {}
local Settings = JM.Settings
local Skin = JM.Skin

Settings.DEFAULTS = {
	autoOpen = true,
	hideFromChat = true,
	sound = true,
	hideInCombat = false,
	use24h = true,
	inactiveAlpha = 0.7,
	scale = 1.0,
	fontSize = 12,
	maxMessages = 200,
	retentionDays = 30,
	quickReplies = { "One sec", "On my way", "Sure!", "Sorry, busy right now - will reply soon" },
}

local MAX_QUICK_REPLIES = 6

-- Font object shared by every bubble/system line so a font-size change is
-- one SetFont call (plus a transcript re-render to re-measure bubbles).
local messageFont = CreateFont("JM_MessageFont")
messageFont:SetFontObject(GameFontHighlightSmall)

local function CopyDefault(v)
	if type(v) ~= "table" then
		return v
	end
	local copy = {}
	for k, inner in pairs(v) do
		copy[k] = CopyDefault(inner)
	end
	return copy
end

function Settings:Init()
	JM.db.settings = JM.db.settings or {}
	local s = JM.db.settings
	for k, v in pairs(self.DEFAULTS) do
		if s[k] == nil then
			s[k] = CopyDefault(v)
		end
	end
	self.db = s
	self:ApplyFont()
end

function Settings:Get(key)
	return self.db[key]
end

function Settings:Set(key, value)
	self.db[key] = value
	if key == "fontSize" then
		self:ApplyFont()
		JM.MainFrame:RefreshMessages()
	elseif key == "scale" or key == "inactiveAlpha" then
		JM.MainFrame:ApplyWindowSettings()
	end
	-- maxMessages/retentionDays deliberately don't prune here: dragging the
	-- slider down and back up would otherwise destroy history mid-drag. They
	-- take effect on the next login prune / next message added.
end

function Settings:ApplyFont()
	local path = GameFontHighlightSmall:GetFont()
	messageFont:SetFont(path, self.db.fontSize)
end

function Settings:ResetToDefaults()
	for k in pairs(self.db) do
		self.db[k] = nil
	end
	for k, v in pairs(self.DEFAULTS) do
		self.db[k] = CopyDefault(v)
	end
	self:ApplyFont()
	JM.MainFrame:ApplyWindowSettings()
	self:RefreshPage()
	JM.MainFrame:RefreshMessages()
	JM.MainFrame:RefreshList()
end

--------------------------------------
--          Settings page           --
--------------------------------------

local page, controls

local function SectionHeader(parent, text, y)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fs:SetPoint("TOPLEFT", 4, y)
	fs:SetTextColor(1, 1, 1)
	fs:SetText(text)
	local line = parent:CreateTexture(nil, "ARTWORK")
	line:SetTexture(Skin.WHITE)
	line:SetVertexColor(1, 1, 1, 0.1)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -4)
	line:SetPoint("RIGHT", parent, "RIGHT", -4, 0)
	return y - 26
end

local CHECKBOXES = {
	{ key = "autoOpen", label = "Open the window on incoming whispers (never in combat)" },
	{ key = "hideFromChat", label = "Hide whispers from the default chat frame" },
	{ key = "sound", label = "Play a sound on incoming whispers" },
	{ key = "hideInCombat", label = "Hide the window during combat" },
	{ key = "use24h", label = "24-hour timestamps" },
}

local function Percent(v)
	return math.floor(v * 100 + 0.5) .. "%"
end

local SLIDERS = {
	{ key = "inactiveAlpha", label = "Opacity when not in use", min = 0.3, max = 1.0, step = 0.05, format = Percent },
	{ key = "scale", label = "Window scale", min = 0.75, max = 1.5, step = 0.05, format = Percent },
	{ key = "fontSize", label = "Message font size", min = 10, max = 16, step = 1 },
	{ key = "maxMessages", label = "Messages kept per conversation", min = 50, max = 500, step = 10 },
	{ key = "retentionDays", label = "Keep history for (days)", min = 1, max = 60, step = 1 },
}

local function SaveQuickReplies()
	local list = {}
	for _, holder in ipairs(controls.quickReplies) do
		local text = holder.editBox:GetText()
		if text and string.match(text, "%S") then
			table.insert(list, text)
		end
	end
	Settings.db.quickReplies = list
end

function Settings:BuildPage(parent)
	page = CreateFrame("Frame", nil, parent)
	page:SetAllPoints()
	page:Hide()

	local scroll = CreateFrame("ScrollFrame", "JM_SettingsScroll", page, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 4, -4)
	scroll:SetPoint("BOTTOMRIGHT", -26, 4)

	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(300, 600)
	scroll:SetScrollChild(content)
	scroll:SetScript("OnSizeChanged", function(self, w)
		content:SetWidth(w)
	end)

	controls = { checkboxes = {}, sliders = {}, quickReplies = {} }
	local y = -4

	y = SectionHeader(content, "Behavior", y)
	for _, spec in ipairs(CHECKBOXES) do
		local cb = Skin:CreateCheckbox(content, spec.label, function(checked)
			Settings:Set(spec.key, checked)
			if spec.key == "use24h" then
				JM.MainFrame:RefreshMessages()
				JM.MainFrame:RefreshList()
			end
		end)
		cb:SetPoint("TOPLEFT", 6, y)
		controls.checkboxes[spec.key] = cb
		y = y - 22
	end

	y = SectionHeader(content, "Appearance & history", y - 10)
	for _, spec in ipairs(SLIDERS) do
		local s = Skin:CreateSlider(content, spec.label, spec.min, spec.max, spec.step, spec.format, function(value)
			Settings:Set(spec.key, value)
		end)
		s:SetPoint("TOPLEFT", 6, y)
		s:SetWidth(240)
		controls.sliders[spec.key] = s
		y = y - 42
	end

	y = SectionHeader(content, "Quick replies", y - 10)
	for i = 1, MAX_QUICK_REPLIES do
		local holder = Skin:CreateEditBox(content, 260, 22)
		holder:SetPoint("TOPLEFT", 6, y)
		holder.placeholder:SetText("Quick reply " .. i)
		holder.editBox:HookScript("OnTextChanged", function(self, userInput)
			if userInput then
				SaveQuickReplies()
			end
		end)
		holder.editBox:SetScript("OnEnterPressed", holder.editBox.ClearFocus)
		controls.quickReplies[i] = holder
		y = y - 26
	end

	local reset = Skin:CreateButton(content, 120, 22, "Reset to defaults")
	reset:SetPoint("TOPLEFT", 6, y - 14)
	reset:SetScript("OnClick", function()
		Settings:ResetToDefaults()
	end)
	y = y - 50

	content:SetHeight(-y)
	page:SetScript("OnShow", function()
		Settings:RefreshPage()
	end)
	return page
end

function Settings:RefreshPage()
	if not page then
		return
	end
	for key, cb in pairs(controls.checkboxes) do
		cb:SetChecked(self.db[key] and true or false)
	end
	for key, s in pairs(controls.sliders) do
		s:SetValue(self.db[key])
	end
	for i, holder in ipairs(controls.quickReplies) do
		holder.editBox:SetText(self.db.quickReplies[i] or "")
		holder.UpdatePlaceholder()
	end
end
