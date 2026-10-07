-- In-game "update available" notice, ported from Johnny's Raid Comp
-- (Modules\VersionCheck.lua there - same design, same shared channel).
--
-- WoW can't reach the internet, so there's no way to ask GitHub what the
-- latest release is. Instead every copy of the addon announces its own TOC
-- version to other players running it, and any client that hears a higher
-- version than its own shows a gold "Update available" notice in place of
-- the messenger window's title - no pop-up. Clicking it opens a copyable
-- link to the GitHub Releases page.
--
-- Transport: Warmane blocks SendAddonMessage on public channels, so the
-- server-wide leg is a hidden temporary chat channel (shared with the other
-- Johnny's addons) carrying plain SendChatMessage lines tagged
-- "JMV:<version>", with a chat filter hiding those lines (and the channel's
-- join/leave notices) from every chat frame. SendAddonMessage still works for
-- GUILD / RAID / PARTY, so those use it.
--
-- Sends are kept rare so the channel never looks like spam: once on the
-- channel after joining, once to guild at login, to the group on roster
-- changes (throttled), and a single delayed reply when we hear someone on an
-- older version. The highest version heard is saved in JM.db.latestSeenVersion
-- so the notice still shows on later logins even when nobody else is online.
--
-- Anyone can fake a "JMV:99" line; the worst it does is show a pointless
-- notice, so there's no protection against it.
JM.VersionCheck = {}
local VersionCheck = JM.VersionCheck
local Skin = JM.Skin

local TAG = "JMV"
local CHANNEL = "JohnnysAddons"
local RELEASES_URL = "https://github.com/JohnnyL1993/JohnnysMessenger/releases"

local JOIN_DELAY = 5 -- after first PLAYER_ENTERING_WORLD
local CHANNEL_ANNOUNCE_DELAY = 10 -- after joining
local GROUP_THROTTLE = 60
local REPLY_THROTTLE = 600
local REPLY_DELAY_MIN, REPLY_DELAY_MAX = 5, 30

local PREFIX = "|cffffffffJohnny's Messenger|r: "

local myVersion = GetAddOnMetadata(JM.ADDON_NAME, "Version") or "0"
local playerName = UnitName("player")

local started = false
local announcedThisSession = false
local lastGroupSend = -GROUP_THROTTLE
local lastReply = -REPLY_THROTTLE
local replyPending = false

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end

--------------------------------------
--   Version comparison             --
--------------------------------------

-- Numeric per dotted part, so 1.10 > 1.9 and 1.2 == 1.2.0.
local function ParseVersion(v)
	local parts = {}
	for num in string.gmatch(tostring(v), "%d+") do
		table.insert(parts, tonumber(num))
	end
	return parts
end

-- Returns 1 if a > b, -1 if a < b, 0 if equal.
local function CompareVersions(a, b)
	local pa, pb = ParseVersion(a), ParseVersion(b)
	for i = 1, math.max(#pa, #pb) do
		local x, y = pa[i] or 0, pb[i] or 0
		if x > y then
			return 1
		end
		if x < y then
			return -1
		end
	end
	return 0
end

local function LatestNewerVersion()
	local latest = JM.db and JM.db.latestSeenVersion
	if latest and CompareVersions(latest, myVersion) > 0 then
		return latest
	end
end

--------------------------------------
--   In-window notice               --
--------------------------------------

local notice, hostTitle

local function RefreshNotice()
	if not notice then
		return
	end
	local latest = LatestNewerVersion()
	if latest then
		notice.text:SetText("Update available: v" .. latest)
		notice:SetWidth(notice.text:GetStringWidth() + 24)
		notice:Show()
		if hostTitle then
			hostTitle:Hide()
		end
	else
		notice:Hide()
		notice.linkPanel:Hide()
		if hostTitle then
			hostTitle:Show()
		end
	end
end

local function BuildLinkPanel(host)
	local panel = CreateFrame("Frame", nil, host)
	panel:SetSize(330, 48)
	panel:SetPoint("TOP", notice, "BOTTOM", 0, -2)
	panel:SetFrameLevel(host:GetFrameLevel() + 20)
	Skin:StylePanel(panel)
	panel:EnableMouse(true)

	local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("TOPLEFT", 8, -7)
	label:SetText(string.format("You have v%s. Copy the link with Ctrl+C:", myVersion))

	-- Read-only: re-selects everything on focus/click and undoes any typing,
	-- so it's just a place to Ctrl+C the link from.
	local urlHolder = Skin:CreateEditBox(panel, 314, 20)
	urlHolder:SetPoint("BOTTOM", 0, 6)
	local edit = urlHolder.editBox
	edit:SetText(RELEASES_URL)
	edit:HookScript("OnEditFocusGained", function(self)
		self:HighlightText()
	end)
	edit:SetScript("OnMouseUp", function(self)
		self:HighlightText()
	end)
	edit:HookScript("OnTextChanged", function(self, userInput)
		if userInput then
			self:SetText(RELEASES_URL)
			self:HighlightText()
		end
	end)
	edit:SetCursorPosition(0)
	panel.edit = edit

	panel:Hide()
	return panel
end

local function ToggleLinkPanel()
	local panel = notice.linkPanel
	if panel:IsShown() then
		panel:Hide()
	else
		panel:Show()
		panel.edit:SetFocus()
	end
end

-- Puts the notice where the window's title is, hiding the title while an
-- update is known (the title bar's corners already hold buttons). Called from
-- MainFrame's BuildFrame; shows straight away if a newer version is known.
function VersionCheck:AttachNotice(host, title)
	hostTitle = title
	notice = CreateFrame("Button", nil, host)
	notice:SetHeight(20)
	notice:SetPoint("TOP", 0, -5)

	local icon = notice:CreateTexture(nil, "OVERLAY")
	icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
	icon:SetSize(16, 16)
	icon:SetPoint("LEFT", 0, 0)

	local text = notice:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	text:SetPoint("LEFT", icon, "RIGHT", 4, 0)
	notice.text = text

	notice:SetScript("OnEnter", function(self)
		self.text:SetTextColor(1, 1, 1)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Click for the download link")
		GameTooltip:Show()
	end)
	notice:SetScript("OnLeave", function(self)
		self.text:SetTextColor(1, 0.82, 0)
		GameTooltip:Hide()
	end)
	notice:SetScript("OnClick", ToggleLinkPanel)

	notice.linkPanel = BuildLinkPanel(host)
	host:HookScript("OnHide", function()
		notice.linkPanel:Hide()
	end)

	RefreshNotice()
	return notice
end

function VersionCheck:PrintStatus()
	local latest = LatestNewerVersion()
	if latest then
		Print(string.format("installed %s, newer version %s available - %s", myVersion, latest, RELEASES_URL))
	else
		Print(string.format("installed %s - no newer version seen.", myVersion))
	end
end

--------------------------------------
--   Sending                        --
--------------------------------------

local function SendOnChannel()
	local id = GetChannelName(CHANNEL)
	if id and id > 0 then
		SendChatMessage(TAG .. ":" .. myVersion, "CHANNEL", nil, id)
	end
end

local function SendAddon(distribution)
	SendAddonMessage(TAG, myVersion, distribution)
end

local function SendToGroup()
	local now = GetTime()
	if now - lastGroupSend < GROUP_THROTTLE then
		return
	end
	if GetNumRaidMembers() > 0 then
		SendAddon("RAID")
	elseif GetNumPartyMembers() > 0 then
		SendAddon("PARTY")
	else
		return
	end
	lastGroupSend = now
end

-- Someone on an older version spoke - tell them once, after a random delay so
-- a crowd of up-to-date clients doesn't all answer at the same moment.
local function ScheduleReply(send)
	if replyPending or GetTime() - lastReply < REPLY_THROTTLE then
		return
	end
	replyPending = true
	JM.Timer:After(math.random(REPLY_DELAY_MIN, REPLY_DELAY_MAX), function()
		replyPending = false
		lastReply = GetTime()
		send()
	end)
end

--------------------------------------
--   Receiving                      --
--------------------------------------

local function AnnounceOnce()
	if not announcedThisSession then
		announcedThisSession = true
		Print(string.format("version %s is available (you have %s) - open /jm and click \"Update available\" for the link.", JM.db.latestSeenVersion, myVersion))
	end
end

local function OnVersionHeard(version, sender, reply)
	if not version or version == "" or sender == playerName or not JM.db then
		return
	end
	local cmp = CompareVersions(version, myVersion)
	if cmp > 0 then
		if not JM.db.latestSeenVersion or CompareVersions(version, JM.db.latestSeenVersion) > 0 then
			JM.db.latestSeenVersion = version
		end
		AnnounceOnce()
		RefreshNotice()
	elseif cmp < 0 then
		ScheduleReply(reply)
	end
end

local function IsOurChannel(channelName)
	return channelName and string.lower(channelName) == string.lower(CHANNEL)
end

-- Chat filters: hide our tagged lines and the channel's join/leave notices.
-- arg9 is the channel's base name for all three CHAT_MSG_CHANNEL* events.
local function ChannelMessageFilter(self, event, msg, ...)
	if msg and string.sub(msg, 1, #TAG + 1) == TAG .. ":" then
		return true
	end
end

local function ChannelNoticeFilter(self, event, ...)
	if IsOurChannel((select(9, ...))) then
		return true
	end
end

ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", ChannelMessageFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE", ChannelNoticeFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE_USER", ChannelNoticeFilter)

--------------------------------------
--   Channel join / events          --
--------------------------------------

local function JoinVersionChannel()
	if GetChannelName(CHANNEL) == 0 then
		JoinTemporaryChannel(CHANNEL)
	end
	-- Keep it out of every chat window even if some frame picked it up.
	for i = 1, NUM_CHAT_WINDOWS do
		local frame = _G["ChatFrame" .. i]
		if frame then
			ChatFrame_RemoveChannel(frame, CHANNEL)
		end
	end
	JM.Timer:After(CHANNEL_ANNOUNCE_DELAY, SendOnChannel)
end

local function OnFirstEnterWorld()
	if JM.db.latestSeenVersion and CompareVersions(JM.db.latestSeenVersion, myVersion) <= 0 then
		JM.db.latestSeenVersion = nil -- we've updated since it was seen
	end
	RefreshNotice()
	if LatestNewerVersion() then
		AnnounceOnce()
	end

	JM.Timer:After(JOIN_DELAY, JoinVersionChannel)
	if IsInGuild() then
		JM.Timer:After(JOIN_DELAY, function()
			SendAddon("GUILD")
		end)
	end
	SendToGroup()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CHAT_MSG_CHANNEL")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")

eventFrame:SetScript("OnEvent", function(self, event, ...)
	if event == "PLAYER_ENTERING_WORLD" then
		if not started then
			started = true -- PLAYER_ENTERING_WORLD also fires on every zone change
			OnFirstEnterWorld()
		end
	elseif event == "CHAT_MSG_CHANNEL" then
		local msg, sender = ...
		local channelName = select(9, ...)
		if IsOurChannel(channelName) and msg then
			local version = string.match(msg, "^" .. TAG .. ":(%S+)")
			OnVersionHeard(version, sender, SendOnChannel)
		end
	elseif event == "CHAT_MSG_ADDON" then
		local prefix, msg, distribution, sender = ...
		if prefix == TAG then
			OnVersionHeard(msg, sender, function()
				SendAddon(distribution)
			end)
		end
	elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
		SendToGroup()
	end
end)
