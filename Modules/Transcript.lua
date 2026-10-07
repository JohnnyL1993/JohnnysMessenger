-- The open thread, drawn as WhisperMessenger-style chat bubbles: theirs on the
-- left, yours on the right, consecutive messages grouped under one sender
-- label, with date separators and a "New messages" divider.
--
-- Each bubble's text lives in its own small ScrollingMessageFrame rather than
-- a FontString. On this client only SMF reliably delivers OnHyperlinkClick
-- for item/spell/achievement links (SimpleHTML silently failed to parse them -
-- see the 1.0 notes), so bubbles keep links clickable. A hidden FontString
-- measures each message first so the SMF can be sized to fit it exactly.
JM.Transcript = {}
local Transcript = JM.Transcript
local Skin = JM.Skin

local PAD_X, PAD_Y = 10, 6 -- text padding inside a bubble
local SIDE = 10 -- gap between bubbles and the pane edge
local GAP_IN_GROUP, GAP_GROUP = 3, 10
local GROUP_WINDOW = 120 -- seconds; WhisperMessenger's grouping threshold
local MAX_WIDTH_FRAC = 0.75

local INCOMING_BG = { 0.12, 0.12, 0.12, 0.95 }
local OUTGOING_BG = { 0.24, 0.24, 0.24, 0.95 }
local URL_COLOR = "9ecfff"

local scroll, content, measureNat, measureWrap
local bubblePool, labelPool, sepPool, systemPool = {}, {}, {}, {}
local used = { bubble = 0, label = 0, sep = 0, system = 0 }

--------------------------------------
--   Text helpers                   --
--------------------------------------

-- WhisperMessenger-style clickable URLs. Messages that already contain game
-- hyperlinks are left alone so a link's own |H...|h text is never mangled.
local function Linkify(msg)
	if string.find(msg, "|H", 1, true) then
		return msg
	end
	return (string.gsub(msg, "%S+", function(word)
		if string.find(word, "^https?://") or string.find(word, "^www%.") then
			return "|cff" .. URL_COLOR .. "|Hjmurl:" .. word .. "|h" .. word .. "|h|r"
		end
	end))
end

local function DayKey(t)
	return date("%Y%m%d", t)
end

local function DayLabel(t)
	local today = DayKey(time())
	local key = DayKey(t)
	if key == today then
		return "Today"
	elseif key == DayKey(time() - 86400) then
		return "Yesterday"
	end
	return date("%B ", t) .. tonumber(date("%d", t)) .. date(", %Y", t)
end

function Transcript.FormatTime(t)
	if JM.Settings:Get("use24h") then
		return date("%H:%M", t)
	end
	return (string.gsub(date("%I:%M %p", t), "^0", ""))
end

--------------------------------------
--   Copy popup                     --
--------------------------------------

StaticPopupDialogs["JM_COPY_TEXT"] = {
	text = "Press Ctrl+C to copy:",
	button1 = CLOSE or "Close",
	hasEditBox = 1,
	hasWideEditBox = 1,
	maxLetters = 1024,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
	EditBoxOnEscapePressed = function(self)
		self:GetParent():Hide()
	end,
	EditBoxOnEnterPressed = function(self)
		self:GetParent():Hide()
	end,
}

function Transcript.ShowCopyPopup(text)
	local dialog = StaticPopup_Show("JM_COPY_TEXT")
	if not dialog then
		return
	end
	-- 3.3.5a's StaticPopup names its edit box "<dialog>WideEditBox" when
	-- hasWideEditBox is set, else "<dialog>EditBox".
	local edit = _G[dialog:GetName() .. "WideEditBox"] or _G[dialog:GetName() .. "EditBox"]
	if edit then
		edit:SetText(text or "")
		edit:SetFocus()
		edit:HighlightText()
	end
end

--------------------------------------
--   Hyperlinks                     --
--------------------------------------

local TOOLTIP_LINKS = { item = true, spell = true, enchant = true, achievement = true, quest = true, talent = true, glyph = true }

local function OnHyperlinkClick(self, link, text, button)
	local url = string.match(link, "^jmurl:(.+)$")
	if url then
		Transcript.ShowCopyPopup(url)
		return
	end
	-- SetItemRef is what ChatFrame_OnHyperlinkShow forwards to; calling it
	-- directly sidesteps that wrapper's signature differing between clients.
	SetItemRef(link, text, button, DEFAULT_CHAT_FRAME)
end

local function OnHyperlinkEnter(self, link)
	local linkType = string.match(link, "^(%a+):")
	if linkType and TOOLTIP_LINKS[linkType] then
		GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
		GameTooltip:SetHyperlink(link)
		GameTooltip:Show()
	end
end

local function OnHyperlinkLeave()
	GameTooltip:Hide()
end

--------------------------------------
--   Pools                          --
--------------------------------------

local copyMenuFrame = CreateFrame("Frame", "JM_BubbleMenu", UIParent, "UIDropDownMenuTemplate")

local function ShowBubbleMenu(bubble)
	local raw = bubble.rawText
	EasyMenu({
		{ text = "Copy text", notCheckable = 1, func = function() Transcript.ShowCopyPopup(raw) end },
		{ text = CANCEL or "Cancel", notCheckable = 1 },
	}, copyMenuFrame, "cursor", 0, 0, "MENU")
end

local function AcquireBubble()
	used.bubble = used.bubble + 1
	local b = bubblePool[used.bubble]
	if not b then
		b = CreateFrame("Frame", nil, content)
		b:SetBackdrop({ bgFile = Skin.WHITE })

		local smf = CreateFrame("ScrollingMessageFrame", nil, b)
		smf:SetPoint("TOPLEFT", PAD_X, -PAD_Y)
		smf:SetFontObject(JM_MessageFont)
		smf:SetJustifyH("LEFT")
		smf:SetFading(false)
		smf:SetMaxLines(8)
		if smf.SetIndentedWordWrap then
			smf:SetIndentedWordWrap(false)
		end
		smf:EnableMouse(true)
		smf:SetScript("OnHyperlinkClick", OnHyperlinkClick)
		smf:SetScript("OnHyperlinkEnter", OnHyperlinkEnter)
		smf:SetScript("OnHyperlinkLeave", OnHyperlinkLeave)
		smf:SetScript("OnMouseUp", function(self, button)
			if button == "RightButton" then
				ShowBubbleMenu(b)
			end
		end)
		b.smf = smf
		bubblePool[used.bubble] = b
	end
	b:ClearAllPoints()
	b:Show()
	return b
end

local function AcquireLabel()
	used.label = used.label + 1
	local fs = labelPool[used.label]
	if not fs then
		fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		labelPool[used.label] = fs
	end
	fs:ClearAllPoints()
	fs:Show()
	return fs
end

local function AcquireSystem()
	used.system = used.system + 1
	local fs = systemPool[used.system]
	if not fs then
		fs = content:CreateFontString(nil, "OVERLAY")
		fs:SetFontObject(JM_MessageFont)
		fs:SetJustifyH("CENTER")
		fs:SetTextColor(0.6, 0.6, 0.6)
		systemPool[used.system] = fs
	end
	fs:ClearAllPoints()
	fs:Show()
	return fs
end

-- Centered text with a hairline either side ("—— Today ——").
local function AcquireSeparator()
	used.sep = used.sep + 1
	local s = sepPool[used.sep]
	if not s then
		s = CreateFrame("Frame", nil, content)
		s:SetHeight(20)
		s.text = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		s.text:SetPoint("CENTER")
		s.left = s:CreateTexture(nil, "ARTWORK")
		s.left:SetTexture(Skin.WHITE)
		s.left:SetHeight(1)
		s.left:SetPoint("LEFT", 10, 0)
		s.left:SetPoint("RIGHT", s.text, "LEFT", -8, 0)
		s.right = s:CreateTexture(nil, "ARTWORK")
		s.right:SetTexture(Skin.WHITE)
		s.right:SetHeight(1)
		s.right:SetPoint("LEFT", s.text, "RIGHT", 8, 0)
		s.right:SetPoint("RIGHT", -10, 0)
		sepPool[used.sep] = s
	end
	s:ClearAllPoints()
	s:Show()
	return s
end

local function ReleaseAll()
	for _, pool in pairs({ bubble = bubblePool, label = labelPool, sep = sepPool, system = systemPool }) do
		for _, obj in ipairs(pool) do
			obj:Hide()
		end
	end
	used.bubble, used.label, used.sep, used.system = 0, 0, 0, 0
end

--------------------------------------
--   Build / render                 --
--------------------------------------

function Transcript:Build(parent)
	scroll = CreateFrame("ScrollFrame", "JM_TranscriptScroll", parent, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 2, -2)
	scroll:SetPoint("BOTTOMRIGHT", -24, 2)

	content = CreateFrame("Frame", nil, scroll)
	content:SetSize(300, 20)
	scroll:SetScrollChild(content)

	-- Off-screen measuring strings, kept shown (alpha 0) because some clients
	-- report 0 height for strings on hidden frames.
	local measurer = CreateFrame("Frame", nil, UIParent)
	measurer:SetSize(1, 1)
	measurer:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -5000, 5000)
	measurer:SetAlpha(0)
	measureNat = measurer:CreateFontString(nil, "OVERLAY")
	measureNat:SetFontObject(JM_MessageFont)
	measureNat:SetPoint("TOPLEFT")
	measureWrap = measurer:CreateFontString(nil, "OVERLAY")
	measureWrap:SetFontObject(JM_MessageFont)
	measureWrap:SetPoint("TOPLEFT")
	measureWrap:SetJustifyH("LEFT")

	return scroll
end

local function Measure(text, maxInner)
	measureNat:SetText(text)
	local natural = measureNat:GetStringWidth()
	if natural <= maxInner then
		return math.ceil(natural), math.ceil(measureNat:GetStringHeight())
	end
	measureWrap:SetWidth(maxInner)
	measureWrap:SetText(text)
	return maxInner, math.ceil(measureWrap:GetStringHeight())
end

function Transcript:IsAtBottom()
	if not scroll then
		return true
	end
	return scroll:GetVerticalScrollRange() - scroll:GetVerticalScroll() < 6
end

function Transcript:ScrollToBottom()
	-- The scroll range only catches up with a new child height after layout,
	-- so set it now and once more on the next frame.
	scroll:UpdateScrollChildRect()
	scroll:SetVerticalScroll(scroll:GetVerticalScrollRange())
	JM.Timer:After(0.01, function()
		scroll:UpdateScrollChildRect()
		scroll:SetVerticalScroll(scroll:GetVerticalScrollRange())
	end)
end

-- opts.dividerTime: draw "New messages" before the first incoming message
-- newer than this. opts.forceBottom: always end scrolled to the newest line.
function Transcript:Render(name, convo, opts)
	opts = opts or {}
	local wasAtBottom = opts.forceBottom or self:IsAtBottom()
	ReleaseAll()

	local width = math.max(100, scroll:GetWidth())
	content:SetWidth(width)
	if not convo then
		content:SetHeight(20)
		return
	end

	local maxInner = math.floor(width * MAX_WIDTH_FRAC) - PAD_X * 2
	local myName = UnitName("player")
	local myClass = JM.ClassColor:GetMyEnglishClass()
	local y = 8
	local prev, prevDay, dividerPlaced

	for _, m in ipairs(convo.messages) do
		local day = DayKey(m.time)
		local breakGroup = false

		if day ~= prevDay then
			local s = AcquireSeparator()
			s:SetPoint("TOPLEFT", 0, -y)
			s:SetPoint("RIGHT", content, "RIGHT", 0, 0)
			s.text:SetText(DayLabel(m.time))
			s.text:SetTextColor(0.6, 0.6, 0.6)
			s.left:SetVertexColor(1, 1, 1, 0.1)
			s.right:SetVertexColor(1, 1, 1, 0.1)
			y = y + 24
			prevDay = day
			breakGroup = true
		end

		if opts.dividerTime and not dividerPlaced and m.inbound and m.time > opts.dividerTime then
			local s = AcquireSeparator()
			s:SetPoint("TOPLEFT", 0, -y)
			s:SetPoint("RIGHT", content, "RIGHT", 0, 0)
			s.text:SetText("New messages")
			s.text:SetTextColor(1, 1, 1)
			s.left:SetVertexColor(1, 1, 1, 0.6)
			s.right:SetVertexColor(1, 1, 1, 0.6)
			y = y + 24
			dividerPlaced = true
			breakGroup = true
		end

		if m.kind == "system" then
			local fs = AcquireSystem()
			fs:SetWidth(width - 40)
			fs:SetText(m.msg)
			fs:SetPoint("TOP", content, "TOP", 0, -y)
			y = y + math.ceil(fs:GetStringHeight()) + 8
			prev = nil
		else
			local newGroup = breakGroup or not prev or prev.inbound ~= m.inbound or (m.time - prev.time) > GROUP_WINDOW
			if newGroup then
				if prev then
					y = y + GAP_GROUP
				end
				local label = AcquireLabel()
				if m.inbound then
					label:SetText(JM.ClassColor:ColorName(name, m.class or convo.class) .. "  |cff808080" .. Transcript.FormatTime(m.time) .. "|r")
					label:SetPoint("TOPLEFT", SIDE, -y)
				else
					label:SetText("|cff808080" .. Transcript.FormatTime(m.time) .. "|r  " .. JM.ClassColor:ColorName(myName, myClass))
					label:SetPoint("TOPRIGHT", -SIDE, -y)
				end
				y = y + 16
			else
				y = y + GAP_IN_GROUP
			end

			local text = Linkify(m.msg)
			local textW, textH = Measure(text, maxInner)
			local b = AcquireBubble()
			b.rawText = m.msg
			-- A little slack so the SMF never wraps one line earlier than the
			-- measuring FontString did (which would clip the top line).
			b.smf:SetSize(textW + 4, textH + 2)
			b:SetSize(textW + 4 + PAD_X * 2, textH + 2 + PAD_Y * 2)
			local bg = m.inbound and INCOMING_BG or OUTGOING_BG
			b:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
			if m.inbound then
				b:SetPoint("TOPLEFT", SIDE, -y)
			else
				b:SetPoint("TOPRIGHT", -SIDE, -y)
			end
			b.smf:Clear()
			b.smf:AddMessage(text, 1, 1, 1)
			y = y + b:GetHeight()
			prev = m
		end
	end

	content:SetHeight(y + 8)
	if wasAtBottom then
		self:ScrollToBottom()
	end
end
