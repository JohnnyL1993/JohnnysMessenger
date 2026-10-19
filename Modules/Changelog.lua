-- Changelog window, opened from the "Changelog" button in Settings
-- (Modules\Settings.lua). Lists what changed in each version,
-- newest first. Versions newer than the one you last opened this window on
-- are tagged NEW, so after an update the fresh entries stand out.
--
-- To add a release: put a new { version =, changes = { ... }, fixes = { ... } }
-- block at the TOP of ENTRIES and bump "## Version" in the .toc to match.
-- `changes` is what's new, `fixes` (optional) is bugs fixed - shown under
-- their own "Changes" / "Bug fixes" sub-headings.
local NS = JM
NS.Changelog = {}
local Changelog = NS.Changelog
local Skin = NS.Skin

local ENTRIES = {
	{
		version = "2.4",
		changes = {
			"Emojis: a smiley button next to the reply box. They're sent as :) :D <3 and so on, so anyone without Messenger sees the text; Messenger shows them as icons for you and anyone else using it.",
			"Keep typing after sending: the reply box stays active until you press Esc or click outside the window. Can be turned off in Settings.",
			"Search now looks inside messages as well as names, and shows the line it found.",
			"Friend and Ignore buttons in the conversation header. Click Friend again to remove them from your friends list; Ignore and remove both ask first.",
			"History: conversations open on today's messages only; older ones sit behind a \"History\" bar at the top of the thread, one click to show or hide. Can be turned off in Settings.",
			"\"Delete all but today\" in Settings clears older history in one go.",
			"As many quick replies as you like: \"+ Add another\" adds a row, X removes one. \"Edit quick replies...\" at the bottom of the Quick menu jumps there.",
			"Sent requests have their own tab (All / Unread / Sent).",
			"Whisper sound: pick the WoW whisper, the new Messenger chime, or any shared sound from your other addons (ElvUI's \"Whisper Alert\" included), with a Test button.",
			"No whisper sound while the Messenger window is open (tick \"...even while the window is open\" to keep it).",
			"Whispering someone from chat (/w, /r) opens their conversation in Messenger - never in combat. Can be turned off in Settings.",
			"Hide in combat leaves the window open if you're typing a reply (can be turned off in Settings).",
			"On a narrow window the Ignore / Add friend / Invite buttons move to their own row under the name instead of covering it.",
			"Changelog and Report a bug / request buttons in Settings.",
		},
		fixes = {
			"The whisper sound was silent unless whispers were hidden from chat; it now always plays, even with game sound effects turned off.",
			"Online status stuck on \"online\": for people who aren't friends, guild or group, a whisper now only counts for 5 minutes, and friend log-in/log-out notices update the dot straight away.",
			"Opening a sent request (or typing in one) moved it into the main list.",
			"Emojis drew smaller than the text, and messages full of them spilled out of their bubble.",
			"Clicking outside the window didn't leave the search box.",
			"The resize corner jumped the window bigger on the first click; it now follows the mouse from where you grabbed it.",
			"The Window scale slider only went to 75% or 150%; the new scale now applies when you let go.",
		},
	},
	{
		version = "2.3",
		changes = {
			"Conversations where only you have spoken are folded under \"Sent requests\", with Clear to remove them all at once.",
			"All / Unread tabs above the conversation list.",
			"Pin and Remove buttons on the selected conversation, and an Undo bar after removing.",
			"With nothing selected, the right side lists unread (or recent) conversations to open in one click.",
		},
	},
	{
		version = "2.2",
		changes = {
			"New blue-black \"workshop\" look with a lime accent.",
			"Update checks from all of Johnny's addons share one slow queue, so logging in with several no longer trips the chat mute.",
		},
	},
	{
		version = "2.1.1",
		changes = {
			"Rounded message bubbles.",
			"Fixed bubbles that sometimes showed up empty.",
		},
	},
	{
		version = "2.1",
		changes = {
			"In-game \"Update available\" notice when someone with a newer version is seen. /jm version shows your version.",
		},
	},
	{
		version = "2.0",
		changes = {
			"Redesign: chat bubbles with day separators and a \"New messages\" line, clickable item and web links, and copy text.",
			"Conversation list with class icons, online dots, previews and drafts, unread counts, search and a right-click menu (pin, mute, mark unread, remove).",
			"Reply box with per-conversation drafts, quick replies and sent-message history; resizable window; settings page.",
		},
	},
}

local FRAME_W, FRAME_H = 460, 440
local PAD = 14

local frame

-- "1.10" > "1.9": compares dot-separated numbers, not text.
local function VersionNewer(a, b)
	local pa, pb = {}, {}
	for n in string.gmatch(tostring(a or ""), "%d+") do
		table.insert(pa, tonumber(n))
	end
	for n in string.gmatch(tostring(b or ""), "%d+") do
		table.insert(pb, tonumber(n))
	end
	for i = 1, math.max(#pa, #pb) do
		local x, y = pa[i] or 0, pb[i] or 0
		if x ~= y then
			return x > y
		end
	end
	return false
end

local function InstalledVersion()
	return GetAddOnMetadata("JohnnysMessenger", "Version") or "0"
end

-- True while there are entries the player hasn't opened the changelog on yet
-- (drives the "new" marker on the Cfg panel's button).
function Changelog:HasUnseen()
	local seen = NS.db and NS.db.changelogSeenVersion
	return VersionNewer(InstalledVersion(), seen or "0")
end

local function Build()
	local C = Skin.C
	frame = CreateFrame("Frame", "JM_Changelog", UIParent)
	frame:SetSize(FRAME_W, FRAME_H)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	Skin:StylePanel(frame, 0.97)
	frame:Hide()
	table.insert(UISpecialFrames, "JM_Changelog") -- Esc closes it

	local title = Skin:AddHeader(frame, "Changelog")
	local sub = Skin:Heading(frame, 12, C.muted)
	sub:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 10, 1)
	sub:SetText("JOHNNY'S MESSENGER  /  INSTALLED " .. InstalledVersion())

	local close = Skin:CreateButton(frame, 20, 20, "X")
	close:SetPoint("TOPRIGHT", -4, -4)
	close:SetScript("OnClick", function() frame:Hide() end)

	local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("BOTTOMLEFT", PAD, 8)
	hint:SetText("Mouse wheel to scroll - newest first.")

	local scroll = CreateFrame("ScrollFrame", nil, frame)
	scroll:SetPoint("TOPLEFT", PAD, -(Skin.HEADER_HEIGHT + 10))
	scroll:SetPoint("BOTTOMRIGHT", -PAD, 30)
	scroll:EnableMouseWheel(true)

	local content = CreateFrame("Frame", nil, scroll)
	local contentW = FRAME_W - PAD * 2
	content:SetWidth(contentW)
	content:SetHeight(10)
	scroll:SetScrollChild(content)

	-- Never shown: no width set, so GetStringWidth gives an entry's full
	-- unwrapped width (see the height calculation below).
	local measure = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	measure:Hide()
	local LINE_H = 13

	local installed = InstalledVersion()
	local seen = (NS.db and NS.db.changelogSeenVersion) or "0"
	local y = 0
	for _, entry in ipairs(ENTRIES) do
		local head = Skin:Heading(content, 15, C.accent)
		head:SetPoint("TOPLEFT", 0, -y)
		head:SetText("VERSION " .. entry.version)

		local tag
		if VersionNewer(entry.version, installed) then
			tag = "NOT RELEASED YET"
		elseif entry.version == installed then
			tag = VersionNewer(entry.version, seen) and "NEW  -  THIS VERSION" or "THIS VERSION"
		elseif VersionNewer(entry.version, seen) then
			tag = "NEW"
		end
		if tag then
			local tagText = Skin:Heading(content, 11, C.muted)
			tagText:SetPoint("BOTTOMLEFT", head, "BOTTOMRIGHT", 10, 1)
			tagText:SetText(tag)
			if string.find(tag, "NEW", 1, true) == 1 then
				tagText:SetTextColor(1, 0.85, 0.40)
			end
		end
		y = y + 22

		-- Changes first, then bug fixes. The two sub-headings only appear on a
		-- version that has fixes; one with changes alone is a plain list.
		local hasFixes = entry.fixes and #entry.fixes > 0
		local sections = {
			{ label = "CHANGES", items = entry.changes or {} },
			{ label = "BUG FIXES", items = entry.fixes or {} },
		}
		for _, section in ipairs(sections) do
			if #section.items > 0 then
				if hasFixes then
					local subHead = Skin:Heading(content, 11, C.muted)
					subHead:SetPoint("TOPLEFT", 2, -y)
					subHead:SetText(section.label)
					y = y + 16
				end

				for _, change in ipairs(section.items) do
					local dot = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
					dot:SetPoint("TOPLEFT", 2, -y)
					dot:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
					dot:SetText("-")

					local line = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
					line:SetPoint("TOPLEFT", 14, -y)
					line:SetWidth(contentW - 18)
					line:SetJustifyH("LEFT")
					line:SetJustifyV("TOP")
					line:SetTextColor(C.text[1], C.text[2], C.text[3])
					line:SetText(change)
					-- GetHeight can report one line for text that only just
					-- wraps onto a second, which made the next entry overlap
					-- it. Cross-check against the text's unwrapped width (with
					-- some slack, since word wrap breaks early) and take the
					-- taller of the two.
					measure:SetText(change)
					local wrapLines = math.ceil(measure:GetStringWidth() / ((contentW - 18) * 0.93))
					y = y + math.max(12, line:GetHeight(), wrapLines * LINE_H) + 6
				end

				if hasFixes then
					y = y + 4
				end
			end
		end

		local rule = Skin:Solid(content, "ARTWORK", C.rule)
		rule:SetPoint("TOPLEFT", 0, -(y + 4))
		rule:SetPoint("TOPRIGHT", 0, -(y + 4))
		rule:SetHeight(1)
		y = y + 16
	end
	content:SetHeight(y)

	scroll:SetScript("OnMouseWheel", function(self, delta)
		local maxScroll = math.max(0, content:GetHeight() - self:GetHeight())
		local target = self:GetVerticalScroll() - delta * 40
		self:SetVerticalScroll(math.max(0, math.min(maxScroll, target)))
	end)
end

-- Docks the window beside the Messenger window, tops level, so the two never
-- overlap: on its left if there's room, otherwise on its right (past the lockouts
-- panel docked there). Only if neither side has room - or Raid
-- Comp is closed - does it fall back to the middle of the screen.
local function Place()
	local comp = _G["JM_MainFrame"]
	frame:ClearAllPoints()
	if comp and comp:IsShown() and comp:GetLeft() then
		-- Everything in real screen pixels, since the windows can be scaled.
		local need = (FRAME_W + 6) * frame:GetEffectiveScale()
		local compScale = comp:GetEffectiveScale()
		if comp:GetLeft() * compScale >= need then
			frame:SetPoint("TOPRIGHT", comp, "TOPLEFT", -6, 0)
			return
		end

		local edge, edgeScale = comp, compScale
		local spam = nil
		if spam and spam:IsShown() and spam:GetRight()
			and spam:GetRight() * spam:GetEffectiveScale() > comp:GetRight() * compScale then
			edge, edgeScale = spam, spam:GetEffectiveScale()
		end
		local screenRight = UIParent:GetRight() * UIParent:GetEffectiveScale()
		if screenRight - edge:GetRight() * edgeScale >= need then
			frame:SetPoint("TOPLEFT", edge, "TOPRIGHT", 6, 0)
			return
		end
	end
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end

local function Open()
	if not frame then
		Build()
	end
	Place()
	frame:Show()
	-- Everything up to the installed version now counts as seen. The NEW
	-- tags were painted when the window was built, so they stay up for the
	-- rest of this session.
	NS.db.changelogSeenVersion = InstalledVersion()
end

function Changelog:Toggle()
	if frame and frame:IsShown() then
		frame:Hide()
	else
		Open()
	end
end

-- Called when the Messenger window opens: pops the changelog up beside it
-- once per update, until it has been looked at.
function Changelog:ShowIfUnseen()
	if self:HasUnseen() then
		Open()
	end
end

-- Called when the Messenger window closes, so the changelog doesn't stay
-- behind on its own.
function Changelog:Hide()
	if frame then
		frame:Hide()
	end
end
