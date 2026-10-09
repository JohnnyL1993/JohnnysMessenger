-- Left pane: search box + conversation rows (pooled rows in a scrollframe,
-- the same list pattern as 1.0). Row layout follows WhisperMessenger: class
-- icon with a presence dot, class-colored name, relative time, a preview
-- line (or "Draft: ..."), and an unread badge; pinned rows sort first.
JM.ContactList = {}
local ContactList = JM.ContactList
local Skin = JM.Skin

local ROW_HEIGHT = 46
local ICON_SIZE = 28

local listScroll, listContent, searchHolder, emptyText, newBtn
local rows = {}
local filter = ""

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

	local previewText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	previewText:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, 1)
	previewText:SetPoint("RIGHT", badge, "LEFT", -4, 0)
	previewText:SetJustifyH("LEFT")
	previewText:SetHeight(12)
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
	row.previewText:SetText(Truncate(preview or "", 60))
	row.previewText:SetTextColor(0.6, 0.6, 0.6)

	row.badge:SetCount(convo.unreadCount)
	-- Unread rows get a brighter preview so they stand out without color.
	if (convo.unreadCount or 0) > 0 then
		row.previewText:SetTextColor(0.9, 0.9, 0.9)
	end
end

--------------------------------------
--   Build / refresh                --
--------------------------------------

function ContactList:Build(parent)
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

	listScroll = CreateFrame("ScrollFrame", "JM_ContactScroll", parent, "UIPanelScrollFrameTemplate")
	listScroll:SetPoint("TOPLEFT", 2, -34)
	listScroll:SetPoint("BOTTOMRIGHT", -24, 2)

	listContent = CreateFrame("Frame", nil, listScroll)
	listContent:SetSize(100, 20)
	listScroll:SetScrollChild(listContent)
	listScroll:SetScript("OnSizeChanged", function(self, w)
		listContent:SetWidth(w)
	end)

	emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	emptyText:SetPoint("TOP", 0, -60)
	emptyText:SetPoint("LEFT", 10, 0)
	emptyText:SetPoint("RIGHT", -10, 0)
	emptyText:SetTextColor(0.5, 0.5, 0.5)

	newBtn = Skin:CreateButton(parent, 120, 22, "Start new whisper")
	newBtn:SetPoint("TOP", emptyText, "BOTTOM", 0, -10)
	newBtn:SetScript("OnClick", function()
		JM.MainFrame:PromptNewWhisper()
	end)
	newBtn:Hide()
end

function ContactList:Refresh(selectedName)
	if not listContent then
		return
	end
	listContent:SetWidth(listScroll:GetWidth())
	local list = JM.Store:GetSortedConversationList(filter)

	for i, entry in ipairs(list) do
		local row = rows[i]
		if not row then
			row = CreateRow(listContent)
			row:SetPoint("TOPLEFT", listContent, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
			row:SetPoint("RIGHT", listContent, "RIGHT", 0, 0)
			rows[i] = row
		end
		FillRow(row, entry, selectedName)
		Skin:StyleRow(row, entry.name == selectedName)
		row:Show()
	end

	for i = #list + 1, #rows do
		rows[i].name = nil
		rows[i]:Hide()
	end

	listContent:SetHeight(math.max(20, #list * ROW_HEIGHT))

	if #list == 0 then
		if filter ~= "" then
			emptyText:SetText("No chats match \"" .. filter .. "\".")
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
	return #list
end
