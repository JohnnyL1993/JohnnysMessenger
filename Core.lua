-- Shared addon namespace. Every module hangs its own table off this
-- (JM.Skin, JM.Store, JM.Whisper, JM.MainFrame, JM.Minimap).
JM = {}
JM.ADDON_NAME = "JohnnysMessenger"

local defaults = {
	history = {},
	minimap = { angle = 215 },
}

local function ApplyDefaults(db, defaultTbl)
	for k, v in pairs(defaultTbl) do
		if db[k] == nil then
			db[k] = v
		end
	end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == JM.ADDON_NAME then
		if type(JohnnysMessengerDB) ~= "table" then
			JohnnysMessengerDB = {}
		end
		ApplyDefaults(JohnnysMessengerDB, defaults)
		JM.db = JohnnysMessengerDB
	elseif event == "PLAYER_LOGIN" then
		-- Player name/realm aren't reliably available until login, so the
		-- data store, whisper capture and minimap icon all init here.
		JM.Store:Init()
		JM.Whisper:Init()
		JM.Minimap:Init()
	end
end)
