-- SpeedHubX / Modules / Util.luau
-- Executor-safe helpers: instance factory, GUI parenting with fallback,
-- previous-instance cleanup, window dragging and a tiny connection bucket.
-- No Roblox Studio-only APIs are assumed; every executor global is probed
-- with typeof/pcall before use.

return function(_Deps: any)
	local Util = {}

	local Players = game:GetService("Players")
	local UserInputService = game:GetService("UserInputService")

	--- Shorthand Instance constructor: Util.new("Frame", {Size = ..., Parent = ...})
	function Util.new(className: string, properties: { [string]: any }?): Instance
		local instance = Instance.new(className)
		if properties then
			for key, value in pairs(properties) do
				(instance :: any)[key] = value
			end
		end
		return instance
	end

	--- All containers a previous copy of the menu may live in.
	function Util.guiContainers(): { Instance }
		local containers: { Instance } = {}

		local localPlayer = Players.LocalPlayer
		if localPlayer then
			local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
			if playerGui then
				table.insert(containers, playerGui)
			end
		end

		local coreGuiOk, coreGui = pcall(function()
			return game:GetService("CoreGui")
		end)
		if coreGuiOk and coreGui then
			table.insert(containers, coreGui)
		end

		if typeof(gethui) == "function" then
			local ok, hidden = pcall(gethui)
			if ok and hidden then
				table.insert(containers, hidden)
			end
		end

		return containers
	end

	--- Destroy every existing GUI with this name (re-running the script
	--- replaces the old menu instead of stacking copies).
	function Util.destroyExisting(name: string)
		for _, container in ipairs(Util.guiContainers()) do
			local existing = container:FindFirstChild(name)
			while existing do
				existing:Destroy()
				existing = container:FindFirstChild(name)
			end
		end
		-- Also drop the handle published by a previous run, if any.
		if typeof(getgenv) == "function" then
			local ok, env = pcall(getgenv)
			if ok and type(env) == "table" and env.SpeedHubX and env.SpeedHubX ~= nil then
				pcall(function()
					env.SpeedHubX.Destroy()
				end)
				env.SpeedHubX = nil
			end
		end
	end

	--- Ask the executor (if it supports it) to protect the GUI.
	function Util.protectGui(screenGui: ScreenGui)
		local fenv: any = getfenv()
		local syn = fenv.syn
		if type(syn) == "table" and type(syn.protect_gui) == "function" then
			pcall(syn.protect_gui, screenGui)
		end
	end

	--- Best available parent for a ScreenGui, executor-first:
	--- gethui() -> CoreGui -> PlayerGui. Returns (parent, sourceName).
	function Util.bestParent(): (Instance?, string)
		if typeof(gethui) == "function" then
			local ok, hidden = pcall(gethui)
			if ok and hidden then
				return hidden, "gethui"
			end
		end

		local coreGuiOk, coreGui = pcall(function()
			return game:GetService("CoreGui")
		end)
		if coreGuiOk and coreGui then
			return coreGui, "CoreGui"
		end

		local localPlayer = Players.LocalPlayer
		if localPlayer then
			local playerGui = localPlayer:WaitForChild("PlayerGui", 5)
			if playerGui then
				return playerGui, "PlayerGui"
			end
		end

		return nil, "none"
	end

	--- Parent a ScreenGui the way executors expect, with graceful fallback:
	--- syn.protect_gui + gethui() -> CoreGui -> PlayerGui.
	function Util.parentGui(screenGui: ScreenGui): string
		Util.protectGui(screenGui)
		local parent, source = Util.bestParent()
		if parent then
			local parented = pcall(function()
				screenGui.Parent = parent
			end)
			if parented and screenGui.Parent == parent then
				return source
			end
			-- Last resort: PlayerGui directly.
			local localPlayer = Players.LocalPlayer
			local playerGui = localPlayer and localPlayer:FindFirstChildOfClass("PlayerGui")
			if playerGui then
				screenGui.Parent = playerGui
				return "PlayerGui"
			end
		end
		return "none"
	end

	--- Connection bucket so the whole menu can be unloaded cleanly.
	function Util.connectionBucket()
		local bucket = { _connections = {} :: { RBXScriptConnection } }

		function bucket.add(_self: any, connection: RBXScriptConnection): RBXScriptConnection
			table.insert(bucket._connections, connection)
			return connection
		end

		function bucket.disconnectAll(_self: any)
			for _, connection in ipairs(bucket._connections) do
				pcall(function()
					connection:Disconnect()
				end)
			end
			table.clear(bucket._connections)
		end

		return bucket
	end

	--- Make `window` draggable by grabbing `handle` (the title bar).
	--- Returns a setter to enable/disable dragging (used by the Misc tab).
	function Util.makeDraggable(window: GuiObject, handle: GuiObject, bucket: any): (boolean) -> ()
		local dragging = false
		local enabled = true
		local dragStart = Vector2.zero
		local windowStart = UDim2.new()

		bucket:add(handle.InputBegan:Connect(function(input: InputObject)
			if not enabled then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				dragging = true
				dragStart = Vector2.new(input.Position.X, input.Position.Y)
				windowStart = window.Position
			end
		end))

		bucket:add(UserInputService.InputChanged:Connect(function(input: InputObject)
			if not dragging or not enabled then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			then
				local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStart
				window.Position = UDim2.new(
					windowStart.X.Scale,
					windowStart.X.Offset + delta.X,
					windowStart.Y.Scale,
					windowStart.Y.Offset + delta.Y
				)
			end
		end))

		bucket:add(UserInputService.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				dragging = false
			end
		end))

		return function(value: boolean)
			enabled = value
			if not value then
				dragging = false
			end
		end
	end

	--- True while the user is typing in a TextBox (so RightShift etc.
	--- do not toggle the menu while chatting / entering values).
	function Util.isTyping(): boolean
		local focused = UserInputService:GetFocusedTextBox()
		return focused ~= nil
	end

	Util.Players = Players
	Util.UserInputService = UserInputService

	return Util
end
