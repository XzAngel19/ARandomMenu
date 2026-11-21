--[[
	Minimal Roblox mock used to execute violent-ui/dist/Violent.lua outside the
	engine. It is a smoke harness, not an emulator: it validates that the bundle
	constructs its whole tree without errors and lets the test inspect sizes,
	text and hierarchy.
]]

local MOCK = {}

local function newSignal()
	local signal = { handlers = {} }
	function signal:Connect(callback)
		local entry = { callback = callback, connected = true }
		function entry:Disconnect()
			self.connected = false
		end
		table.insert(self.handlers, entry)
		return entry
	end
	function signal:Fire(...)
		for _, entry in ipairs(self.handlers) do
			if entry.connected then
				entry.callback(...)
			end
		end
	end
	return signal
end

MOCK.newSignal = newSignal

local CLASS_DEFAULT_PROPS = {
	Frame = { BackgroundColor3 = "Color3", BackgroundTransparency = 0, Visible = true },
	TextLabel = { Text = "", Visible = true },
	TextButton = { Text = "", Visible = true },
	ScrollingFrame = { Visible = true },
	ScreenGui = { Enabled = true },
}

local function newInstance(className, parent)
	local self = {
		__mockType = "Instance",
		_className = className,
		_props = { Name = className, ClassName = className, Parent = nil, Visible = true },
		_children = {},
		_signals = {},
		_attributes = {},
		AbsoluteSize = { X = 0, Y = 0, __mockType = "Vector2" },
		AbsolutePosition = { X = 0, Y = 0, __mockType = "Vector2" },
	}
	local defaults = CLASS_DEFAULT_PROPS[className]
	if defaults then
		for key, value in pairs(defaults) do
			self._props[key] = value
		end
	end
	setmetatable(self, MOCK.Instance)
	if parent then
		self.Parent = parent
	end
	return self
end

MOCK.Instance = {
	__index = function(self, key)
		local method = MOCK.InstanceMethods[key]
		if method then
			return method
		end
		local props = rawget(self, "_props")
		if props[key] ~= nil then
			return props[key]
		end
		local signals = rawget(self, "_signals")
		if signals[key] ~= nil then
			return signals[key]
		end
		-- Every input/text signal a GuiObject could expose.
		if key == "InputBegan" or key == "InputChanged" or key == "InputEnded"
			or key == "MouseEnter" or key == "MouseLeave" or key == "MouseButton1Click"
			or key == "Changed" or key == "AncestryChanged" or key == "Destroying"
			or key == "Activated"
		then
			local signal = newSignal()
			signals[key] = signal
			return signal
		end
		return nil
	end,
	__newindex = function(self, key, value)
		if key == "Parent" then
			local old = rawget(self, "_props").Parent
			if old ~= nil and old ~= value then
				for index, child in ipairs(old._children) do
					if child == self then
						table.remove(old._children, index)
						break
					end
				end
			end
			rawget(self, "_props").Parent = value
			if value ~= nil then
				table.insert(value._children, self)
			end
			return
		end
		rawget(self, "_props")[key] = value
	end,
}

MOCK.InstanceMethods = {}

function MOCK.InstanceMethods:Destroy()
	self._props.Parent = nil
	self._props.Destroyed = true
	if self._signals.Destroying then
		self._signals.Destroying:Fire()
	end
end

function MOCK.InstanceMethods:GetChildren()
	local result = {}
	for index, child in ipairs(self._children) do
		result[index] = child
	end
	return result
end

function MOCK.InstanceMethods:GetDescendants()
	local result = {}
	local function walk(node)
		for _, child in ipairs(node._children) do
			table.insert(result, child)
			walk(child)
		end
	end
	walk(self)
	return result
end

function MOCK.InstanceMethods:FindFirstChild(name, recursive)
	for _, child in ipairs(self._children) do
		if child._props.Name == name then
			return child
		end
	end
	return nil
end

function MOCK.InstanceMethods:FindFirstChildOfClass(className)
	for _, child in ipairs(self._children) do
		if child._className == className then
			return child
		end
	end
	return nil
end

function MOCK.InstanceMethods:WaitForChild(name)
	local existing = self:FindFirstChild(name)
	if existing then
		return existing
	end
	local child = newInstance("Folder")
	child.Name = name
	child.Parent = self
	return child
end

function MOCK.InstanceMethods:GetPropertyChangedSignal(property)
	local signals = rawget(self, "_signals")
	signals[property] = signals[property] or newSignal()
	return signals[property]
end

function MOCK.InstanceMethods:SetAttribute(name, value)
	self._attributes[name] = value
end

function MOCK.InstanceMethods:GetAttribute(name)
	return self._attributes[name]
end

function MOCK.InstanceMethods:IsA(className)
	return self._className == className
end

function MOCK.InstanceMethods:GetFullName()
	local names = { self._props.Name }
	local node = self._props.Parent
	while node ~= nil do
		table.insert(names, 1, node._props.Name)
		node = node._props.Parent
	end
	return table.concat(names, ".")
end

Instance = { new = function(className, parent)
	return newInstance(className, parent)
end }

-- Value types ---------------------------------------------------------------
local function typed(kind, fields)
	fields.__mockType = kind
	return fields
end

Color3 = {
	fromRGB = function(r, g, b)
		return typed("Color3", { R = r / 255, G = g / 255, B = b / 255, RGB = { r, g, b } })
	end,
	new = function(r, g, b)
		return typed("Color3", { R = r, G = g, B = b })
	end,
}

UDim = { new = function(scale, offset)
	return typed("UDim", { Scale = scale, Offset = offset })
end }

UDim2 = {
	new = function(xs, xo, ys, yo)
		return typed("UDim2", {
			X = { Scale = xs, Offset = xo },
			Y = { Scale = ys, Offset = yo },
		})
	end,
	fromOffset = function(x, y)
		return UDim2.new(0, x, 0, y)
	end,
	fromScale = function(x, y)
		return UDim2.new(x, 0, y, 0)
	end,
}

Vector2 = { new = function(x, y)
	return typed("Vector2", { X = x, Y = y })
end }

local function vectorSub(a, b)
	return Vector2.new(a.X - b.X, a.Y - b.Y)
end

setmetatable(Vector2, {
	__index = {},
})

local Vector2Meta = {
	__sub = vectorSub,
	__add = function(a, b)
		return Vector2.new(a.X + b.X, a.Y + b.Y)
	end,
}

-- Wrap new() to carry the metatable.
local rawVector2New = Vector2.new
Vector2.new = function(x, y)
	return setmetatable(rawVector2New(x, y), Vector2Meta)
end

ColorSequenceKeypoint = { new = function(time, color)
	return typed("ColorSequenceKeypoint", { Time = time, Value = color })
end }

ColorSequence = { new = function(keypoints)
	return typed("ColorSequence", { Keypoints = keypoints })
end }

NumberSequenceKeypoint = { new = function(time, value)
	return typed("NumberSequenceKeypoint", { Time = time, Value = value })
end }

NumberSequence = { new = function(keypoints)
	return typed("NumberSequence", { Keypoints = keypoints })
end }

Font = { new = function(family, weight, style)
	return typed("Font", { Family = family, Weight = weight, Style = style })
end }

-- Enums ---------------------------------------------------------------------
local enumItemMeta = {
	__tostring = function(self)
		return self.Name
	end,
}

local function enumItem(name)
	return setmetatable({ Name = name }, enumItemMeta)
end

local REAL_FONTS = {
	AmaticSC = true, Antique = true, Arial = true, ArialBold = true, Arcade = true,
	Arimo = true, Bangers = true, Bodoni = true, Cartoon = true, Code = true,
	Creepster = true, DenkOne = true, Fantasy = true, Fondamento = true,
	FredokaOne = true, Garamond = true, Gotham = true, GothamBlack = true,
	GothamBold = true, GothamMedium = true, GothamSemibold = true,
	GrenzeGotisch = true, Highway = true, IndieFlower = true, JosefinSans = true,
	Jura = true, Kalam = true, Legacy = true, LuckiestGuy = true,
	Merriweather = true, Michroma = true, Nunito = true, Oswald = true,
	PatrickHand = true, PermanentMarker = true, Roboto = true,
	RobotoCondensed = true, RobotoMono = true, Sarpanch = true, SciFi = true,
	SourceSans = true, SourceSansBold = true, SourceSansItalic = true,
	SourceSansLight = true, SourceSansSemibold = true, SpecialElite = true,
	TitilliumWeb = true, Ubuntu = true,
}

local enumCache = {}
local enumCategoryMeta = {
	__index = function(self, key)
		if self.__name == "Font" and not REAL_FONTS[key] then
			return nil
		end
		local item = enumCache[self.__name .. "." .. key]
		if item == nil then
			item = enumItem(key)
			enumCache[self.__name .. "." .. key] = item
		end
		return item
	end,
}

local enumGlobalMeta = {
	__index = function(self, key)
		local category = enumCache["@" .. key]
		if category == nil then
			category = setmetatable({ __name = key }, enumCategoryMeta)
			enumCache["@" .. key] = category
		end
		return category
	end,
}

Enum = setmetatable({}, enumGlobalMeta)

-- Runtime -------------------------------------------------------------------
local services = {}
local function service(name)
	if services[name] == nil then
		local instance = newInstance(name == "CoreGui" and "CoreGui" or "Folder")
		instance._props.Name = name
		services[name] = instance
	end
	return services[name]
end

local hiddenUI = newInstance("Folder")
hiddenUI.Name = "HiddenUI"

Players = service("Players")
local localPlayer = newInstance("Player")
localPlayer.Name = "LocalPlayer"
localPlayer.Parent = Players
local playerGui = newInstance("PlayerGui")
playerGui.Name = "PlayerGui"
playerGui.Parent = localPlayer
Players.LocalPlayer = localPlayer

game = {
	GetService = function(_, name)
		return service(name)
	end,
	GetFullName = function()
		return "Game"
	end,
}

workspace = {
	CurrentCamera = {
		ViewportSize = Vector2.new(1280, 720),
		GetPropertyChangedSignal = function()
			return newSignal()
		end,
	},
	GetPropertyChangedSignal = function()
		return newSignal()
	end,
}

UserInputService = service("UserInputService")
UserInputService.InputBegan = newSignal()
UserInputService.InputChanged = newSignal()
UserInputService.GetMouseLocation = function()
	return Vector2.new(0, 0)
end

RunService = service("RunService")
RunService.RenderStepped = newSignal()

gethui = function()
	return hiddenUI
end

task = {
	defer = function(callback, ...)
		local ok, err = pcall(callback, ...)
		if not ok then
			MOCK.deferredError = err
		end
	end,
	spawn = function(callback, ...)
		local ok, err = pcall(callback, ...)
		if not ok then
			MOCK.deferredError = err
		end
	end,
	wait = function()
		return 0
	end,
	delay = function(_, callback, ...)
		return callback(...)
	end,
}

function typeof(value)
	if type(value) == "table" and value.__mockType ~= nil then
		return value.__mockType
	end
	return type(value)
end

MOCK.service = service
MOCK.hiddenUI = hiddenUI
MOCK.newInstance = newInstance

return MOCK
