-- Moves the default chat window + input bar to the bottom-left corner so the
-- top of the screen stays clear (the inventory panel opens centered).
-- Uses TextChatService's ChatWindowConfiguration alignment properties; if the
-- experience is still on the legacy chat these don't exist, so failures are
-- caught and warned rather than breaking client startup.

local TextChatService = game:GetService("TextChatService")

local ChatConfig = {}

function ChatConfig.start()
	task.spawn(function()
		local ok, err = pcall(function()
			-- Only ChatWindowConfiguration carries the alignment properties;
			-- ChatInputBarConfiguration has no HorizontalAlignment/VerticalAlignment
			-- (assigning them throws), and the input bar auto-follows the window.
			local window = TextChatService:WaitForChild("ChatWindowConfiguration", 10)
			if window then
				window.HorizontalAlignment = Enum.HorizontalAlignment.Left
				window.VerticalAlignment = Enum.VerticalAlignment.Bottom
			end
		end)
		if not ok then
			warn("[ChatConfig] Could not reposition the chat (legacy chat service?): " .. tostring(err))
		end
	end)
end

return ChatConfig
