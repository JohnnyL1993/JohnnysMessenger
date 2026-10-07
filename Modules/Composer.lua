-- Reply box at the bottom of the conversation pane: placeholder text,
-- per-conversation drafts, a quick-replies menu, sent-message history on the
-- arrow keys, and a length hint once a message will be split.
JM.Composer = {}
local Composer = JM.Composer
local Skin = JM.Skin

local holder, editBox, counter, currentName

local function SaveDraft()
	if not currentName or not editBox then
		return
	end
	local convo = JM.Store:GetConversation(currentName)
	if convo then
		local text = editBox:GetText()
		convo.draft = (text and text ~= "") and text or nil
	end
end

local function UpdateCounter()
	local len = string.len(editBox:GetText() or "")
	if len > 200 then
		local parts = math.ceil(len / 254)
		counter:SetText(len .. (parts > 1 and (" (" .. parts .. " msgs)") or ""))
		counter:Show()
	else
		counter:Hide()
	end
end

local function Send()
	if not currentName then
		return
	end
	local text = editBox:GetText()
	if text and string.match(text, "%S") then
		JM.Whisper:SendWhisper(currentName, text)
		editBox:AddHistoryLine(text)
		editBox:SetText("")
		SaveDraft()
	end
end

local qrMenuFrame = CreateFrame("Frame", "JM_QuickReplyMenu", UIParent, "UIDropDownMenuTemplate")

local function ShowQuickReplies(anchor)
	local menu = { { text = "Quick replies", isTitle = 1, notCheckable = 1 } }
	for _, reply in ipairs(JM.Settings:Get("quickReplies")) do
		table.insert(menu, { text = reply, notCheckable = 1, func = function()
			editBox:SetText(reply)
			editBox:SetFocus()
			editBox:SetCursorPosition(string.len(reply))
		end })
	end
	if #menu == 1 then
		table.insert(menu, { text = "None set - add some in Settings", notCheckable = 1, disabled = 1 })
	end
	table.insert(menu, { text = CANCEL or "Cancel", notCheckable = 1 })
	EasyMenu(menu, qrMenuFrame, anchor, 0, 0, "MENU")
end

function Composer:Build(parent)
	holder = Skin:CreateEditBox(parent, 100, 28)
	editBox = holder.editBox
	editBox:SetAltArrowKeyMode(false) -- plain Up/Down walk sent-message history
	editBox:SetHistoryLines(32)

	local sendBtn = Skin:CreateButton(parent, 60, 28, "Send")
	sendBtn:SetPoint("BOTTOMRIGHT", -10, 10)
	sendBtn:SetScript("OnClick", Send)

	local qrBtn = Skin:CreateButton(parent, 54, 28, "Quick")
	qrBtn:SetPoint("RIGHT", sendBtn, "LEFT", -6, 0)
	qrBtn:SetScript("OnClick", function(self)
		ShowQuickReplies(self)
	end)
	qrBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Quick replies")
		GameTooltip:AddLine("Edit the list in Settings.", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	qrBtn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	holder:SetPoint("BOTTOMLEFT", 10, 10)
	holder:SetPoint("RIGHT", qrBtn, "LEFT", -6, 0)

	counter = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	counter:SetPoint("BOTTOMRIGHT", holder, "TOPRIGHT", 0, 2)
	counter:SetTextColor(0.6, 0.6, 0.6)
	counter:Hide()

	editBox:SetScript("OnEnterPressed", function(self)
		Send()
		self:ClearFocus()
	end)
	editBox:HookScript("OnTextChanged", function(self, userInput)
		UpdateCounter()
		if userInput then
			SaveDraft()
		end
	end)
	editBox:HookScript("OnEditFocusLost", function()
		SaveDraft()
	end)

	return holder
end

-- Switches the box to another conversation, stashing the old one's draft.
function Composer:SetConversation(name)
	if name == currentName then
		return
	end
	SaveDraft()
	currentName = name
	local convo = name and JM.Store:GetConversation(name)
	editBox:SetText(convo and convo.draft or "")
	holder.placeholder:SetText(name and ("Message " .. name .. "...") or "")
	holder.UpdatePlaceholder()
	UpdateCounter()
end

function Composer:Focus()
	if editBox then
		editBox:SetFocus()
	end
end

function Composer:HasFocus()
	return editBox and editBox:HasFocus()
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
