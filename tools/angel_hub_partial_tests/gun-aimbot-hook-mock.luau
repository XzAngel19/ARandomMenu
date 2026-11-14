local calls={};local method='FireServer';local executorCaller=false
local original=function(remote,...)table.insert(calls,{remote=remote,args=table.pack(...)});return 'sent'end
local currentHook=original
local function hookmetamethod(_,name,callback)assert(name=='__namecall');local previous=currentHook;currentHook=callback;return previous end
local function getnamecallmethod()return method end
local function checkcaller()return executorCaller end
local oldTypeof=typeof
local function typeof(value)if type(value)=='table' and value.__cframe then return 'CFrame'end;return oldTypeof(value)end
