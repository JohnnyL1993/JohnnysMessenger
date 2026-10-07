-- Fallback launcher alongside the minimap icon and the keybinding.
SLASH_JOHNNYSMESSENGER1 = "/jm"
SLASH_JOHNNYSMESSENGER2 = "/messenger"
SlashCmdList["JOHNNYSMESSENGER"] = function(msg)
	local cmd = string.lower(string.match(msg or "", "^%s*(%S*)") or "")
	if cmd == "settings" or cmd == "options" or cmd == "config" then
		JM.MainFrame:Show()
		JM.MainFrame:ToggleSettings(true)
	elseif cmd == "reply" or cmd == "r" then
		local target = ChatEdit_GetLastTellTarget()
		if target and target ~= "" then
			JM.MainFrame:Show()
			JM.MainFrame:SelectConversation(target)
			JM.MainFrame:FocusEditBox()
		else
			print("|cffffffffJohnny's Messenger:|r nobody has whispered you yet.")
		end
	elseif cmd == "help" then
		print("|cffffffffJohnny's Messenger|r commands:")
		print("  /jm - toggle the window")
		print("  /jm reply - open the last person who whispered you")
		print("  /jm settings - open settings")
	else
		JM.MainFrame:Toggle()
	end
end

-- Key Bindings > AddOns > Johnny's Messenger (see Bindings.xml).
BINDING_HEADER_JOHNNYSMESSENGER = "Johnny's Messenger"
BINDING_NAME_JOHNNYSMESSENGER_TOGGLE = "Toggle messenger window"
BINDING_NAME_JOHNNYSMESSENGER_REPLY = "Reply to last whisper"
