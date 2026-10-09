-- Left pane: search box, All / Unread tabs, and conversation rows (pooled
-- rows in a scrollframe, the same list pattern as 1.0). Conversations where
-- only you have spoken are folded under a "Sent requests" row. Row layout follows WhisperMessenger: class
-- icon with a presence dot, class-colored name, relative time, a preview
-- line (or "Draft: ..."), and an unread badge; pinned rows sort first.
JM.ContactList = {}
local ContactList = JM.ContactList
local Skin = JM.Skin

local ROW_HEIGHT = 46
local ICON_SIZE = 28
local GROUP_HEIGHT = 24
-- How long the "Removed X - Undo" bar stays up.
local UNDO_SECONDS = 10

local listScroll, listContent, searchHolder, emptyText, newBtn
local allTab, unreadTab, groupRow, groupClear, undoBar
local rows = {}
local filter = ""
-- "all" (the default: real conversations, then unanswered sent requests
-- folded under one row) or "unread".
local view = "all"

--------------------------------------
--   Formatting                     --
--------------------------------------

-- now / 5m / 3h / Yesterday / Mon / Oct 7 (WhisperMessenger's TimeFormat).
function ContactList.RelativeTime(epoch)
	if not epoch or epoch == 0 then
		return ""
	end
	local now = time()
	local diff = now - epoch
	if diff < 60 then
		return "now"
	elseif diff < 3600 then
		return math.floor(diff / 60) .. "m"
	end
	local day = date("%Y%m%d", epoch)
	if day == date("%Y%m%d", now) then
		return math.floor(diff / 3600) .. "h"
	elseif day == date("%Y%m%d", now - 86400) then
		return "Yesterday"
	elseif diff < 6 * 86400 then
		return date("%a", epoch)
	end
	return date("%b ", epoch) .. tonumber(date("%d", epoch))
end

-- Strips color/link escapes so previews show the link's visible text.
local function PlainText(text)
	text = string.gsub(text or "", "|c%x%x%x%x%x%x%x%x", "")
	text = string.gsub(text, "|r", "")
	text = string.gsub(text, "|H.-|h(.-)|h", "%1")
	return text
end

local function Truncate(text, maxLen)
	if string.len(text) > maxLen then
		return string.sub(text, 1, maxLen) .. "..."
	end
	return text
end

--------------------------------------
--   Context menu                   --
--------------------------------------

local menuFrame = CreateFrame("Frame", "JM_ContactMenu", UIParent, "UIDropDownMenuTemplate")

local function ShowContextMenu(name)
	local convo = JM.Store:GetConversation(name)
	if not convo then
		return
	end
	local menu = {
		{ text = name, isTitle = 1, notCheckable = 1 },
		{ text = convo.pinned and "Unpin" or "Pin to top", notCheckable = 1, func = function()
			convo.pinned = not convo.pinned or nil
			JM.MainFrame:RefreshList()
		end },
		{ text = convo.muted and "Unmute" or "Mute", notCheckable = 1, func = function()
			convo.muted = not convo.muted or nil
			JM.MainFrame:RefreshList()
		end },
		{ text = "Mark as unread", notCheckable = 1, func = function()
			JM.Store:MarkUnread(name)
			JM.MainFrame:OnUnreadChanged(name)
		end },
		{ text = "Invite to group", notCheckable = 1, func = function()
			InviteUnit(name)
		end },
		{ text = "Who is this?", notCheckable = 1, func = function()
			SendWho("n-\"" .. name .. "\"")
		end },
		{ text = "|cffff6060Remove conversation|r", notCheckable = 1, func = function()
			JM.MainFrame:RemoveConversation(name)
		end },
		{ text = CANCEL or "Cancel", notCheckable = 1 },
	}
	EasyMenu(menu, menuFrame, "cursor", 0, 0, "MENU")
end

--------------------------------------
--   Rows                           --
--------------------------------------

local function ShowRowTooltip(row)
	local convo = JM.Store:GetConversation(row.name)
	if not convo then
		return
	end
	local info = JM.PlayerInfo:Get(row.name, convo)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:AddLine(JM.ClassColor:ColorName(row.name, info.class))
	local desc = JM.PlayerInfo:Describe(info)
	if desc ~= "" then
		GameTooltip:AddLine(desc, 0.8, 0.8, 0.8)
	end
	if info.status then
		local c = Skin.STATUS_COLORS[info.status]
		GameTooltip:AddLine(JM.PlayerInfo:StatusLabel(info.status), c[1], c[2], c[3])
	end
	local last = convo.messages[#convo.messages]
	if last then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(Truncate(PlainText(last.msg), 80), 1, 1, 1, true)
	end
	if (convo.unreadCount or 0) > 0 then
		GameTooltip:AddLine(convo.unreadCount .. " unread", 1, 1, 1)
	end
	if convo.muted then
		GameTooltip:AddLine("Muted", 0.6, 0.6, 0.6)
	end
	GameTooltip:AddLine("Right-click for options", 0.5, 0.5, 0.5)
	GameTooltip:Show()
end

local function CreateRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW_HEIGHT)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	local bar = row:CreateTexture(nil, "OVERLAY")
	bar:SetTexture(Skin.WHITE)
	bar:SetVertexColor(0.725, 0.886, 0.290, 1)
	bar:SetPoint("TOPLEFT")
	bar:SetPoint("BOTTOMLEFT")
	bar:SetWidth(2)
	row.selectBar = bar
	Skin:StyleRow(row, false)

	local icon = row:CreateTexture(nil, "ARTWORK")
	icon:SetSize(ICON_SIZE, ICON_SIZE)
	icon:SetPoint("LEFT", 8, 0)
	row.icon = icon

	local dot = Skin:CreateStatusDot(row, 9)
	dot:SetPoint("CENTER", icon, "BOTTOMRIGHT", -2, 2)
	dot:SetFrameLevel(row:GetFrameLevel() + 2)
	row.dot = dot

	local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	nameText:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -1)
	nameText:SetJustifyH("LEFT")
	nameText:SetHeight(12)
	row.nameText = nameText

	local timeText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	timeText:SetPoint("TOPRIGHT", -8, -8)
	timeText:SetTextColor(0.55, 0.55, 0.55)
	row.timeText = timeText
	nameText:SetPoint("RIGHT", timeText, "LEFT", -4, 0)

	local badge = Skin:CreateBadge(row)
	badge:SetPoint("BOTTOMRIGHT", -8, 7)
	row.badge = badge

	-- Pin and Remove, shown on the selected row only - the same two actions
	-- as the right-click menu, where they were easy to miss.
	local removeBtn = Skin:CreateButton(row, 18, 15, "X")
	removeBtn:SetPoint("BOTTOMRIGHT", -6, 6)
	removeBtn:SetScript("OnClick", function()
		if row.name then
			JM.MainFrame:RemoveConversation(row.name)
		end
	end)
	removeBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Remove conversation", 1, 1, 1)
		GameTooltip:AddLine("Deletes its history. You get a few seconds to undo.", nil, nil, nil, true)
		GameTooltip:Show()
	end)
	removeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	removeBtn:Hide()
	row.removeBtn = removeBtn

	local pinBtn = Skin:CreateButton(row, 40, 15, "Pin")
	pinBtn:SetPoint("RIGHT", removeBtn, "LEFT", -2, 0)
	pinBtn:SetScript("OnClick", function()
		local convo = row.name and JM.Store:GetConversation(row.name)
		if convo then
			convo.pinned = not convo.pinned or nil
			JM.MainFrame:RefreshList()
		end
	end)
	pinBtn:Hide()
	row.pinBtn = pinBtn

	local previewText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	previewText:SetJustifyH("LEFT")
	previewText:SetHeight(12)
	if previewText.SetWordWrap then
		previewText:SetWordWrap(false)
	end
	row.previewText = previewText

	row:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			ShowContextMenu(self.name)
		else
			JM.MainFrame:SelectConversation(self.name)
		end
	end)
	row:SetScript("OnEnter", ShowRowTooltip)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	return row
end

local function FillRow(row, entry, selectedName)
	local convo = entry.convo
	local info = JM.PlayerInfo:Get(entry.name, convo)
	local selected = (entry.name == selectedName)
	row.name = entry.name
	row.pinned = convo.pinned

	JM.PlayerInfo:SetClassIcon(row.icon, info.class)
	row.dot:SetStatus(info.status)

	local name = JM.ClassColor:ColorName(entry.name, info.class)
	if convo.pinned then
		name = name .. " |cff808080(pinned)|r"
	end
	row.nameText:SetText(name)
	row.timeText:SetText(ContactList.RelativeTime(convo.lastMessageTime))

	local preview
	if convo.draft and convo.draft ~= "" and entry.name ~= selectedName then
		preview = "|cffffffffDraft:|r " .. PlainText(convo.draft)
	else
		local last = convo.messages[#convo.messages]
		if last then
			preview = (last.inbound or last.kind == "system") and PlainText(last.msg) or ("You: " .. PlainText(last.msg))
		end
	end
	if convo.muted then
		preview = "(muted) " .. (preview or "")
	end
	row.previewText:SetText(Truncate(preview or "", 120))
	row.previewText:SetTextColor(0.6, 0.6, 0.6)

	local unread = (convo.unreadCount or 0) > 0
	row.badge:SetCount(convo.unreadCount)
	-- Unread rows get a brighter preview so they stand out without color.
	if unread then
		row.previewText:SetTextColor(0.9, 0.9, 0.9)
	end

	if selected then
		row.pinBtn.text:SetText(convo.pinned and "Unpin" or "Pin")
		row.pinBtn:Show()
		row.removeBtn:Show()
	else
		row.pinBtn:Hide()
		row.removeBtn:Hide()
	end

	-- The preview runs to the row's edge unless something sits there: the
	-- selected row's buttons, or an unread badge.
	row.previewText:ClearAllPoints()
	row.previewText:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 1)
	if selected then
		row.previewText:SetPoint("RIGHT", row.pinBtn, "LEFT", -4, 0)
	elseif unread then
		row.previewText:SetPoint("RIGHT", row.badge, "LEFT", -4, 0)
	else
		row.previewText:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	end
end

--------------------------------------
--   Build / refresh                --
--------------------------------------

local function PaintTab(btn, on)
	local C = Skin.C
	if on then
		btn:SetBackdropColor(0.122, 0.153, 0.169, 0.95)
		btn:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
		btn.text:SetTextColor(C.text[1], C.text[2], C.text[3])
	else
		btn:SetBackdropColor(C.panel[1], C.panel[2], C.panel[3], 0.95)
		btn:SetBackdropBorderColor(C.rule2[1], C.rule2[2], C.rule2[3], 1)
		btn.text:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
	end
end

local function WindowDB()
	JM.db.window = JM.db.window or {}
	return JM.db.window
end

function ContactList:Build(parent)
	local C = Skin.C

	searchHolder = Skin:CreateEditBox(parent, 100, 22)
	searchHolder:SetPoint("TOPLEFT", 6, -6)
	searchHolder:SetPoint("TOPRIGHT", -6, -6)
	searchHolder.placeholder:SetText("Search chats")
	searchHolder.editBox:HookScript("OnTextChanged", function(self)
		filter = self:GetText() or ""
		JM.MainFrame:RefreshList()
	end)
	searchHolder.editBox:SetScript("OnEnterPressed", searchHolder.editBox.ClearFocus)
	searchHolder.UpdatePlaceholder()

	-- All / Unread.
	allTab = Skin:CreateButton(parent, 50, 20, "All")
	allTab:SetPoint("TOPLEFT", 6, -32)
	allTab:SetScript("OnClick", function()
		view = "all"
		JM.MainFrame:RefreshList()
	end)
	allTab:SetScript("OnMouseUp", function(self) PaintTab(self, view == "all") end)

	unreadTab = Skin:CreateButton(parent, 90, 20, "Unread")
	unreadTab:SetPoint("LEFT", allTab, "RIGHT", 2, 0)
	unreadTab:SetScript("OnClick", function()
		view = "unread"
		JM.MainFrame:RefreshList()
	end)
	unreadTab:SetScript("OnMouseUp", function(self) PaintTab(self, view == "unread") end)

	listScroll = CreateFrame("ScrollFrame", "JM_ContactScroll", parent, "UIPanelScrollFrameTemplate")
	listScroll:SetPoint("TOPLEFT", 2, -58)
	listScroll:SetPoint("BOTTOMRIGHT", -24, 2)
	Skin:StyleScrollBar(listScroll)

	listContent = CreateFrame("Frame", nil, listScroll)
	listContent:SetSize(100, 20)
	listScroll:SetScrollChild(listContent)
	listScroll:SetScript("OnSizeChanged", function(self, w)
		listContent:SetWidth(w)
	end)

	-- "Sent requests (9)": conversations where only you have spoken (join
	-- whispers nobody answered, mostly), folded away under one row so they
	-- don't bury real conversations. Click to expand; Clear removes them all.
	groupRow = CreateFrame("Button", nil, listContent)
	groupRow:SetHeight(GROUP_HEIGHT)
	local groupBg = groupRow:CreateTexture(nil, "BACKGROUND")
	groupBg:SetAllPoints()
	groupBg:SetTexture(Skin.WHITE)
	groupBg:SetVertexColor(C.panel[1], C.panel[2], C.panel[3], 1)
	local groupHl = groupRow:CreateTexture(nil, "HIGHLIGHT")
	groupHl:SetAllPoints()
	groupHl:SetTexture(Skin.WHITE)
	groupHl:SetVertexColor(1, 1, 1, 0.06)
	groupRow.text = Skin:Heading(groupRow, 11, C.muted)
	groupRow.text:SetPoint("LEFT", 10, 0)
	groupRow:SetScript("OnClick", function()
		WindowDB().sentExpanded = not WindowDB().sentExpanded or nil
		JM.MainFrame:RefreshList()
	end)
	groupRow:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Sent requests", 1, 1, 1)
		GameTooltip:AddLine("Whispers you sent that were never answered. They move back into the main list as soon as the other player replies.", nil, nil, nil, true)
		GameTooltip:Show()
	end)
	groupRow:SetScript("OnLeave", function() GameTooltip:Hide() end)
	groupRow:Hide()

	groupClear = Skin:CreateButton(groupRow, 44, 16, "Clear")
	groupClear:SetPoint("RIGHT", -6, 0)
	groupClear:SetScript("OnClick", function()
		JM.MainFrame:RemoveSentRequests()
	end)
	groupClear:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Clear sent requests", 1, 1, 1)
		GameTooltip:AddLine("Removes every unanswered conversation in this group. You get a few seconds to undo.", nil, nil, nil, true)
		GameTooltip:Show()
	end)
	groupClear:SetScript("OnLeave", function() GameTooltip:Hide() end)

	emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	emptyText:SetPoint("TOP", 0, -84)
	emptyText:SetPoint("LEFT", 10, 0)
	emptyText:SetPoint("RIGHT", -10, 0)
	emptyText:SetTextColor(0.5, 0.5, 0.5)

	newBtn = Skin:CreateButton(parent, 120, 22, "Start new whisper")
	newBtn:SetPoint("TOP", emptyText, "BOTTOM", 0, -10)
	newBtn:SetScript("OnClick", function()
		JM.MainFrame:PromptNewWhisper()
	end)
	newBtn:Hide()

	-- Undo bar: over the bottom of the list for a few seconds after a remove.
	undoBar = CreateFrame("Frame", nil, parent)
	undoBar:SetPoint("BOTTOMLEFT", 2, 2)
	undoBar:SetPoint("BOTTOMRIGHT", -2, 2)
	undoBar:SetHeight(26)
	undoBar:SetFrameLevel(listScroll:GetFrameLevel() + 20)
	Skin:StylePanel(undoBar, 1)
	undoBar:SetBackdropColor(0.122, 0.153, 0.169, 1)
	undoBar:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
	undoBar:EnableMouse(true)
	undoBar:Hide()
	undoBar.text = undoBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	undoBar.text:SetPoint("LEFT", 8, 0)
	undoBar.text:SetPoint("RIGHT", -64, 0)
	undoBar.text:SetJustifyH("LEFT")
	undoBar.text:SetHeight(12)
	local undoBtn = Skin:CreateButton(undoBar, 52, 18, "Undo")
	undoBtn:SetPoint("RIGHT", -4, 0)
	undoBtn:SetScript("OnClick", function()
		JM.MainFrame:UndoRemove()
	end)
	undoBar:SetScript("OnUpdate", function(self)
		local last = JM.Store.lastRemoved
		if not last or (GetTime() - last.at) >= UNDO_SECONDS then
			self:Hide()
		end
	end)
end

function ContactList:Refresh(selectedName)
	if not listContent then
		return
	end
	listContent:SetWidth(listScroll:GetWidth())
	local all = JM.Store:GetSortedConversationList(filter)

	-- What to show. Searching and the Unread view are flat lists; the default
	-- view keeps unanswered sent-only conversations under the group row.
	local main, sent = {}, {}
	local unreadTotal = 0
	for _, entry in ipairs(all) do
		local unread = (entry.convo.unreadCount or 0) > 0
		if unread then
			unreadTotal = unreadTotal + 1
		end
		if view == "unread" then
			if unread then
				table.insert(main, entry)
			end
		elseif filter == "" and JM.Store:IsSentOnly(entry.convo) and entry.name ~= selectedName then
			table.insert(sent, entry)
		else
			table.insert(main, entry)
		end
	end

	unreadTab.text:SetText(unreadTotal > 0 and string.format("Unread (%d)", unreadTotal) or "Unread")
	PaintTab(allTab, view == "all")
	PaintTab(unreadTab, view == "unread")

	local used, y = 0, 0
	local function Place(entry)
		used = used + 1
		local row = rows[used]
		if not row then
			row = CreateRow(listContent)
			rows[used] = row
		end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", listContent, "TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", listContent, "RIGHT", 0, 0)
		FillRow(row, entry, selectedName)
		Skin:StyleRow(row, entry.name == selectedName)
		row:Show()
		y = y + ROW_HEIGHT
	end

	for _, entry in ipairs(main) do
		Place(entry)
	end

	if #sent > 0 then
		local expanded = WindowDB().sentExpanded
		groupRow:ClearAllPoints()
		groupRow:SetPoint("TOPLEFT", listContent, "TOPLEFT", 0, -y)
		groupRow:SetPoint("RIGHT", listContent, "RIGHT", 0, 0)
		groupRow.text:SetText(string.format("%s  SENT REQUESTS (%d)", expanded and "-" or "+", #sent))
		groupRow:Show()
		y = y + GROUP_HEIGHT
		if expanded then
			for _, entry in ipairs(sent) do
				Place(entry)
			end
		end
	else
		groupRow:Hide()
	end

	for i = used + 1, #rows do
		rows[i].name = nil
		rows[i]:Hide()
	end

	listContent:SetHeight(math.max(20, y))

	if #main == 0 and #sent == 0 then
		if filter ~= "" then
			emptyText:SetText("No chats match \"" .. filter .. "\".")
			newBtn:Hide()
		elseif view == "unread" then
			emptyText:SetText("Nothing unread.")
			newBtn:Hide()
		else
			emptyText:SetText("No conversations yet.")
			newBtn:Show()
		end
		emptyText:Show()
	else
		emptyText:Hide()
		newBtn:Hide()
	end

	-- Undo bar.
	local last = JM.Store.lastRemoved
	if last and (GetTime() - last.at) < UNDO_SECONDS then
		if #last.items == 1 then
			undoBar.text:SetText("Removed " .. last.items[1].name .. ".")
		else
			undoBar.text:SetText("Removed " .. #last.items .. " conversations.")
		end
		undoBar:Show()
	else
		undoBar:Hide()
	end

	return #main + #sent
end
