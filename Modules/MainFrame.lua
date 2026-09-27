-- The two-pane Teams-style window: left = conversation list (pooled rows in
-- a scrollframe, modeled on JohnnysAddonHub's RaidBrowserUI/BlackListUI list
-- pattern), right = the open thread. The thread is a single ScrollingMessageFrame
-- (like a real chat window) rather than pooled per-message rows, so item/
-- achievement/spell links are clickable - this is the exact widget/script
-- setup the actual WIM addon uses for the same purpose (see its
-- Sources/MessageWindows.lua, chat_display), confirmed working on this
-- client. An earlier SimpleHTML-based attempt at the same goal silently
-- failed to parse hyperlinks at all here; ScrollingMessageFrame is the
-- proven option. Trade-off: messages render in one shared left-aligned
-- column like a normal chat log, not per-side bubbles.
JM.MainFrame = {}
local MainFrame = JM.MainFrame
local Skin = JM.Skin

local FRAME_WIDTH, FRAME_HEIGHT = 600, 450
local LEFT_PANEL_WIDTH = 170
local ROW_WIDTH = LEFT_PANEL_WIDTH - 26 -- scrollbar clearance
local ROW_HEIGHT = 44

local mainFrame, listContent, msgDisplay, editBox, headerName, inviteBtn, scanBtn, scanResultText, emptyText
local rows = {}
local selectedName

local function TruncateText(text, maxLen)
	text = text or ""
	if string.len(text) > maxLen then
		return string.sub(text, 1, maxLen) .. "..."
	end
	return text
end

local function RelativeTime(epoch)
	if not epoch or epoch == 0 then
		return ""
	end
	local diff = time() - epoch
	if diff < 60 then
		return "now"
	elseif diff < 3600 then
		return math.floor(diff / 60) .. "m"
	elseif diff < 86400 then
		return math.floor(diff / 3600) .. "h"
	else
		return math.floor(diff / 86400) .. "d"
	end
end

local function RefreshSelectionHighlight()
	for _, row in ipairs(rows) do
		Skin:StyleRow(row, row.name ~= nil and row.name == selectedName)
	end
end

local function CreateRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(ROW_WIDTH, ROW_HEIGHT)
	Skin:StyleRow(row, false)

	local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	nameText:SetPoint("TOPLEFT", 8, -6)
	nameText:SetJustifyH("LEFT")
	row.nameText = nameText

	local timeText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	timeText:SetPoint("TOPRIGHT", -8, -6)
	timeText:SetTextColor(0.6, 0.6, 0.6)
	row.timeText = timeText

	local previewText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	previewText:SetPoint("TOPLEFT", 8, -23)
	previewText:SetPoint("RIGHT", -8, 0)
	previewText:SetJustifyH("LEFT")
	previewText:SetTextColor(0.6, 0.6, 0.6)
	row.previewText = previewText

	local unreadText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	unreadText:SetPoint("BOTTOMRIGHT", -8, 6)
	unreadText:SetTextColor(1, 1, 1)
	row.unreadText = unreadText

	row:SetScript("OnClick", function(self)
		MainFrame:SelectConversation(self.name)
	end)

	return row
end

function MainFrame:RefreshList()
	local list = JM.Store:GetSortedConversationList()

	for i, entry in ipairs(list) do
		local row = rows[i]
		if not row then
			row = CreateRow(listContent)
			row:SetPoint("TOPLEFT", listContent, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
			rows[i] = row
		end

		row.name = entry.name
		row.nameText:SetText(JM.ClassColor:ColorName(entry.name, entry.convo.class))
		row.timeText:SetText(RelativeTime(entry.convo.lastMessageTime))

		local lastMsg = entry.convo.messages[#entry.convo.messages]
		row.previewText:SetText(lastMsg and TruncateText(lastMsg.msg, 30) or "")

		if (entry.convo.unreadCount or 0) > 0 then
			row.unreadText:SetText("(" .. entry.convo.unreadCount .. ")")
		else
			row.unreadText:SetText("")
		end

		row:Show()
	end

	for i = #list + 1, #rows do
		rows[i].name = nil
		rows[i]:Hide()
	end

	listContent:SetHeight(math.max(20, #list * ROW_HEIGHT))
	RefreshSelectionHighlight()

	if #list == 0 then
		emptyText:SetText("No conversations yet.\nWhisper someone to get started.")
		emptyText:Show()
		msgDisplay:Hide()
	elseif not selectedName then
		emptyText:SetText("Select a conversation to start chatting.")
		emptyText:Show()
		msgDisplay:Hide()
	else
		emptyText:Hide()
		msgDisplay:Show()
	end
end

function MainFrame:RefreshMessages(forceBottom)
	-- Like WoW's own chat frame: new messages only pull you down if you were
	-- already caught up. GetScrollOffset()/SetScrollOffset() would be the
	-- precise way to do this but error as nil methods on this client's
	-- ScrollingMessageFrame despite being standard Blizzard API - AtBottom()
	-- is what WIM's own WindowHandler.lua uses instead (proven to exist
	-- here), so that's the only signal available; there's no way to restore
	-- an exact prior position after Clear() rebuilds the whole buffer.
	local wasAtBottom = forceBottom or msgDisplay:AtBottom()

	msgDisplay:Clear()

	if not selectedName then
		headerName:SetText("")
		inviteBtn:Hide()
		scanBtn:Hide()
		return
	end

	local convo = JM.Store:GetConversation(selectedName)
	headerName:SetText(JM.ClassColor:ColorName(selectedName, convo and convo.class))
	inviteBtn:Show()
	scanBtn:Show()
	if not convo then
		return
	end

	local myName = UnitName("player")
	local myClass = JM.ClassColor:GetMyEnglishClass()

	for _, m in ipairs(convo.messages) do
		local ts = date("%H:%M", m.time)
		if m.inbound then
			msgDisplay:AddMessage(JM.ClassColor:ColorName(selectedName, m.class) .. ": " .. m.msg .. " |cff888888[" .. ts .. "]|r", 1, 1, 1)
		else
			-- Your own messages still show your name so the thread reads the
			-- same way regardless of who sent which line.
			msgDisplay:AddMessage(JM.ClassColor:ColorName(myName, myClass) .. ": " .. m.msg .. " |cff888888[" .. ts .. "]|r", 0.85, 0.85, 0.85)
		end
	end

	if wasAtBottom then
		msgDisplay:ScrollToBottom()
	end
	-- else: leave it where Clear()+AddMessage() naturally settles - no
	-- SetScrollOffset() available on this client to restore a specific
	-- prior position (see the note above).
end

function MainFrame:SelectConversation(name)
	if not name or name == "" then
		return
	end
	if name ~= selectedName and scanResultText then
		scanResultText:SetText("")
	end
	selectedName = name
	JM.Store:MarkRead(name)
	JM.Minimap:UpdateBadge()
	self:RefreshMessages(true)
	self:RefreshList()
end

function MainFrame:OnMessageReceived(name)
	-- The window may never have been opened yet (mainFrame/listContent
	-- only get built lazily on first Show/Toggle), so there may be
	-- nothing to refresh - the data is already in JM.Store regardless.
	if not mainFrame then
		return
	end
	self:RefreshList()
	if mainFrame:IsShown() and name == selectedName then
		self:RefreshMessages()
	end
end

function MainFrame:HandleIncomingWhisper(name)
	if mainFrame and mainFrame:IsShown() and selectedName then
		-- Don't yank focus away from whatever conversation the user is
		-- actively viewing/typing a reply to - just update the list/badge.
		self:OnMessageReceived(name)
	else
		self:Show()
		self:SelectConversation(name)
	end
end

function MainFrame:FocusEditBox()
	if editBox then
		editBox:SetFocus()
	end
end

local function SendCurrentMessage()
	if not selectedName or not editBox then
		return
	end
	local text = editBox:GetText()
	if text and text ~= "" then
		JM.Whisper:SendWhisper(selectedName, text)
		editBox:SetText("")
	end
end

-- Shift-clicking an item/spell/achievement while this window's reply box has
-- focus should insert the link, exactly like a real chat edit box does.
-- ChatEdit_GetActiveWindow() (Blizzard FrameXML) only scans the standard
-- ChatFrame<N>EditBox globals, so our editBox is invisible to it and
-- ChatEdit_InsertLink silently no-ops while typing here. Hook it and insert
-- into our own box when IT is the one actually focused - hooksecurefunc
-- leaves the original function (and real chat windows) untouched.
hooksecurefunc("ChatEdit_InsertLink", function(link)
	if editBox and editBox:IsVisible() and editBox:HasFocus() then
		editBox:Insert(link)
	end
end)

local function BuildFrame()
	mainFrame = CreateFrame("Frame", "JM_MainFrame", UIParent)
	mainFrame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)

	local pos = JM.db.framePosition
	if pos then
		mainFrame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
	else
		mainFrame:SetPoint("CENTER")
	end

	mainFrame:SetFrameStrata("DIALOG")
	mainFrame:SetMovable(true)
	mainFrame:EnableMouse(true)
	mainFrame:RegisterForDrag("LeftButton")
	mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
	mainFrame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, _, x, y = self:GetPoint()
		JM.db.framePosition = { point = point, x = x, y = y }
	end)
	Skin:StylePanel(mainFrame, 0.95)
	mainFrame:Hide()

	local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	title:SetPoint("TOP", 0, -16)
	title:SetTextColor(1, 1, 1)
	title:SetText("Messages")

	local close = Skin:CreateButton(mainFrame, 20, 20, "X")
	close:SetPoint("TOPRIGHT", -4, -4)
	close:SetScript("OnClick", function() MainFrame:Hide() end)

	-- Left pane: conversation list.
	local leftPanel = CreateFrame("Frame", nil, mainFrame)
	leftPanel:SetPoint("TOPLEFT", 16, -48)
	leftPanel:SetSize(LEFT_PANEL_WIDTH, FRAME_HEIGHT - 64)
	Skin:StylePanel(leftPanel, 0.6)

	local listScroll = CreateFrame("ScrollFrame", "JM_ContactScroll", leftPanel, "UIPanelScrollFrameTemplate")
	listScroll:SetPoint("TOPLEFT", 2, -2)
	listScroll:SetPoint("BOTTOMRIGHT", -24, 2)

	listContent = CreateFrame("Frame", nil, listScroll)
	listContent:SetSize(ROW_WIDTH, 20)
	listScroll:SetScrollChild(listContent)

	-- Right pane: header + message thread + reply box.
	local rightX = 16 + LEFT_PANEL_WIDTH + 16

	headerName = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	headerName:SetPoint("TOPLEFT", rightX, -50)

	inviteBtn = Skin:CreateButton(mainFrame, 76, 20, "Invite")
	inviteBtn:SetPoint("LEFT", headerName, "RIGHT", 10, 0)
	inviteBtn:SetScript("OnClick", function()
		if selectedName then
			InviteUnit(selectedName)
		end
	end)
	inviteBtn:Hide()

	scanBtn = Skin:CreateButton(mainFrame, 60, 20, "Scan")
	scanBtn:SetPoint("LEFT", inviteBtn, "RIGHT", 8, 0)
	scanBtn:SetScript("OnClick", function()
		if not selectedName or not JM.GearScan then
			return
		end
		local target = selectedName
		scanResultText:SetTextColor(0.6, 0.6, 0.6)
		scanResultText:SetText("Scanning...")
		JM.GearScan:Scan(target, function(result)
			-- The player may have switched conversations while the scan
			-- (up to a few seconds) was in flight - drop stale results.
			if selectedName ~= target then
				return
			end
			if not result.ok then
				-- Out of range / no response - just clear back to blank
				-- rather than showing an error.
				scanResultText:SetText("")
				return
			end
			local levelText = (result.level and result.level > 0) and tostring(result.level) or "??"
			local emptyText2 = result.emptySlots > 0 and (", " .. result.emptySlots .. " empty slot" .. (result.emptySlots > 1 and "s" or "")) or ""
			scanResultText:SetTextColor(1, 1, 1)
			scanResultText:SetText("Lvl " .. levelText .. "  |  GS ~" .. result.score .. " (approx" .. emptyText2 .. ")")
		end)
	end)
	scanBtn:Hide()

	scanResultText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	scanResultText:SetPoint("TOPLEFT", rightX, -74)
	scanResultText:SetTextColor(0.6, 0.6, 0.6)

	local msgPanel = CreateFrame("Frame", nil, mainFrame)
	msgPanel:SetPoint("TOPLEFT", rightX, -94)
	msgPanel:SetPoint("RIGHT", -16, 0)
	msgPanel:SetPoint("BOTTOM", mainFrame, "BOTTOM", 0, 56)
	Skin:StylePanel(msgPanel, 0.6)

	-- ScrollingMessageFrame, not a ScrollFrame+content pair - this is the
	-- widget WIM's own chat_display uses (Sources/MessageWindows.lua) so
	-- item/achievement/spell hyperlinks in a message are clickable; it
	-- manages its own line buffer/wrapping/scrolling natively.
	msgDisplay = CreateFrame("ScrollingMessageFrame", "JM_MessageDisplay", msgPanel)
	msgDisplay:SetPoint("TOPLEFT", 8, -8)
	msgDisplay:SetPoint("BOTTOMRIGHT", -12, 8)
	msgDisplay:SetFontObject("GameFontHighlightSmall")
	msgDisplay:SetJustifyH("LEFT")
	msgDisplay:SetFading(false)
	msgDisplay:SetMaxLines(200)
	msgDisplay:EnableMouse(true)
	msgDisplay:EnableMouseWheel(true)
	msgDisplay:SetScript("OnMouseWheel", function(self, delta)
		if delta > 0 then
			self:ScrollUp()
		else
			self:ScrollDown()
		end
	end)
	-- Same three scripts + ChatFrame_OnHyperlinkShow dispatcher WIM's
	-- chat_display uses - it already knows how to open an item tooltip, an
	-- achievement, a whisper-a-linked-player, etc. without special-casing
	-- each link type here.
	msgDisplay:SetScript("OnHyperlinkClick", function(self, link, text, mouseButton)
		ChatFrame_OnHyperlinkShow(link, text, mouseButton)
	end)
	msgDisplay:SetScript("OnHyperlinkEnter", function(self, link)
		GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
		GameTooltip:SetHyperlink(link)
		GameTooltip:Show()
	end)
	msgDisplay:SetScript("OnHyperlinkLeave", function()
		GameTooltip:Hide()
	end)

	emptyText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	emptyText:SetPoint("CENTER", msgPanel, "CENTER")
	emptyText:SetTextColor(0.5, 0.5, 0.5)
	emptyText:SetJustifyH("CENTER")

	local editWidth = FRAME_WIDTH - LEFT_PANEL_WIDTH - 48 - 90
	local editHolder = Skin:CreateEditBox(mainFrame, editWidth, 28)
	editHolder:SetPoint("BOTTOMLEFT", rightX, 16)
	editBox = editHolder.editBox
	editBox:SetScript("OnEnterPressed", function(self)
		SendCurrentMessage()
		self:ClearFocus()
	end)

	local sendBtn = Skin:CreateButton(mainFrame, 80, 28, "Send")
	sendBtn:SetPoint("LEFT", editHolder, "RIGHT", 8, 0)
	sendBtn:SetScript("OnClick", SendCurrentMessage)

	mainFrame:SetScript("OnShow", function()
		MainFrame:RefreshList()
		MainFrame:RefreshMessages()
	end)
end

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
