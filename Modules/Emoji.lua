-- Emojis. WoW's fonts can't draw real emojis, so they travel as the classic
-- text codes - :)  :D  <3 and friends - which is what anyone without
-- Messenger sees. Messenger shows those codes as little icons (Media\Emoji)
-- in the conversation and the list previews, on both your side and theirs.
-- The smiley button by the reply box opens a picker that types the code.
JM.Emoji = {}
local Emoji = JM.Emoji
local Skin = JM.Skin

local PATH = "Interface\\AddOns\\JohnnysMessenger\\Media\\Emoji\\"

-- In picker order. The first code is the one the picker inserts.
Emoji.LIST = {
	{ file = "smile", codes = { ":)", ":-)", "=)" } },
	{ file = "grin", codes = { ":D", ":-D", "=D" } },
	{ file = "laugh", codes = { "xD", "XD" } },
	{ file = "wink", codes = { ";)", ";-)" } },
	{ file = "tongue", codes = { ":P", ":p", ":-P", ":-p" } },
	{ file = "cool", codes = { "B)", "B-)" } },
	{ file = "surprised", codes = { ":O", ":o", ":-O", ":-o" } },
	{ file = "sad", codes = { ":(", ":-(" } },
	{ file = "cry", codes = { ":'(" } },
	{ file = "angry", codes = { ">:(" } },
	{ file = "heart", codes = { "<3" } },
	{ file = "thumbsup", codes = { "(y)", "(Y)" } },
}

local fileByCode = {}
for _, e in ipairs(Emoji.LIST) do
	for _, code in ipairs(e.codes) do
		fileByCode[code] = e.file
	end
end

-- "|T...:0|t" sizes to the font's line height, which draws noticeably
-- smaller than the letters, so icons get an explicit size instead (1.5x
-- the font size), nudged down to sit on the text line.
local markupCache = {}
local function Markup(file, size)
	local key = file .. size
	local m = markupCache[key]
	if not m then
		m = "|T" .. PATH .. file .. ":" .. size .. ":" .. size .. ":0:-2|t"
		markupCache[key] = m
	end
	return m
end

-- Swaps standalone emoji codes for their icons. Words containing a "|" are
-- left alone, so links, colour codes and clickable URLs are never touched.
-- size is the icon's pixel size; it defaults to 1.5x the message font size.
function Emoji:Render(text, size)
	if not text or text == "" then
		return text
	end
	size = math.floor(size or (((JM.Settings.db and JM.Settings.db.fontSize) or 12) * 1.5))
	return (string.gsub(text, "%S+", function(word)
		if not string.find(word, "|", 1, true) then
			local file = fileByCode[word]
			if file then
				return Markup(file, size)
			end
		end
	end))
end

--------------------------------------
--   Picker                         --
--------------------------------------

local picker
local COLS, CELL = 6, 26

local function BuildPicker()
	picker = CreateFrame("Frame", "JM_EmojiPicker", UIParent)
	picker:SetFrameStrata("FULLSCREEN_DIALOG")
	picker:SetClampedToScreen(true)
	local rowsCount = math.ceil(#Emoji.LIST / COLS)
	picker:SetSize(COLS * CELL + 10, rowsCount * CELL + 10)
	Skin:StylePanel(picker, 0.97)
	picker:EnableMouse(true)
	picker:Hide()
	for i, e in ipairs(Emoji.LIST) do
		local btn = CreateFrame("Button", nil, picker)
		btn:SetSize(CELL - 2, CELL - 2)
		local col = (i - 1) % COLS
		local row = math.floor((i - 1) / COLS)
		btn:SetPoint("TOPLEFT", 5 + col * CELL, -5 - row * CELL)
		local tex = btn:CreateTexture(nil, "ARTWORK")
		tex:SetPoint("CENTER")
		tex:SetSize(20, 20)
		tex:SetTexture(PATH .. e.file)
		local hl = btn:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetTexture(Skin.WHITE)
		hl:SetVertexColor(1, 1, 1, 0.12)
		btn:SetScript("OnClick", function()
			if picker.onPick then
				picker.onPick(e.codes[1])
			end
			picker:Hide()
		end)
		btn:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(table.concat(e.codes, "  "), 1, 1, 1)
			GameTooltip:AddLine("Others without Messenger see the text.", 0.7, 0.7, 0.7)
			GameTooltip:Show()
		end)
		btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
end

-- Opens the picker above `anchor`; onPick(code) gets the chosen code. A
-- second call while it's open closes it.
function Emoji:TogglePicker(anchor, onPick)
	if not picker then
		BuildPicker()
	end
	if picker:IsShown() then
		picker:Hide()
		return
	end
	picker.onPick = onPick
	picker:ClearAllPoints()
	picker:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 4)
	picker:Show()
end

function Emoji:HidePicker()
	if picker then
		picker:Hide()
	end
end

function Emoji:IsPickerOver()
	return picker and picker:IsShown() and MouseIsOver(picker)
end
