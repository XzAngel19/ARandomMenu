--[[
	Main.lua
	Entry point. Builds the ScreenGui in the safest container the executor
	offers, mounts the menu, binds the visibility key (RightShift) and returns
	the public API.

	Standalone: no game-specific code, no Studio assumptions, no features.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Theme = require("Theme")
local Util = require("Util")
local Menu = require("Menu")
local Stubs = require("Stubs")

local Main = {
	Name = Theme.Name,
	Version = Theme.Version,
	Visible = true,
}

local env = (typeof(getgenv) == "function" and getgenv()) or _G

-- Replace a previous build instead of stacking a second copy.
local previous = env.VIOLENT_UI
if type(previous) == "table" and type(previous.Destroy) == "function" then
	pcall(previous.Destroy)
end

local screen = Util.new("ScreenGui", {
	Name = "ViolentUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 90,
})
Util.protectGui(screen)

-- Parent into the hidden-UI container when available; CoreGui and PlayerGui
-- are the fallbacks. The parent call itself is guarded: some executors expose
-- gethui() but still refuse the assignment.
local function mount(gui)
	local ok = pcall(function()
		gui.Parent = Util.guiParent()
	end)
	if ok and gui.Parent ~= nil then
		return
	end
	local player = Players.LocalPlayer
	if player == nil then
		for _ = 1, 100 do
			player = Players.LocalPlayer
			if player ~= nil then
				break
			end
			task.wait(0.05)
		end
	end
	if player then
		local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10)
		if playerGui then
			gui.Parent = playerGui
		end
	end
end

mount(screen)

local menu = Menu.new(screen)

Main.Menu = menu
Main.Screen = screen
Main.State = menu.State
Main.Stubs = Stubs

function Main.SetVisible(visible)
	menu:SetVisible(visible)
	Main.Visible = menu.Visible
end

function Main.Toggle()
	Main.SetVisible(not menu.Visible)
end

-- RightShift shows/hides both windows (UI-only behaviour).
local keyConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.RightShift then
		Main.Toggle()
	end
end)

-- Keep the board scaled to the viewport. Positions are only laid out once so
-- dragging is never undone by a resolution change.
Main.__lastViewport = Util.viewportSize()
local viewportConnection = RunService.RenderStepped:Connect(function()
	local viewport = Util.viewportSize()
	if viewport ~= Main.__lastViewport then
		Main.__lastViewport = viewport
		menu:RefreshScale(false)
	end
end)

function Main.Destroy()
	if Main.__destroyed then
		return
	end
	Main.__destroyed = true

	pcall(function()
		keyConnection:Disconnect()
	end)
	pcall(function()
		viewportConnection:Disconnect()
	end)
	pcall(function()
		menu:Destroy()
	end)
	pcall(function()
		screen:Destroy()
	end)

	if env.VIOLENT_UI == Main then
		env.VIOLENT_UI = nil
	end
end

env.VIOLENT_UI = Main

Stubs.Ready()

return Main
