--!strict

type Chunk = () -> any
type Compiler = (source: string) -> Chunk?

local SOURCE_URL: string =
    "https://raw.githubusercontent.com/XzAngel19/ARandomMenu/main/src/gui/Current/gui.lua"
local source: string = game:HttpGet(SOURCE_URL)
local compiler: Compiler = (loadstring :: any) :: Compiler
local chunk: Chunk = assert(compiler(source), "ARandomMenu failed to compile")

return chunk()
