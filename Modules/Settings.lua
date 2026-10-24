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
	-- Flash WoW's taskbar button on a whisper while alt-tabbed (if the client can).
	flashTaskbar = true,
	-- The whisper sound is skipped while the window is open unless this is on.
	soundWhenOpen = false,
	-- "default" (game whisper), "chime", or "lsm:<LibSharedMedia name>".
	soundName = "default",
	-- Whispering someone from the chat box (/w, /r) opens their conversation.
	openOnSend = true,
	-- Stay in the reply box after sending; Esc or a click outside leaves it.
	keepFocus = true,
	-- Conversations open on today's messages; older ones sit behind a
	-- "History" bar at the top of the thread.
	todayOnly = true,
	hideInCombat = false,
	-- With hideInCombat on, don't hide if you're typing in the reply box.
	stayWhileTyping = true,
	use24h = true,
	inactiveAlpha = 0.7,
	scale = 1.0,
	fontSize = 12,
	maxMessages = 200,
	retentionDays = 30,
	quickReplies = { "One sec", "On my way", "Sure!", "Sorry, busy right now - will reply soon" },
}

local MAX_QUICK_REPLIES = 30 -- generous cap so the settings page stays usable

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

StaticPopupDialogs["JM_DELETE_BEFORE_TODAY"] = {
	text = "Delete every message from before today, in all conversations?\n\nThis can't be undone.",
	button1 = "Delete",
	button2 = CANCEL or "Cancel",
	OnAccept = function()
		local removed = JM.Store:DeleteBeforeToday()
		JM.Minimap:UpdateBadge()
		JM.MainFrame:RefreshList()
		JM.MainFrame:RefreshMessages()
		DEFAULT_CHAT_FRAME:AddMessage("|cffb9e24aMessenger:|r deleted " .. removed .. " older message" .. (removed == 1 and "" or "s") .. ".")
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
	showAlert = 1,
}

-- The game can't open a web page, so this shows the GitHub issues address
-- ready to copy.
local ISSUES_URL = "https://github.com/JohnnyL1993/JohnnysMessenger/issues"
StaticPopupDialogs["JM_ISSUES"] = {
	text = "Report a bug or request a change on GitHub.\nCtrl+C copies the address below.",
	button1 = CLOSE or "Close",
	hasEditBox = 1,
	hasWideEditBox = 1,
	OnShow = function(self)
		local box = self.wideEditBox or self.editBox or _G[self:GetName() .. "WideEditBox"]
		if box then
			box:SetText(ISSUES_URL)
			box:SetFocus()
			box:HighlightText()
		end
	end,
	EditBoxOnTextChanged = function(self)
		if self:GetText() ~= ISSUES_URL then
			self:SetText(ISSUES_URL)
			self:HighlightText()
		end
	end,
	EditBoxOnEnterPressed = function(self)
		self:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function(self)
		self:GetParent():Hide()
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

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
	{ key = "openOnSend", label = "Open the conversation when I whisper from chat (/w, /r)" },
	{ key = "sound", label = "Play a sound on incoming whispers" },
	{ key = "soundWhenOpen", label = "...even while the window is open" },
	{ key = "keepFocus", label = "Keep typing after sending (Esc or click outside to stop)" },
	{ key = "hideInCombat", label = "Hide the window during combat" },
	{ key = "stayWhileTyping", label = "...but not while I'm typing a reply" },
	{ key = "use24h", label = "24-hour timestamps" },
	{ key = "todayOnly", label = "Show only today's messages (older ones under History)" },
}

-- Only offered on clients that can actually flash the taskbar.
if FlashClientIcon then
	table.insert(CHECKBOXES, { key = "flashTaskbar", label = "Flash WoW on the taskbar for whispers while alt-tabbed" })
end

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

-- Quick reply rows are created on demand; qrCount is how many are in use.
local qrBox, qrAddBtn, qrContent, qrTop, tailHeight
local qrCount = 0
local ROW_STEP = 26

local function SaveQuickReplies()
	local list = {}
	for i = 1, qrCount do
		local text = controls.quickReplies[i].editBox:GetText()
		if text and string.match(text, "%S") then
			table.insert(list, text)
		end
	end
	Settings.db.quickReplies = list
end

local function LayoutQuickReplies()
	for i, holder in ipairs(controls.quickReplies) do
		if i <= qrCount then
			holder:Show()
		else
			holder:Hide()
		end
	end
	qrAddBtn:ClearAllPoints()
	qrAddBtn:SetPoint("TOPLEFT", 6, -(qrCount * ROW_STEP))
	if qrCount >= MAX_QUICK_REPLIES then
		qrAddBtn:Hide()
	else
		qrAddBtn:Show()
	end
	local boxHeight = qrCount * ROW_STEP + ROW_STEP
	qrBox:SetHeight(boxHeight)
	qrContent:SetHeight(-qrTop + boxHeight + tailHeight)
end

local RemoveQuickReply

local function GetQuickReplyRow(i)
	local holder = controls.quickReplies[i]
	if holder then
		return holder
	end
	holder = Skin:CreateEditBox(qrBox, 260, 22)
	holder:SetPoint("TOPLEFT", 6, -((i - 1) * ROW_STEP))
	holder.placeholder:SetText("Type a quick reply")
	holder.editBox:HookScript("OnTextChanged", function(self, userInput)
		if userInput then
			SaveQuickReplies()
		end
	end)
	holder.editBox:SetScript("OnEnterPressed", holder.editBox.ClearFocus)
	local remove = Skin:CreateButton(holder, 22, 22, "X")
	remove:SetPoint("LEFT", holder, "RIGHT", 4, 0)
	remove:SetScript("OnClick", function()
		RemoveQuickReply(i)
	end)
	holder.removeBtn = remove
	controls.quickReplies[i] = holder
	return holder
end

local function SetQuickReplyTexts(texts)
	qrCount = math.max(#texts, 1)
	for i = 1, qrCount do
		local holder = GetQuickReplyRow(i)
		holder.editBox:SetText(texts[i] or "")
		holder.UpdatePlaceholder()
	end
	LayoutQuickReplies()
end

RemoveQuickReply = function(index)
	local texts = {}
	for i = 1, qrCount do
		if i ~= index then
			table.insert(texts, controls.quickReplies[i].editBox:GetText() or "")
		end
	end
	for i = 1, qrCount do
		controls.quickReplies[i].editBox:ClearFocus()
	end
	SetQuickReplyTexts(texts)
	SaveQuickReplies()
end

local function AddQuickReply()
	if qrCount >= MAX_QUICK_REPLIES then
		return
	end
	qrCount = qrCount + 1
	local holder = GetQuickReplyRow(qrCount)
	holder.editBox:SetText("")
	holder.UpdatePlaceholder()
	LayoutQuickReplies()
	holder.editBox:SetFocus()
end

function Settings:BuildPage(parent)
	page = CreateFrame("Frame", nil, parent)
	page:SetAllPoints()
	page:Hide()

	local scroll = CreateFrame("ScrollFrame", "JM_SettingsScroll", page, "UIPanelScrollFrameTemplate")
	JM.Skin:StyleScrollBar(scroll)
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
			if spec.key == "use24h" or spec.key == "todayOnly" then
				JM.MainFrame:RefreshMessages()
				JM.MainFrame:RefreshList()
			end
		end)
		cb:SetPoint("TOPLEFT", 6, y)
		controls.checkboxes[spec.key] = cb
		y = y - 22
	end

	-- Which whisper sound, with a Test button.
	local soundLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	soundLabel:SetPoint("TOPLEFT", 8, y - 6)
	soundLabel:SetText("Whisper sound:")
	local soundBtn = Skin:CreateButton(content, 150, 20, "")
	soundBtn:SetPoint("LEFT", soundLabel, "RIGHT", 8, 0)
	soundBtn:SetScript("OnClick", function(self)
		Settings:ShowSoundMenu(self)
	end)
	local testBtn = Skin:CreateButton(content, 44, 20, "Test")
	testBtn:SetPoint("LEFT", soundBtn, "RIGHT", 4, 0)
	testBtn:SetScript("OnClick", function()
		JM.Whisper:PlayWhisperSound()
	end)
	controls.soundBtn = soundBtn
	y = y - 30

	y = SectionHeader(content, "Appearance & history", y - 10)
	for _, spec in ipairs(SLIDERS) do
		local s = Skin:CreateSlider(content, spec.label, spec.min, spec.max, spec.step, spec.format, function(value)
			Settings:Set(spec.key, value)
		end)
		s:SetPoint("TOPLEFT", 6, y)
		s:SetWidth(240)
		s.applyOnRelease = spec.key == "scale"
		controls.sliders[spec.key] = s
		y = y - 42
	end

	y = SectionHeader(content, "Quick replies", y - 10)
	qrContent = content
	qrTop = y
	qrBox = CreateFrame("Frame", nil, content)
	qrBox:SetPoint("TOPLEFT", 0, y)
	qrBox:SetPoint("RIGHT", content, "RIGHT", 0, 0)
	qrBox:SetHeight(ROW_STEP * 2)
	qrAddBtn = Skin:CreateButton(qrBox, 110, 20, "+ Add another")
	qrAddBtn:SetScript("OnClick", AddQuickReply)

	-- Everything below the quick replies hangs off this frame, so it moves
	-- down as rows are added and back up as they are removed.
	local tail = CreateFrame("Frame", nil, content)
	tail:SetPoint("TOPLEFT", qrBox, "BOTTOMLEFT", 0, 0)
	tail:SetPoint("RIGHT", content, "RIGHT", 0, 0)
	content = tail
	y = 0

	-- History clean-up: everything from before today goes, after a confirm.
	y = SectionHeader(content, "History", y - 10)
	local wipeBtn = Skin:CreateButton(content, 160, 22, "Delete all but today")
	wipeBtn:SetPoint("TOPLEFT", 6, y)
	wipeBtn:SetScript("OnClick", function()
		StaticPopup_Show("JM_DELETE_BEFORE_TODAY")
	end)
	local wipeHint = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	wipeHint:SetPoint("LEFT", wipeBtn, "RIGHT", 8, 0)
	wipeHint:SetTextColor(0.6, 0.6, 0.6)
	wipeHint:SetText("Keeps today's messages only.")
	y = y - 30

	-- About: what's new, and where to report problems.
	y = SectionHeader(content, "About", y - 10)
	local logBtn = Skin:CreateButton(content, 120, 22, "Changelog")
	logBtn:SetPoint("TOPLEFT", 6, y)
	logBtn:SetScript("OnClick", function()
		JM.Changelog:Toggle()
	end)
	local bugBtn = Skin:CreateButton(content, 160, 22, "Report a bug / request")
	bugBtn:SetPoint("LEFT", logBtn, "RIGHT", 6, 0)
	bugBtn:SetScript("OnClick", function()
		StaticPopup_Show("JM_ISSUES")
	end)
	y = y - 30

	local reset = Skin:CreateButton(content, 120, 22, "Reset to defaults")
	reset:SetPoint("TOPLEFT", 6, y - 14)
	reset:SetScript("OnClick", function()
		Settings:ResetToDefaults()
	end)
	y = y - 50

	tailHeight = -y
	tail:SetHeight(tailHeight)
	SetQuickReplyTexts(Settings.db and Settings.db.quickReplies or {})
	page:SetScript("OnShow", function()
		Settings:RefreshPage()
	end)
	return page
end

local soundMenuFrame
function Settings:ShowSoundMenu(anchor)
	soundMenuFrame = soundMenuFrame or CreateFrame("Frame", "JM_SoundMenu", UIParent, "UIDropDownMenuTemplate")
	local current = self.db.soundName or "default"
	local function Pick(key)
		Settings.db.soundName = key
		controls.soundBtn.text:SetText(JM.Whisper:SoundLabel(key))
		JM.Whisper:PlayWhisperSound()
		CloseDropDownMenus()
	end
	local menu = { { text = "Whisper sound", isTitle = true, notCheckable = true } }
	local shared = {}
	for _, choice in ipairs(JM.Whisper:GetSoundChoices()) do
		local item = {
			text = choice.label,
			checked = choice.key == current,
			func = function() Pick(choice.key) end,
		}
		-- ElvUI's whisper sound goes at the top; other shared sounds (there
		-- can be dozens) go in a submenu.
		if not choice.shared or choice.label == "Whisper Alert" then
			table.insert(menu, item)
		elseif #shared < 30 then
			table.insert(shared, item)
		end
	end
	if #shared > 0 then
		table.insert(menu, { text = "More sounds", hasArrow = true, notCheckable = true, menuList = shared })
	end
	EasyMenu(menu, soundMenuFrame, anchor, 0, 0, "MENU")
end

function Settings:RefreshPage()
	if not page then
		return
	end
	if controls.soundBtn then
		controls.soundBtn.text:SetText(JM.Whisper:SoundLabel(self.db.soundName))
	end
	for key, cb in pairs(controls.checkboxes) do
		cb:SetChecked(self.db[key] and true or false)
	end
	for key, s in pairs(controls.sliders) do
		s:SetValue(self.db[key])
	end
	SetQuickReplyTexts(self.db.quickReplies or {})
end
