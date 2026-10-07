-- The two-pane messenger window, laid out after WhisperMessenger: a title bar
-- (new whisper / mark all read / settings / close), a resizable contacts pane
-- on the left (JM.ContactList), and the open thread on the right - a header
-- with presence info, the bubble transcript (JM.Transcript) and the reply
-- box (JM.Composer). The settings page (JM.Settings) swaps in for the
-- right pane. This module owns the window chrome and the selection state and
-- coordinates the others.
JM.MainFrame = {}
local MainFrame = JM.MainFrame
local Skin = JM.Skin

local DEFAULT_W, DEFAULT_H = 760, 500
local MIN_W, MIN_H = 520, 340
local LIST_MIN, LIST_MAX, LIST_DEFAULT = 160, 320, 220
local RIGHT_MIN = 300
local TITLE_H = 30
local MARGIN = 10
local DIVIDER_W = 6

local mainFrame, listPanel, divider, rightPane, threadPane, settingsPage, emptyPane
local headerIcon, headerName, headerDot, headerStatus, headerSub, inviteBtn
local settingsBtn
local selectedName, dividerTime
local hiddenByCombat
local BuildFrame -- defined below; referenced by functions declared earlier

--------------------------------------
--   Saved window geometry          --
--------------------------------------

local function WindowDB()
	JM.db.window = JM.db.window or {}
	return JM.db.window
end

local function SavePosition()
	local point, _, relPoint, x, y = mainFrame:GetPoint()
	JM.db.framePosition = { point = point, relPoint = relPoint, x = x, y = y }
end

local function RestorePosition()
	local pos = JM.db.framePosition
	mainFrame:ClearAllPoints()
	if pos then
		-- 1.0 saved no relPoint (and assumed it matched point).
		mainFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
	else
		mainFrame:SetPoint("CENTER")
	end
end

local function ClampListWidth(w)
	local maxByWindow = mainFrame:GetWidth() - RIGHT_MIN - MARGIN * 2 - DIVIDER_W
	return math.max(LIST_MIN, math.min(w, LIST_MAX, maxByWindow))
end

local function ApplyListWidth()
	listPanel:SetWidth(ClampListWidth(WindowDB().listWidth or LIST_DEFAULT))
end

--------------------------------------
--   Header                         --
--------------------------------------

local function RefreshHeader()
	if not selectedName then
		return
	end
	local convo = JM.Store:GetConversation(selectedName)
	local info = JM.PlayerInfo:Get(selectedName, convo)
	JM.PlayerInfo:SetClassIcon(headerIcon, info.class)
	headerName:SetText(JM.ClassColor:ColorName(selectedName, info.class))
	headerDot:SetStatus(info.status)
	headerStatus:SetText(JM.PlayerInfo:StatusLabel(info.status))
	headerSub:SetText(JM.PlayerInfo:Describe(info))
end

--------------------------------------
--   Right pane state               --
--------------------------------------

local function ShowRightPane()
	if settingsPage:IsShown() then
		return
	end
	if selectedName then
		emptyPane:Hide()
		threadPane:Show()
	else
		threadPane:Hide()
		emptyPane:Show()
	end
end

function MainFrame:ToggleSettings(show)
	if not mainFrame then
		BuildFrame()
	end
	if show == nil then
		show = not settingsPage:IsShown()
	end
	if show then
		threadPane:Hide()
		emptyPane:Hide()
		settingsPage:Show()
		settingsBtn.text:SetText("Back")
	elseif settingsPage:IsShown() then
		settingsPage:Hide()
		settingsBtn.text:SetText("Settings")
		ShowRightPane()
		self:RefreshMessages(true)
	else
		ShowRightPane()
	end
end

--------------------------------------
--   Refresh / selection            --
--------------------------------------

function MainFrame:RefreshList()
	if not mainFrame then
		return
	end
	JM.ContactList:Refresh(selectedName)
end

function MainFrame:RefreshMessages(forceBottom)
	if not mainFrame or not selectedName or not threadPane:IsShown() then
		return
	end
	RefreshHeader()
	JM.Transcript:Render(selectedName, JM.Store:GetConversation(selectedName), {
		dividerTime = dividerTime,
		forceBottom = forceBottom,
	})
end

-- Where the "New messages" divider goes when a conversation is opened with
-- unread messages. 1.0 data has no lastReadTime, so fall back to counting
-- back unreadCount incoming messages.
local function ComputeDividerTime(convo)
	if not convo or (convo.unreadCount or 0) == 0 then
		return nil
	end
	if convo.lastReadTime then
		return convo.lastReadTime
	end
	local remaining = convo.unreadCount
	for i = #convo.messages, 1, -1 do
		local m = convo.messages[i]
		if m.inbound then
			remaining = remaining - 1
			if remaining == 0 then
				return m.time - 1
			end
		end
	end
	return 0
end

function MainFrame:SelectConversation(name)
	if not name or name == "" then
		return
	end
	name = JM.Store.FormatUserName(name)
	if not mainFrame then
		BuildFrame()
	end
	if name ~= selectedName then
		local convo = JM.Store:GetConversation(name, true)
		-- Keep a freshly started (still empty) conversation listed this session.
		convo.keep = true
		dividerTime = ComputeDividerTime(convo)
	end
	selectedName = name
	JM.Store:MarkRead(name)
	JM.Minimap:UpdateBadge()
	JM.Composer:SetConversation(name)
	self:ToggleSettings(false)
	self:RefreshList()
	self:RefreshMessages(true)
end

function MainFrame:GetSelected()
	return selectedName
end

function MainFrame:OnMessageReceived(name)
	-- The window may never have been built yet (it's built lazily on first
	-- show), so there may be nothing to refresh - the data is already in
	-- JM.Store regardless.
	if not mainFrame then
		return
	end
	if mainFrame:IsShown() and threadPane:IsShown() and name == selectedName then
		-- They're looking at it, so it's read.
		JM.Store:MarkRead(name)
		JM.Minimap:UpdateBadge()
		self:RefreshMessages()
	end
	self:RefreshList()
end

function MainFrame:HandleIncomingWhisper(name)
	local shown = mainFrame and mainFrame:IsShown()
	if shown and selectedName then
		-- Don't yank focus away from whatever conversation the user is
		-- actively viewing/typing a reply to - just update the list/badge.
		self:OnMessageReceived(name)
	elseif not shown and JM.Settings:Get("autoOpen") and not InCombatLockdown() then
		self:Show()
		self:SelectConversation(name)
	elseif shown then
		self:SelectConversation(name)
	else
		self:OnMessageReceived(name)
	end
end

function MainFrame:OnUnreadChanged(name)
	if name == selectedName then
		selectedName = nil
		JM.Composer:SetConversation(nil)
		ShowRightPane()
	end
	JM.Minimap:UpdateBadge()
	self:RefreshList()
end

function MainFrame:OnPresenceChanged()
	if mainFrame and mainFrame:IsShown() then
		self:RefreshList()
		RefreshHeader()
	end
end

function MainFrame:RemoveConversation(name)
	JM.Store:RemoveConversation(name)
	if name == selectedName then
		selectedName = nil
		JM.Composer:SetConversation(nil)
		ShowRightPane()
	end
	JM.Minimap:UpdateBadge()
	self:RefreshList()
end

function MainFrame:MarkAllRead()
	JM.Store:MarkAllRead()
	dividerTime = nil
	JM.Minimap:UpdateBadge()
	self:RefreshList()
	self:RefreshMessages()
end

function MainFrame:FocusEditBox()
	JM.Composer:Focus()
end

StaticPopupDialogs["JM_NEW_WHISPER"] = {
	text = "Whisper who?",
	button1 = ACCEPT or "Accept",
	button2 = CANCEL or "Cancel",
	hasEditBox = 1,
	maxLetters = 48,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
	OnAccept = function(self)
		local edit = _G[self:GetName() .. "EditBox"]
		local name = edit and string.match(edit:GetText() or "", "^%s*(%S+)")
		if name then
			MainFrame:SelectConversation(name)
			MainFrame:FocusEditBox()
		end
	end,
	EditBoxOnEnterPressed = function(self)
		local dialog = self:GetParent()
		StaticPopupDialogs["JM_NEW_WHISPER"].OnAccept(dialog)
		dialog:Hide()
	end,
	EditBoxOnEscapePressed = function(self)
		self:GetParent():Hide()
	end,
}

function MainFrame:PromptNewWhisper()
	StaticPopup_Show("JM_NEW_WHISPER")
end

--------------------------------------
--   Window settings / fade         --
--------------------------------------

function MainFrame:ApplyWindowSettings()
	if not mainFrame then
		return
	end
	mainFrame:SetScale(JM.Settings:Get("scale") or 1)
	mainFrame.fadeElapsed = 1 -- re-evaluate alpha on the next frame
end

-- WhisperMessenger-style: full opacity while hovered or typing, dimmed
-- otherwise. Polled a few times a second; there's no "mouse left a frame
-- and all its children" event.
local function FadeOnUpdate(self, elapsed)
	self.fadeElapsed = (self.fadeElapsed or 0) + elapsed
	if self.fadeElapsed < 0.15 then
		return
	end
	self.fadeElapsed = 0
	local active = MouseIsOver(self) or JM.Composer:HasFocus() or self.isMoving
		or (DropDownList1 and DropDownList1:IsShown())
	self:SetAlpha(active and 1 or (JM.Settings:Get("inactiveAlpha") or 1))
end

--------------------------------------
--   Build                          --
--------------------------------------

local function CreateTitleButton(text, width, onClick, tooltip)
	local btn = Skin:CreateButton(mainFrame, width, 20, text)
	btn:SetScript("OnClick", onClick)
	if tooltip then
		btn:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:AddLine(tooltip)
			GameTooltip:Show()
		end)
		btn:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
	end
	return btn
end

local function BuildHeader(parent)
	headerIcon = parent:CreateTexture(nil, "ARTWORK")
	headerIcon:SetSize(32, 32)
	headerIcon:SetPoint("TOPLEFT", 10, -10)

	headerName = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	headerName:SetPoint("TOPLEFT", headerIcon, "TOPRIGHT", 10, 0)

	headerDot = Skin:CreateStatusDot(parent, 8)
	headerDot:SetPoint("LEFT", headerName, "RIGHT", 8, 0)

	headerStatus = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	headerStatus:SetPoint("LEFT", headerDot, "RIGHT", 4, 0)
	headerStatus:SetTextColor(0.7, 0.7, 0.7)

	headerSub = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	headerSub:SetPoint("BOTTOMLEFT", headerIcon, "BOTTOMRIGHT", 10, 0)
	headerSub:SetTextColor(0.6, 0.6, 0.6)

	inviteBtn = Skin:CreateButton(parent, 60, 20, "Invite")
	inviteBtn:SetPoint("TOPRIGHT", -10, -10)
	inviteBtn:SetScript("OnClick", function()
		if selectedName then
			InviteUnit(selectedName)
		end
	end)

	local line = parent:CreateTexture(nil, "ARTWORK")
	line:SetTexture(Skin.WHITE)
	line:SetVertexColor(1, 1, 1, 0.08)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", 0, -52)
	line:SetPoint("TOPRIGHT", 0, -52)
end

function BuildFrame()
	local win = WindowDB()
	mainFrame = CreateFrame("Frame", "JM_MainFrame", UIParent)
	mainFrame:SetSize(win.width or DEFAULT_W, win.height or DEFAULT_H)
	mainFrame:SetFrameStrata("DIALOG")
	mainFrame:SetToplevel(true)
	mainFrame:SetClampedToScreen(true)
	mainFrame:SetMovable(true)
	mainFrame:SetResizable(true)
	mainFrame:SetMinResize(MIN_W, MIN_H)
	mainFrame:SetMaxResize(1600, 1200)
	mainFrame:EnableMouse(true)
	mainFrame:RegisterForDrag("LeftButton")
	mainFrame:SetScript("OnDragStart", function(self)
		self.isMoving = true
		self:StartMoving()
	end)
	mainFrame:SetScript("OnDragStop", function(self)
		self.isMoving = nil
		self:StopMovingOrSizing()
		SavePosition()
	end)
	Skin:StylePanel(mainFrame, 0.95)
	RestorePosition()
	mainFrame:Hide()
	-- Escape closes it, like Blizzard panels.
	table.insert(UISpecialFrames, "JM_MainFrame")

	-- Title bar.
	local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	title:SetPoint("TOP", 0, -9)
	title:SetText("Messages")
	-- Swaps in for the title when a newer version has been seen.
	JM.VersionCheck:AttachNotice(mainFrame, title)

	local newBtn = CreateTitleButton("+ New", 50, function()
		MainFrame:PromptNewWhisper()
	end, "Start a new whisper")
	newBtn:SetPoint("TOPLEFT", 6, -5)

	local readBtn = CreateTitleButton("Mark read", 66, function()
		MainFrame:MarkAllRead()
	end, "Mark all conversations as read")
	readBtn:SetPoint("LEFT", newBtn, "RIGHT", 4, 0)

	local close = CreateTitleButton("X", 20, function()
		MainFrame:Hide()
	end)
	close:SetPoint("TOPRIGHT", -6, -5)

	settingsBtn = CreateTitleButton("Settings", 60, function()
		MainFrame:ToggleSettings()
	end)
	settingsBtn:SetPoint("RIGHT", close, "LEFT", -4, 0)

	-- Left pane.
	listPanel = CreateFrame("Frame", nil, mainFrame)
	listPanel:SetPoint("TOPLEFT", MARGIN, -TITLE_H)
	listPanel:SetPoint("BOTTOMLEFT", MARGIN, MARGIN)
	Skin:StylePanel(listPanel, 0.6)
	JM.ContactList:Build(listPanel)

	-- Draggable splitter between the panes.
	divider = CreateFrame("Button", nil, mainFrame)
	divider:SetWidth(DIVIDER_W)
	divider:SetPoint("TOPLEFT", listPanel, "TOPRIGHT", 0, 0)
	divider:SetPoint("BOTTOMLEFT", listPanel, "BOTTOMRIGHT", 0, 0)
	local grip = divider:CreateTexture(nil, "HIGHLIGHT")
	grip:SetTexture(Skin.WHITE)
	grip:SetVertexColor(1, 1, 1, 0.25)
	grip:SetPoint("TOP")
	grip:SetPoint("BOTTOM")
	grip:SetWidth(2)
	divider:SetScript("OnMouseDown", function(self)
		self:SetScript("OnUpdate", function()
			local x = GetCursorPosition() / mainFrame:GetEffectiveScale()
			listPanel:SetWidth(ClampListWidth(x - mainFrame:GetLeft() - MARGIN))
		end)
	end)
	divider:SetScript("OnMouseUp", function(self)
		self:SetScript("OnUpdate", nil)
		WindowDB().listWidth = math.floor(listPanel:GetWidth() + 0.5)
		MainFrame:RefreshMessages()
	end)

	-- Right pane: thread, empty state, or settings.
	rightPane = CreateFrame("Frame", nil, mainFrame)
	rightPane:SetPoint("TOPLEFT", divider, "TOPRIGHT", 0, 0)
	rightPane:SetPoint("BOTTOMRIGHT", -MARGIN, MARGIN)
	Skin:StylePanel(rightPane, 0.6)

	threadPane = CreateFrame("Frame", nil, rightPane)
	threadPane:SetAllPoints()
	threadPane:Hide()
	BuildHeader(threadPane)

	local transcriptPanel = CreateFrame("Frame", nil, threadPane)
	transcriptPanel:SetPoint("TOPLEFT", 0, -54)
	transcriptPanel:SetPoint("BOTTOMRIGHT", 0, 48)
	local transcriptScroll = JM.Transcript:Build(transcriptPanel)
	-- Bubbles wrap to the pane width, which is only known once the window has
	-- been laid out (and changes while the splitter is dragged).
	transcriptScroll:SetScript("OnSizeChanged", JM.Timer:Debounce(0.1, function()
		MainFrame:RefreshMessages()
	end))

	JM.Composer:Build(threadPane)

	emptyPane = CreateFrame("Frame", nil, rightPane)
	emptyPane:SetAllPoints()
	local emptyTitle = emptyPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	emptyTitle:SetPoint("CENTER", 0, 24)
	emptyTitle:SetText("Johnny's Messenger")
	local emptyText = emptyPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	emptyText:SetPoint("TOP", emptyTitle, "BOTTOM", 0, -8)
	emptyText:SetTextColor(0.6, 0.6, 0.6)
	emptyText:SetText("Pick a conversation on the left, or start a new one.")
	local emptyBtn = Skin:CreateButton(emptyPane, 130, 24, "Start new whisper")
	emptyBtn:SetPoint("TOP", emptyText, "BOTTOM", 0, -12)
	emptyBtn:SetScript("OnClick", function()
		MainFrame:PromptNewWhisper()
	end)

	settingsPage = JM.Settings:BuildPage(rightPane)

	-- Bottom-right resize grip.
	local resize = CreateFrame("Button", nil, mainFrame)
	resize:SetSize(12, 12)
	resize:SetPoint("BOTTOMRIGHT", -1, 1)
	local resizeTex = resize:CreateTexture(nil, "OVERLAY")
	resizeTex:SetTexture(Skin.WHITE)
	resizeTex:SetVertexColor(1, 1, 1, 0.3)
	resizeTex:SetPoint("BOTTOMRIGHT", -2, 2)
	resizeTex:SetSize(6, 6)
	resize:SetScript("OnMouseDown", function()
		mainFrame.isMoving = true
		mainFrame:StartSizing("BOTTOMRIGHT")
	end)
	resize:SetScript("OnMouseUp", function()
		mainFrame.isMoving = nil
		mainFrame:StopMovingOrSizing()
		win.width = math.floor(mainFrame:GetWidth() + 0.5)
		win.height = math.floor(mainFrame:GetHeight() + 0.5)
		SavePosition()
		ApplyListWidth()
		MainFrame:RefreshMessages()
	end)

	-- Re-wrap bubbles while resizing, but at most a few times a second.
	local relayout = JM.Timer:Debounce(0.1, function()
		ApplyListWidth()
		MainFrame:RefreshList()
		MainFrame:RefreshMessages()
	end)
	mainFrame:SetScript("OnSizeChanged", relayout)

	mainFrame:SetScript("OnShow", function()
		JM.PlayerInfo:RequestGuildRoster()
		ShowRightPane()
		MainFrame:RefreshList()
		MainFrame:RefreshMessages()
	end)
	mainFrame:SetScript("OnUpdate", FadeOnUpdate)

	ApplyListWidth()
	MainFrame:ApplyWindowSettings()
end

--------------------------------------
--   Show / hide / combat           --
--------------------------------------

function MainFrame:Toggle()
	if not mainFrame then
		BuildFrame()
	end
	if mainFrame:IsShown() then
		mainFrame:Hide()
	else
		mainFrame:Show()
	end
end

function MainFrame:Show()
	if not mainFrame then
		BuildFrame()
	end
	mainFrame:Show()
end

function MainFrame:Hide()
	if mainFrame then
		mainFrame:Hide()
	end
end

local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function(self, event)
	if not mainFrame or not JM.db or not JM.Settings:Get("hideInCombat") then
		hiddenByCombat = nil
		return
	end
	if event == "PLAYER_REGEN_DISABLED" and mainFrame:IsShown() then
		hiddenByCombat = true
		mainFrame:Hide()
	elseif event == "PLAYER_REGEN_ENABLED" and hiddenByCombat then
		hiddenByCombat = nil
		mainFrame:Show()
	end
end)
