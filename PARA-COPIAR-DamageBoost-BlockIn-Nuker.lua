--[[
PARA COPIAR: DamageBoost + Block-In + Nuker estrategico

Este paquete contiene solo los tres modulos pedidos y las funciones que
necesitan para funcionar como en la revision validada:
  * GetHotbar corregido.
  * Wallcheck mejorado (pies, torso y cabeza, en ambas direcciones).
  * Ruta estrategica de Nuker por costo real de herramienta/material.
  * bedwars.breakBlock con sesiones y cambio seguro de herramienta.

NO CONTIENE KILLAURA Y NO CAMBIA KILLAURA.

USO:
Este no es un script independiente. Cada SECCION indica el bloque del
6872274481.lua nuevo que debes reemplazar. Pega las secciones en orden.
]]

-- ============================================================================
-- SECCION 1: REEMPLAZA GetHotbar
-- ============================================================================
local function GetHotbar(Tool)
    local ToolName: string? = typeof(Tool) == "Instance" and Tool.Name or type(Tool) == "string" and Tool or type(Tool) == "table" and (Tool.itemType or Tool.Name) or nil
    for i: number, v: any in (Store.inventory.hotbar or {}) do
        local Item = v.item
        if Item and (Item.tool == Tool or ToolName and (Item.itemType == ToolName or Item.tool and Item.tool.Name == ToolName)) then
            return i - 1
        end
    end
    return nil
end
getgenv().getHotbar = GetHotbar

-- ============================================================================
-- SECCION 2: REEMPLAZA Entity.Wallcheck
-- Dentro del Run principal, justo despues de definir Entity.Raycast.
-- ============================================================================
    local OldWallcheck = Entity.Wallcheck
    local WallcheckParams: RaycastParams = RaycastParams.new()
    WallcheckParams.FilterType = Enum.RaycastFilterType.Exclude
    WallcheckParams.RespectCanCollide = true
    WallcheckParams.IgnoreWater = true
    local WallcheckFilter: {Instance} = {}

    Entity.Wallcheck = function(Origin: Vector3, Position: Vector3, IgnoreObject, Ent)
        local Character = Ent and Ent.Character
        local SelfCharacter = LocalPlayer.Character
        local SelfRoot = Entity.character and Entity.character.RootPart or SelfCharacter and SelfCharacter.PrimaryPart
        local TargetRoot = Ent and Ent.RootPart or Character and Character.PrimaryPart
        if not SelfCharacter or not Character or not SelfRoot or not TargetRoot then
            return OldWallcheck(Origin, Position, IgnoreObject)
        end

        local function GetBodyPoints(Root: BasePart, Humanoid: Humanoid?)
            local Scale = Humanoid and Humanoid:FindFirstChild("BodyHeightScale")
            local Feet: Vector3 = Root.Position - Vector3.new(0, (Humanoid and Humanoid.HipHeight or 0) + (Root.Size.Y / 2), 0)
            local Head: Vector3 = Feet + Vector3.new(0, 5 * (Scale and Scale.Value or 1), 0)
            return Feet, (Feet + Head) / 2, Head
        end

        local Humanoid: Humanoid? = SelfCharacter:FindFirstChildWhichIsA("Humanoid")
        local TargetHumanoid: Humanoid? = Character:FindFirstChildWhichIsA("Humanoid")
        local SelfFeet, SelfMiddle, SelfHead = GetBodyPoints(SelfRoot, Humanoid)
        local TargetFeet, TargetMiddle, TargetHead = GetBodyPoints(TargetRoot, TargetHumanoid)

        table.clear(WallcheckFilter)
        table.insert(WallcheckFilter, Camera)
        table.insert(WallcheckFilter, SelfCharacter)
        for _, v: any in Entity.List do
            if v.Character then
                table.insert(WallcheckFilter, v.Character)
            end
        end
        for _, v: Instance in CollectionService:GetTagged("DontBlockSwordRaycast") do
            table.insert(WallcheckFilter, v)
        end
        if typeof(IgnoreObject) == "table" then
            for _, v: Instance in IgnoreObject do
                table.insert(WallcheckFilter, v)
            end
        elseif typeof(IgnoreObject) == "Instance" then
            table.insert(WallcheckFilter, IgnoreObject)
        end
        WallcheckParams.FilterDescendantsInstances = table.clone(WallcheckFilter)

        local function BlockedBothWays(From: Vector3, To: Vector3)
            local Direction: Vector3 = To - From
            if Direction.Magnitude <= 0.001 then
                return nil
            end
            local Forward = Entity.Raycast(From, Direction, WallcheckParams)
            if not Forward then
                return nil
            end
            return Entity.Raycast(To, -Direction, WallcheckParams) and Forward or nil
        end

        -- A target is hidden only when world geometry covers feet, torso and
        -- head in both ray directions. One real body opening remains hittable.
        return BlockedBothWays(SelfFeet, TargetFeet)
            and BlockedBothWays(SelfMiddle, TargetMiddle)
            and BlockedBothWays(SelfHead, TargetHead)
            or nil
    end

-- ============================================================================
-- SECCION 3: REEMPLAZA BreakMethods Y CONSERVA local CalculatePath
-- Antes del Run principal de inicializacion de BedWars.
-- ============================================================================
local GetBlockHits
local BreakMethods = {
    Health = function(Block, BlockPosition)
        return GetBlockHits(Block, BlockPosition)
    end,
    Distance = function(Block, BlockPosition)
        local Position: Vector3 = (Entity.isAlive and (Entity.character.RootPart.Position - Vector3.new(0, 1, 0)) or Vector3.zero)
        return (Position - Vector3.new(Block.Position.X, Position.Y, Block.Position.Z)).Magnitude + GetBlockHits(Block, BlockPosition) * 0.01
    end
}
local CalculatePath

-- ============================================================================
-- SECCION 4: REEMPLAZA BlockStore.setBlock
-- Usa los locales existentes BlockStore, PathCache y BreakFocus.
-- ============================================================================
    OldSetBlock = BlockStore.setBlock
    BlockStore.setBlock = function(self, Position: Vector3, Block)
        -- Topology changes invalidate wallcheck routes; movement and knockback
        -- do not, keeping a valid strategic target stable while being hit.
        table.clear(PathCache)
        BreakFocus = nil
        Navigation.World:Invalidate(Position.X, Position.Y, Position.Z)
        return OldSetBlock(self, Position, Block)
    end

-- ============================================================================
-- SECCION 5: REEMPLAZA GetBlockHealth/GetBlockHits/CalculatePath
-- ============================================================================
    local function GetBlockHealth(Block, BlockPosition: Vector3)
        local BlockData = bedwars.BlockController:getStore():getBlockData(BlockPosition)
        return (BlockData and (BlockData:GetAttribute("1") or BlockData:GetAttribute("Health")) or Block:GetAttribute("Health"))
    end

    GetBlockHits = function(Block, BlockPosition: Vector3): number
        if not Block then
            return 0
        end
        local BreakType = bedwars.ItemMeta[Block.Name].block.breakType
        local Tool = Store.tools[BreakType]
        Tool = Tool and bedwars.ItemMeta[Tool.itemType].breakBlock[BreakType] or 2
        return GetBlockHealth(Block, bedwars.BlockController:getBlockPosition(BlockPosition)) / Tool
    end

    CalculatePath = function(Target, BlockPosition: Vector3, BreakMethod, MaxRange: number?, IgnoreOwnBlocks: boolean?)
        local Origin: Vector3 = Entity.character.RootPart.Position
        MaxRange = math.min(MaxRange or 30, 30)

        -- Wallcheck routes are based on the bed's real exposed faces, not the
        -- camera or the character's exact position. This keeps the route stable
        -- through knockback while still requiring an opening in the defense.
        local RouteCost = BreakMethod or BreakMethods.Health
        local Key: string = `{BlockPosition.X},{BlockPosition.Y},{BlockPosition.Z}|{BreakMethod == BreakMethods.Distance and 1 or 0}|{MaxRange}|{IgnoreOwnBlocks and 1 or 0}`
        if RouteCost == BreakMethods.Health then
            Key ..= `|{(Store.tools.wool or {}).itemType or ""},{(Store.tools.wood or {}).itemType or ""},{(Store.tools.stone or {}).itemType or ""}`
        end

        local Cached = PathCache[Key]
        if Cached then
            if Cached.pos and GetPlacedBlock(Cached.pos) and (Cached.pos - Origin).Magnitude <= MaxRange then
                return Cached.pos, Cached.cost, Cached.path
            end
            if not Cached.pos and Cached.origin and (Cached.origin - Origin).Magnitude < 3 then
                return nil, nil, Cached.path
            end
            PathCache[Key] = nil
        end

        local Placed, Costs = {}, {}
        local function GetCellBlock(Position: Vector3)
            local Block: any = Placed[Position]
            if Block == nil then
                Block = GetPlacedBlock(Position) or false
                Placed[Position] = Block
            end
            return Block or nil
        end

        local function GetCellCost(Block, Position: Vector3): number
            local Value: number? = Costs[Position]
            if Value == nil then
                Value = tonumber(RouteCost(Block, Position)) or math.huge
                Costs[Position] = Value
            end
            return Value
        end

        -- An exposed face only has to connect to open air around the defense.
        -- It intentionally does not need a perfect camera/head ray: aligned
        -- gaps in Block-In and bed defense remain usable even after knockback.
        local OpenRoutes = {}
        local function IsOpen(Open: Vector3): boolean
            if OpenRoutes[Open] ~= nil then
                return OpenRoutes[Open]
            end

            local Queue, Seen, Reached = {Open}, {[Open] = true}, false
            for _ = 1, 400 do
                local Current = table.remove(Queue)
                if not Current then
                    break
                end
                if (Current - BlockPosition).Magnitude > 15 then
                    Reached = true
                    break
                end

                for _, Side: Vector3 in Sides do
                    local Next: Vector3 = Current + Side
                    if not Seen[Next] and not GetCellBlock(Next) then
                        Seen[Next] = true
                        table.insert(Queue, Next)
                    end
                end
            end

            for Position: Vector3 in Seen do
                OpenRoutes[Position] = Reached
            end
            return Reached
        end

        -- A hole reaching either bed cell is enough. Exact character sight is
        -- deliberately not required; this is the permissive part of wallcheck.
        if GetCellBlock(BlockPosition) and (BlockPosition - Origin).Magnitude <= MaxRange then
            for _, Side: Vector3 in Sides do
                local Opening: Vector3 = BlockPosition + Side
                if not GetCellBlock(Opening) and IsOpen(Opening) then
                    local Direct = {}
                    PathCache[Key] = {pos = BlockPosition, cost = 0, path = Direct}
                    return BlockPosition, 0, Direct
                end
            end
        end

        local Visited, Queue = {}, {}
        local Distances, Exposed, BreakPath = {[BlockPosition] = 0}, {}, {}
        local function PushQueue(Node)
            local Index: number = #Queue + 1
            while Index > 1 do
                local Parent: number = math.floor(Index / 2)
                if Queue[Parent][1] <= Node[1] then
                    break
                end
                Queue[Index] = Queue[Parent]
                Index = Parent
            end
            Queue[Index] = Node
        end
        local function PopQueue()
            local First = Queue[1]
            local Last = table.remove(Queue)
            if #Queue > 0 then
                local Index: number = 1
                while Index * 2 <= #Queue do
                    local Child: number = Index * 2
                    if Child < #Queue and Queue[Child + 1][1] < Queue[Child][1] then
                        Child += 1
                    end
                    if Queue[Child][1] >= Last[1] then
                        break
                    end
                    Queue[Index] = Queue[Child]
                    Index = Child
                end
                Queue[Index] = Last
            end
            return First
        end
        PushQueue({0, BlockPosition})

        -- Dijkstra from the bed makes the first exposed block on the cheapest
        -- complete corridor the strategic choice (tool-adjusted health or the
        -- selected distance mode), rather than merely the closest face.
        for _ = 1, 1500 do
            local Node = PopQueue()
            if not Node then
                break
            end
            local Position: Vector3 = Node[2]
            if Visited[Position] then
                continue
            end
            Visited[Position] = true

            for _, Side: Vector3 in Sides do
                local Next: Vector3 = Position + Side
                if Visited[Next] or (Next - BlockPosition).Magnitude > 15 then
                    continue
                end

                local Block = GetCellBlock(Next)
                if not Block then
                    local Openings = Exposed[Position]
                    if Openings then
                        table.insert(Openings, Next)
                    else
                        Exposed[Position] = {Next}
                    end
                    continue
                end
                if Block == Target or Block:GetAttribute("NoBreak") then
                    continue
                end
                if IgnoreOwnBlocks and Block:GetAttribute("PlacedByUserId") == LocalPlayer.UserId then
                    continue
                end

                local Distance: number = Node[1] + GetCellCost(Block, Next)
                if Distance < (Distances[Next] or math.huge) then
                    Distances[Next] = Distance
                    BreakPath[Next] = Position
                    PushQueue({Distance, Next})
                end
            end
        end

        local Previous: Vector3? = Store.breakTarget
        local Candidates = {}
        for Position: Vector3, Openings: {Vector3} in Exposed do
            local Block = GetCellBlock(Position)
            local Magnitude: number = (Position - Origin).Magnitude
            if Block and Magnitude <= MaxRange then
                for _, Opening: Vector3 in Openings do
                    if IsOpen(Opening) then
                        table.insert(Candidates, {
                            Distances[Position] or 0,
                            Position,
                            Magnitude,
                            Position == Previous
                        })
                        break
                    end
                end
            end
        end

        table.sort(Candidates, function(A, B): boolean
            if A[1] ~= B[1] then
                return A[1] < B[1]
            end
            -- Knockback must not flip between equally strategic faces.
            if A[4] ~= B[4] then
                return A[4]
            end
            if A[3] ~= B[3] then
                return A[3] < B[3]
            end
            local AP, BP = A[2], B[2]
            return AP.X ~= BP.X and AP.X < BP.X or AP.X == BP.X and (AP.Y ~= BP.Y and AP.Y < BP.Y or AP.Y == BP.Y and AP.Z < BP.Z)
        end)

        local Best = Candidates[1]
        local BestPosition: Vector3? = Best and Best[2] or nil
        local BestCost: number? = Best and Best[1] or nil
        PathCache[Key] = {pos = BestPosition, cost = BestCost, path = BreakPath, origin = Origin}
        return BestPosition, BestCost, BreakPath
    end

-- ============================================================================
-- SECCION 6: REEMPLAZA ClearBreakRequest
-- ============================================================================
    local function ClearBreakRequest(Request)
        local Index: number? = table.find(BreakRequests, Request)
        if Index then table.remove(BreakRequests, Index) end
        BreakRequest = BreakRequests[#BreakRequests]
    end

-- ============================================================================
-- SECCION 7: REEMPLAZA bedwars.breakBlock
-- ============================================================================
    bedwars.breakBlock = function(Block, Effects, AnimationMode, CustomHealthbar, AutoTool, Wallcheck, Method, DirectOnly, Sequential: boolean?, Session, MaxRange: number?, IgnoreOwnBlocks: boolean?, StrategicRoute: boolean?)
        if LocalPlayer:GetAttribute("DenyBlockBreak") or not Entity.isAlive or (vape.Modules.InfiniteFly or {}).Enabled or Session and Session.Cancelled then
            return
        end
        local Timeout: number = math.max(1, LocalPlayer:GetNetworkPing() * 4 + 0.5)
        for i: number = #BreakRequests, 1, -1 do
            local Request = BreakRequests[i]
            if tick() - Request.sent >= Timeout or GetPlacedBlock(Request.position) ~= Request.hit then
                table.remove(BreakRequests, i)
            end
        end
        BreakRequest = BreakRequests[#BreakRequests]
        if BreakRequest and (not Sequential or #BreakRequests >= 4) then
            return BreakRequest.position, BreakRequest.path, BreakRequest.target, false
        end

        local Handler = bedwars.BlockController:getHandlerRegistry():getHandler(Block.Name)
        local LocalPosition: Vector3 = Entity.character.RootPart.Position
        local ContainedPositions = Handler and Handler:getContainedPositions(Block) or {bedwars.BlockController:getBlockPosition(Block.Position)}
        local AllowedRange: number = math.min(MaxRange or 30, 30)
        local Cost, Position, Target, BreakPath = math.huge
        local Direct: boolean = false

        -- Wallchecked beds are cheap to recompute from the stable route cache.
        -- Never pin one defense material through BreakFocus: inventory/tool or
        -- route changes must be allowed to promote a cheaper strategic block.
        if Sequential and not StrategicRoute and BreakFocus
            and BreakFocus.session == Session
            and BreakFocus.block == Block
            and BreakFocus.wallcheck == Wallcheck
            and BreakFocus.method == Method
            and BreakFocus.range == AllowedRange
            and BreakFocus.ignoreOwn == IgnoreOwnBlocks
            and GetPlacedBlock(BreakFocus.position) == BreakFocus.hit
            and (LocalPosition - BreakFocus.position).Magnitude <= AllowedRange
            and not BreakFocus.hit:GetAttribute("NoBreak") then
            Position, Target, BreakPath, Direct = BreakFocus.position, BreakFocus.target, BreakFocus.path, BreakFocus.direct
        end

        if not Position and not Wallcheck then
            -- Blatant mode deliberately targets the requested object itself and
            -- does no opening, camera, or defense-corridor checks.
            for _, Cell: Vector3 in ContainedPositions do
                local TargetPosition: Vector3 = Cell * 3
                local Distance: number = (LocalPosition - TargetPosition).Magnitude
                if Distance <= AllowedRange and GetPlacedBlock(TargetPosition) and (not Position or Distance < (LocalPosition - Position).Magnitude) then
                    Cost, Position, Target, BreakPath, Direct = 0, TargetPosition, TargetPosition, {}, true
                end
            end
        elseif not Position then
            for _, Cell: Vector3 in ContainedPositions do
                local TargetPosition: Vector3 = Cell * 3
                local CellPosition, CellCost, CellPath = CalculatePath(Block, TargetPosition, Method or nil, AllowedRange, IgnoreOwnBlocks)
                if CellPosition then
                    local Distance: number = (LocalPosition - CellPosition).Magnitude
                    local Hit: boolean = CellPosition == TargetPosition
                    local Sticky: boolean = CellPosition == Store.breakTarget
                    local CurrentSticky: boolean = Position == Store.breakTarget
                    local Better: boolean = Position == nil
                        or Hit ~= Direct and Hit
                        or Hit == Direct and CellCost < Cost
                        or Hit == Direct and CellCost == Cost and Sticky ~= CurrentSticky and Sticky
                        or Hit == Direct and CellCost == Cost and Sticky == CurrentSticky and Distance < (LocalPosition - Position).Magnitude
                    if Better then
                        Cost, Position, Target, BreakPath, Direct = CellCost, CellPosition, TargetPosition, CellPath, Hit
                    end
                end
            end
        end

        if DirectOnly and not Direct then
            return
        end
        if Position then
            Store.breakTarget = Position
            if (Entity.character.RootPart.Position - Position).Magnitude > AllowedRange then
                return
            end
            local HitBlock, HitPosition = GetPlacedBlock(Position)
            if not HitBlock then
                return
            end
            if BreakRequest and (BreakRequest.hit ~= HitBlock or BreakRequest.position ~= Position) then
                return BreakRequest.position, BreakRequest.path, BreakRequest.target, false
            end

            if (workspace:GetServerTimeNow() - bedwars.SwordController.lastAttack) > 0.4 then
                local BreakType = bedwars.ItemMeta[HitBlock.Name].block.breakType
                local Tool = Store.tools[BreakType]
                if Tool then
                    local HandValue: ObjectValue? = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HandInvItem")
                    local Changed: boolean = not Store.breakTool or Store.breakTool.tool ~= Tool.tool or not HandValue or HandValue.Value ~= Tool.tool
                    local Mining = {tool = Tool.tool, expires = tick() + Timeout, session = Session}
                    Store.breakTool = Mining
                    if AutoTool then
                        local Hotbar = GetHotbar(Tool.tool)
                        if Hotbar then
                            HotbarSwitch(Hotbar)
                        end
                    end
                    if Changed then
                        local Success, Equipped = bedwars.Handler:Get("SetInvItem"):Fire("CallServerAsync", {hand = Tool.tool}):await()
                        if not Success or Equipped == false or not Entity.isAlive or Session and Session.Cancelled or not HandValue or not HandValue.Parent then
                            return Position, BreakPath, Target, false
                        end
                        HandValue.Value = Tool.tool
                    end
                    Mining.expires = tick() + 0.5
                end
            end

            if BlockHealthbar.blockHealth == -1 or HitPosition ~= BlockHealthbar.breakingBlockPosition then
                BlockHealthbar.blockHealth = GetBlockHealth(HitBlock, HitPosition)
                BlockHealthbar.breakingBlockPosition = HitPosition
            end

            if not Entity.isAlive or Session and Session.Cancelled or GetPlacedBlock(Position) ~= HitBlock or not bedwars.BlockController:isBlockBreakable({blockPosition = HitPosition}, LocalPlayer) then
                BreakFocus = nil
                table.clear(PathCache)
                return nil, nil, nil, false
            end
            local BeforeHealth: number = GetBlockHealth(HitBlock, HitPosition) or 0
            local Request = {position = Position, target = Target, path = BreakPath, hit = HitBlock, sent = tick()}
            table.insert(BreakRequests, Request)
            BreakRequest = Request
            BreakFocus = Sequential and not StrategicRoute and {block = Block, hit = HitBlock, position = Position, target = Target, path = BreakPath, direct = Direct, wallcheck = Wallcheck, method = Method, range = AllowedRange, ignoreOwn = IgnoreOwnBlocks, session = Session} or nil
            local Focus = BreakFocus
            local Promise = bedwars.ClientDamageBlock:Get("DamageBlock"):CallServerAsync({
                blockRef = {blockPosition = HitPosition},
                hitPosition = Position,
                hitNormal = Vector3.FromNormalId(Enum.NormalId.Top)
            })
            Promise:andThen(function(Result)
                ClearBreakRequest(Request)
                if (not Result or Result == "cancelled" or Result == "destroyed") and BreakFocus == Focus then
                    BreakFocus = nil
                end
                if Result then
                    if Result == "cancelled" then
                        if BreakFocus == Focus then BreakFocus = nil end
                        table.clear(PathCache)
                        Store.damageBlockFail = tick() + 0.1
                        return
                    end

                    if Effects and Store.breakTarget == Position then
                        local AfterHealth: number = Result == "destroyed" and 0 or GetBlockHealth(HitBlock, HitPosition) or BeforeHealth
                        local BlockDamage: number = math.max(BeforeHealth - AfterHealth, 0)
                        BlockHealthbar.blockHealth = BeforeHealth
                        BlockHealthbar.breakingBlockPosition = HitPosition
                        CustomHealthbar = CustomHealthbar or bedwars.BlockBreaker.updateHealthbar
                        CustomHealthbar(bedwars.BlockBreaker, {blockPosition = HitPosition}, BlockHealthbar.blockHealth, HitBlock:GetAttribute("MaxHealth"), BlockDamage, HitBlock)
                        BlockHealthbar.blockHealth = math.max(BlockHealthbar.blockHealth - BlockDamage, 0)

                        if BlockHealthbar.blockHealth <= 0 then
                            bedwars.BlockBreaker.breakEffect:playBreak(HitBlock.Name, HitPosition, LocalPlayer)
                            bedwars.BlockBreaker.blockHealthbar:destroy()
                            BlockHealthbar.breakingBlockPosition = Vector3.zero
                        else
                            bedwars.BlockBreaker.breakEffect:playHit(HitBlock.Name, HitPosition, LocalPlayer)
                        end
                    end

                    if AnimationMode then
                        local Animation
                        if AnimationMode ~= "Minimal" or Random.new(os.clock() * 1.2):NextInteger(0, 1) == 1 then
                            Animation = bedwars.AnimationUtil:playAnimation(LocalPlayer, bedwars.BlockController:getAnimationController():getAssetId(1))
                        end
                        bedwars.ViewmodelController:playAnimation(15)
                        task.wait(AnimationMode == "Minimal" and 0.01 or 0.3)
                        if Animation then
                            Animation:Stop()
                            Animation:Destroy()
                        end
                    end
                end
                if Result == "destroyed" then
                    if BreakFocus == Focus then BreakFocus = nil end
                    table.clear(PathCache)
                end
            end):catch(function()
                ClearBreakRequest(Request)
                if BreakFocus == Focus then BreakFocus = nil end
                table.clear(PathCache)
            end)

            return Position, BreakPath, Target, true
        end
        return nil
    end

-- IMPORTANTE PARA LA CACHE DE RUTAS:
-- En BreakBlockEvent, Map.Blocks.ChildRemoved y Map.Blocks.ChildAdded,
-- coloca esta linea inmediatamente despues de table.clear(PathCache):
--     BreakFocus = nil

-- ============================================================================
-- SECCION 8: MODULO COMPLETO DamageBoost
-- ============================================================================
Run(function()
	local DamageBoost
	local Stack: number?

	local function IsLongJumping(): boolean
	    local Module = vape.Modules.LongJump
	    return Module and Module.Enabled or false
	end

	DamageBoost = vape.Categories.Blatant:CreateModule({
	    Name = "DamageBoost",
	    Function = function(Callback: boolean)
	        if Callback then
	            DamageBoost:Clean(VapeEvents.EntityDamageEvent.Event:Connect(function(DamageTable)
	                if Entity.isAlive and tick() > (Stack or 0) and DamageTable.entityInstance == LocalPlayer.Character and not IsLongJumping() then
	                    local Horizontal: number = DamageTable.knockbackMultiplier and DamageTable.knockbackMultiplier.horizontal or 0
	                    KnockbackSpeed = bedwars.KnockbackUtil.calculateKnockbackVelocity(Vector3.one, 1, {
	                        vertical = 0,
	                        horizontal = Horizontal
	                    }).Magnitude * (0.9 + (Store.ping.total or 0))
	                    Stack = tick() + (KnockbackSpeed / 45)
	                    KnockbackBoost = tick() + (Horizontal / 3.5)
	                end
	            end))
	        else
	            Stack = nil
	        end
	    end,
	    Tooltip = "Adds the normal short speed boost after damage without changing received knockback"
	})
end)

-- ============================================================================
-- SECCION 9: MODULO COMPLETO Block-In
-- ============================================================================
Run(function()
	local BlockIn
	local Mode
	local Center
	local Priority
	local Return
	local Switch
	local LimitItem
	local Wool
	local Blacklist
	local CenterOrigin: Vector3?

	local Scan: number = 30
	local Directions: {Vector3} = {
	    Vector3.new(1, 0, 0),
	    Vector3.new(-1, 0, 0),
	    Vector3.new(0, 0, 1),
	    Vector3.new(0, 0, -1)
	}
	local Priorities = {
	    ["Lowest cost"] = function(A, B): boolean
	        return A.Health < B.Health
	    end,
	    ["Hardest"] = function(A, B): boolean
	        return A.Health > B.Health
	    end
	}

	local function GetOrigin(): Vector3
	    local Position: Vector3 = Entity.character.RootPart.Position
	    local Hit: RaycastResult? = Entity.Raycast(Position, Vector3.new(0, -Scan, 0), Store.airRay)
	    return RoundPosition(Hit and Vector3.new(Position.X, Hit.Position.Y + 1.5, Position.Z) or Position)
	end

	local function GetBedNear()
	    local LocalPosition: Vector3 = Entity.character.RootPart.Position
	    for _, v: BasePart in CollectionService:GetTagged("bed") do
	        if (LocalPosition - v.Position).Magnitude >= 14 or v:GetAttribute(`Team{LocalPlayer:GetAttribute("Team") or -1}NoBreak`) then
	            continue
	        end

	        local Handler = bedwars.BlockController:getHandlerRegistry():getHandler(v.Name)
	        local Cells = Handler and Handler:getContainedPositions(v) or {v.Position / 3}
	        local Occupied = {}
	        for _, Cell: Vector3 in Cells do
	            Occupied[Cell * 3] = true
	        end

	        local Defended: boolean = true
	        for _, Cell: Vector3 in Cells do
	            for i: number = 1, #Sides do
	                local Position: Vector3 = (Cell * 3) + Sides[i]
	                if not Occupied[Position] and not GetPlacedBlock(Position) then
	                    Defended = false
	                    break
	                end
	            end
	            if not Defended then
	                break
	            end
	        end

	        if Defended then
	            return v
	        end
	    end
	    return nil
	end

	local function GetBlocks()
	    local Blocks = {}
	    local WoolOnly: boolean = Wool and Wool.Enabled or false
	    local Blacklisted: {string} = Blacklist and Blacklist.ListEnabled or {}
	    local Items = Store.inventory and Store.inventory.inventory and Store.inventory.inventory.items or {}
	    for _, v: any in Items do
	        local Meta = bedwars.ItemMeta[v.itemType]
	        local Block = Meta and Meta.block
	        local BlacklistName: string = v.itemType:find("wool") and "wool" or v.itemType
	        if Block and (WoolOnly and v.itemType:find("wool") or not WoolOnly and not table.find(Blacklisted, BlacklistName)) then
	            local Slot: number? = GetHotbar(v.tool)
	            if Slot or not (Switch and Switch.Enabled) then
	                table.insert(Blocks, {Type = v.itemType, Health = Block.health or 0, Slot = Slot, Amount = v.amount or math.huge})
	            end
	        end
	    end
	    if #Blocks > 1 then
	        table.sort(Blocks, Priorities[Priority and Priority.Value or "Lowest cost"])
	    end
	    return Blocks
	end

	local function GetPriorityBlockName(): string
	    local Selected = GetBlocks()[1]
	    if not Selected then
	        return "No block"
	    end
	    local Meta = bedwars.ItemMeta[Selected.Type]
	    return Meta and Meta.displayName or (tostring(Selected.Type):gsub("_", " "):gsub("%a+", function(Word: string)
	        return Word:sub(1, 1):upper() .. Word:sub(2)
	    end))
	end

	local function GetEnclosure(Origin: Vector3, Grounded: boolean): {Vector3}
	    local Enemy = Entity.EntityPosition({
	        Range = 60,
	        Part = "RootPart",
	        Players = true
	    })
	    local Facing: Vector3 = Enemy and Enemy.RootPart.Position - Origin or Vector3.zero
	    local Order: {Vector3} = table.clone(Directions)
	    table.sort(Order, function(A: Vector3, B: Vector3): boolean
	        return A:Dot(Facing) > B:Dot(Facing)
	    end)

	    local Cells: {Vector3} = {}
	    if Grounded and not Entity.Raycast(Origin, Vector3.new(0, -3, 0), Store.airRay) then
	        table.insert(Cells, Vector3.new(0, -3, 0))
	    end
	    for _, Height: number in {0, 3} do
	        for _, Direction: Vector3 in Order do
	            table.insert(Cells, Vector3.new(Direction.X * 3, Height, Direction.Z * 3))
	        end
	    end
	    if Grounded then
	        table.insert(Cells, Vector3.new(0, 6, 0))
	    end
	    return Cells
	end

	local function HoldCenter()
	    if not CenterOrigin or not Center.Enabled or vape.MovementOwner or not Entity.isAlive then
	        return
	    end

	    local Root: BasePart = Entity.character.RootPart
	    if isnetworkowner(Root) then
	        Root.CFrame = CFrame.new(CenterOrigin.X, Root.Position.Y, CenterOrigin.Z) * Root.CFrame.Rotation
	        Root.AssemblyLinearVelocity = Vector3.new(0, Root.AssemblyLinearVelocity.Y, 0)
	    end
	end

	local function PlacePattern(Origin: Vector3, Cells: {Vector3}, Blocks, Limit: number)
	    local Hotbar = Store.hand.tool and GetHotbar(Store.hand.tool) or nil
	    local PlaceDelay: number = 1 / math.min(bedwars.DefaultPlaceCPS or math.huge, bedwars.SharedConstants.BLOCK_PLACE_CPS)
	    local Placed: number = 0
	    local ShouldSwitch: boolean = Switch.Enabled and not LimitItem.Enabled

	    if LimitItem.Enabled then
	        local HeldName: string? = Store.hand.toolType == "block" and Store.hand.tool and Store.hand.tool.Name or nil
	        if not Blocks[1] or HeldName ~= Blocks[1].Type then
	            return
	        end
	        Blocks = {Blocks[1]}
	    end

	    for _, Offset: Vector3 in Cells do
	        if Placed >= Limit or not BlockIn.Enabled or not Entity.isAlive then
	            break
	        end
	        local Position: Vector3 = Origin + Offset
	        if GetPlacedBlock(Position) then
	            continue
	        end
	        while Blocks[1] and Blocks[1].Amount <= 0 do
	            table.remove(Blocks, 1)
	        end
	        local Block = Blocks[1]
	        if not Block then
	            break
	        end

	        if Center.Enabled then
	            CenterOrigin = Origin
	        end
	        repeat
	            task.wait()
	        until not BlockIn.Enabled or not Entity.isAlive or (workspace:GetServerTimeNow() - bedwars.BlockCpsController.lastPlaceTimestamp) >= PlaceDelay
	        if not BlockIn.Enabled or not Entity.isAlive then
	            break
	        end

	        if ShouldSwitch then
	            HotbarSwitch(Block.Slot)
	        end
	        task.spawn(bedwars.placeBlock, Position, Block.Type)
	        if GetPlacedBlock(Position) then
	            Block.Amount -= 1
	            Placed += 1
	        end
	    end
	    if Return.Enabled and ShouldSwitch and Hotbar then
	        HotbarSwitch(Hotbar)
	    end
	end

	BlockIn = vape.Categories.World:CreateModule({
	    Name = "Block-In",
	    Function = function(Callback: boolean)
	        if Callback then
	            BlockIn:Clean(RunService.PreSimulation:Connect(HoldCenter))
	            BlockIn:Clean(function()
	                CenterOrigin = nil
	            end)

	            repeat
	                if Entity.isAlive and (Mode.Value == "On bind" or GetBedNear()) then
	                    local Blocks = GetBlocks()
	                    local Early: boolean = false
	                    repeat
	                        task.wait()
	                        if Entity.isAlive and not Early then
	                            local Origin: Vector3 = GetOrigin()
	                            local Drop: number = Entity.character.RootPart.Position.Y - Origin.Y
	                            Early = Drop >= 6 and Drop <= 24
	                            if Early then
	                                PlacePattern(Origin, GetEnclosure(Origin, false), Blocks, Center.Enabled and math.huge or 3)
	                            end
	                        end
	                    until not BlockIn.Enabled or not Entity.isAlive or Entity.character.Humanoid.FloorMaterial ~= Enum.Material.Air

	                    if Entity.isAlive then
	                        local Origin: Vector3 = GetOrigin()
	                        PlacePattern(Origin, GetEnclosure(Origin, true), Blocks, math.huge)
	                    end
	                    CenterOrigin = nil
	                end

	                if Mode.Value == "On bind" then
	                    BlockIn:Toggle()
	                    break
	                end
	                task.wait(0.5)
	            until not BlockIn.Enabled
	        end
	    end,
	    ExtraText = function()
	        return GetPriorityBlockName()
	    end,
	    Tooltip = "Automatically blocks you in by building walls around you"
	})

	Mode = BlockIn:CreateDropdown({
	    Name = "Mode",
	    List = {"On bind", "When near"},
	    Default = "On bind",
	    Tooltip = "On bind blocks you in once per keypress, When near keeps you blocked in while you are on an enemy bed"
	})
	Center = BlockIn:CreateToggle({
	    Name = "Center",
	    Default = true,
	    Tooltip = "Holds you in the middle of your block while it builds, so no side gets skipped"
	})
	Priority = BlockIn:CreateDropdown({
	    Name = "Block priority",
	    List = {"Lowest cost", "Hardest"},
	    Default = "Lowest cost",
	    Tooltip = "Hardest picks the highest-health block in your inventory, including Obsidian, and shows it beside Block-In"
	})
	Switch = BlockIn:CreateToggle({Name = "Switch", Default = true})
	LimitItem = BlockIn:CreateToggle({
	    Name = "Limit to items",
	    Tooltip = "Only runs while the exact block selected by Block priority is already in your hand"
	})
	Return = BlockIn:CreateToggle({Name = "Return to last slot", Default = true})
	Wool = BlockIn:CreateToggle({Name = "Wool only"})
	Blacklist = BlockIn:CreateTextList({
	    Name = "Blacklist",
	    Default = {"cannon", "siege_tnt", "tnt"}
	})
end)

-- ============================================================================
-- SECCION 10: MODULO COMPLETO Nuker
-- ============================================================================
Run(function()
	local Nuker
	local Mode
	local ClosestBreak
	local Range
	local BreakSpeed
	local UpdateRate
	local Custom
	local Bed
	local Tesla
	local Hive
	local LuckyBlock
	local IronOre
	local Effect
	local CustomHealth = {}
	local Animation = {}
	local SelfBreak
	local LimitItem
	local Wallcheck
	local AutoTool
	local PlayerCheck
	local CustomList, Parts = {}, {}
	local Mouse: Mouse = cloneref(LocalPlayer:GetMouse())
	local MouseParams: RaycastParams = RaycastParams.new()
	MouseParams.FilterType = Enum.RaycastFilterType.Exclude
	local MouseOrigin, MouseDirection, MouseHit = Vector3.zero, Vector3.zero, nil
	local PlayerParams: RaycastParams = RaycastParams.new()
	PlayerParams.FilterType = Enum.RaycastFilterType.Include
	local Session = nil
	local ActiveBlock: BasePart?
	local NextBreak: number = 0
	local PathShown: boolean = false
	local HealthbarProgress
	local HealthbarCleanup: (() -> ())?

	local function ClearHealthbar()
	    local Cleanup: (() -> ())? = HealthbarCleanup
	    HealthbarCleanup = nil
	    if Cleanup then
	        Cleanup()
	    end
	end

	local function CustomHealthbar(self, BlockRef, Health: number, MaxHealth: number, ChangeHealth: number, Block)
	    xpcall(function()
	        if Block:GetAttribute("NoHealthbar") then
	            return
	        end
	        if not self.healthbarPart or not self.healthbarBlockRef or self.healthbarBlockRef.blockPosition ~= BlockRef.blockPosition then
	            if self.healthbarPart then
	                bedwars.QueryUtil:setQueryIgnored(self.healthbarPart, true)
	            end
	            ClearHealthbar()
	            self.healthbarBlockRef = BlockRef
	            local Roact = bedwars.Roact
	            local Create = Roact.createElement
	            local Meta = bedwars.ItemMeta[Block.Name]
	            local DisplayName: string = Meta and Meta.displayName or Block.Name
	            HealthbarProgress = HealthbarProgress or Roact.createRef()
	            local Percent: number = math.clamp(Health / MaxHealth, 0, 1)
	            local CleanCheck: boolean = true
	            local Part: Part = Instance.new("Part")
	            Part.Size = Vector3.one
	            Part.CFrame = CFrame.new(bedwars.BlockController:getWorldPosition(BlockRef.blockPosition))
	            Part.Transparency = 1
	            Part.Anchored = true
	            Part.CanCollide = false
	            Part.Parent = workspace
	            bedwars.QueryUtil:setQueryIgnored(Part, true)
	            self.healthbarPart = Part

	            local Mounted = Roact.mount(Create("BillboardGui", {
	                Size = UDim2.fromOffset(249, 102),
	                StudsOffset = Vector3.new(0, 2.5, 0),
	                Adornee = Part,
	                MaxDistance = 40,
	                AlwaysOnTop = true
	            }, {
	                Create("Frame", {
	                    Size = UDim2.fromOffset(160, 50),
	                    Position = UDim2.fromOffset(44, 32),
	                    BackgroundColor3 = Color3.new(),
	                    BackgroundTransparency = 0.5
	                }, {
	                    Create("UICorner", {CornerRadius = UDim.new(0, 5)}),
	                    Create("ImageLabel", {
	                        Size = UDim2.new(1, 89, 1, 52),
	                        Position = UDim2.fromOffset(-48, -31),
	                        BackgroundTransparency = 1,
	                        Image = GetVapeAsset(`{vape.Directory}/assets/new/blur.png`),
	                        ScaleType = Enum.ScaleType.Slice,
	                        SliceCenter = Rect.new(52, 31, 261, 502)
	                    }),
	                    Create("TextLabel", {
	                        Size = UDim2.fromOffset(145, 14),
	                        Position = UDim2.fromOffset(13, 12),
	                        BackgroundTransparency = 1,
	                        Text = DisplayName,
	                        TextXAlignment = Enum.TextXAlignment.Left,
	                        TextYAlignment = Enum.TextYAlignment.Top,
	                        TextColor3 = Color3.new(),
	                        TextScaled = true,
	                        Font = Enum.Font.Arial
	                    }),
	                    Create("TextLabel", {
	                        Size = UDim2.fromOffset(145, 14),
	                        Position = UDim2.fromOffset(12, 11),
	                        BackgroundTransparency = 1,
	                        Text = DisplayName,
	                        TextXAlignment = Enum.TextXAlignment.Left,
	                        TextYAlignment = Enum.TextYAlignment.Top,
	                        TextColor3 = Color.Dark(UIPallet.Text, 0.16),
	                        TextScaled = true,
	                        Font = Enum.Font.Arial
	                    }),
	                    Create("Frame", {
	                        Size = UDim2.fromOffset(138, 4),
	                        Position = UDim2.fromOffset(12, 32),
	                        BackgroundColor3 = UIPallet.Main
	                    }, {
	                        Create("UICorner", {CornerRadius = UDim.new(1, 0)}),
	                        Create("Frame", {
	                            [Roact.Ref] = HealthbarProgress,
	                            Size = UDim2.fromScale(Percent, 1),
	                            BackgroundColor3 = Color3.fromHSV(math.clamp(Percent / 2.5, 0, 1), 0.89, 0.75)
	                        }, {Create("UICorner", {CornerRadius = UDim.new(1, 0)})})
	                    })
	                })
	            }), Part)

	            HealthbarCleanup = function()
	                CleanCheck = false
	                self.healthbarBlockRef = nil
	                Roact.unmount(Mounted)
	                if self.healthbarPart then
	                    self.healthbarPart:Destroy()
	                end
	                self.healthbarPart = nil
	            end

	            bedwars.RuntimeLib.Promise.delay(5):andThen(function()
	                if CleanCheck then
	                    ClearHealthbar()
	                end
	            end)
	        end

	        local Progress: Frame? = HealthbarProgress and HealthbarProgress:getValue()
	        if not Progress then
	            return
	        end

	        local NewPercent: number = math.clamp((Health - ChangeHealth) / MaxHealth, 0, 1)
	        TweenService:Create(Progress, TweenInfo.new(0.3), {
	            Size = UDim2.fromScale(NewPercent, 1), BackgroundColor3 = Color3.fromHSV(math.clamp(NewPercent / 2.5, 0, 1), 0.89, 0.75)
	        }):Play()
	    end, function(...)
	        if shared.VapeDeveloper then
	            warn(...)
	        end
	    end)
	end

	local function GetContainedPositions(Block)
	    local Handler = bedwars.BlockController:getHandlerRegistry():getHandler(Block.Name)
	    return Handler and Handler:getContainedPositions(Block) or {bedwars.BlockController:getBlockPosition(Block.Position)}
	end

	local function IsBlockBreakable(Block): boolean
	    for _, Position: Vector3 in GetContainedPositions(Block) do
	        if bedwars.BlockController:isBlockBreakable({blockPosition = Position}, LocalPlayer) then
	            return true
	        end
	    end
	    return false
	end

	local function AttemptBreak(List, LocalPosition: Vector3, Route: boolean?, TeamCheck: boolean?)
	    if not List then
	        return
	    end

	    local Block, Closest = nil, math.huge
	    -- Wallcheck may inspect a bed just beyond reach when a useful outer
	    -- defense block is still inside legal breaking range.
	    local TargetRange: number = Route and Wallcheck.Enabled and math.min(Range.Value + 15, 45) or Range.Value
	    for _, v: BasePart in List do
	        if (v.Position - LocalPosition).Magnitude > TargetRange or not IsBlockBreakable(v) then
	            continue
	        end
	        if not SelfBreak.Enabled and v:GetAttribute("PlacedByUserId") == LocalPlayer.UserId then
	            continue
	        end
	        if TeamCheck then
	            local Placer: Player? = Players:GetPlayerByUserId(v:GetAttribute("PlacedByUserId") or 0)
	            if Placer and Placer:GetAttribute("Team") == LocalPlayer:GetAttribute("Team") then
	                continue
	            end
	        end
	        if (v:GetAttribute("BedShieldEndTime") or 0) > workspace:GetServerTimeNow() then
	            continue
	        end
	        if LimitItem.Enabled and not (Store.hand.tool and bedwars.ItemMeta[Store.hand.tool.Name] and bedwars.ItemMeta[Store.hand.tool.Name].breakBlock) then
	            continue
	        end
	        if PlayerCheck.Enabled and workspace:Raycast(Entity.character.Head.Position, v.Position - Entity.character.Head.Position, PlayerParams) then
	            continue
	        end

	        if not ClosestBreak.Enabled or v == MouseHit then
	            local Distance: number = (v.Position - LocalPosition).Magnitude
	            if v == ActiveBlock then
	                Block = v
	                break
	            end
	            if Distance < Closest then
	                Block, Closest = v, Distance
	            end
	            continue
	        end

	        local Offset: Vector3 = v.Position - MouseOrigin
	        local Along: number = Offset:Dot(MouseDirection)
	        local Spread: number = Along > 0 and (Offset - MouseDirection * Along).Magnitude or Offset.Magnitude
	        if Spread < Closest then
	            Block, Closest = v, Spread
	        end
	    end

	    if not Block then
	        return false
	    end

	    ActiveBlock = Block
	    if tick() < NextBreak then return true end
	    local Started: number = tick()
	    local AllowedRange: number = math.min(Range.Value, bedwars.BlockBreaker:getRange())
	    -- A wallchecked bed always uses complete tool-adjusted route cost.
	    -- Proximity/crosshair may choose the bed, but never Obsidian over a
	    -- cheaper wool corridor merely because the Obsidian is closer.
	    local BreakMethod = Route and Wallcheck.Enabled and BreakMethods.Health or ClosestBreak.Enabled and BreakMethods.Distance or BreakMethods[Mode.Value]
	    local BreakPosition, BreakPath, EndPosition, Requested = bedwars.breakBlock(Block, Effect.Enabled, Animation.Value ~= "No Animation" and Animation.Value or nil, CustomHealth.Enabled and CustomHealthbar or nil, AutoTool.Enabled, Wallcheck.Enabled, BreakMethod, not Route, true, Session, AllowedRange, Route and Wallcheck.Enabled and not SelfBreak.Enabled, Route and Wallcheck.Enabled)
	    if Requested then NextBreak = Started + math.max(BreakSpeed.Value, bedwars.BlockBreaker:getCooldown()) end
	    local CurrentNode = Effect.Enabled and BreakPosition or nil
	    if CurrentNode or PathShown then
	        PathShown = CurrentNode ~= nil
	        for _, v: Part in Parts do
	            v.Position = CurrentNode or Vector3.zero
	            if CurrentNode then
	                v.BoxHandleAdornment.Color3 = CurrentNode == EndPosition and Color3.new(1, 0.2, 0.2) or CurrentNode == BreakPosition and Color3.new(0.2, 0.2, 1) or Color3.new(0.2, 1, 0.2)
	            end
	            CurrentNode = BreakPath and BreakPath[CurrentNode]
	        end
	    end

	    return BreakPosition ~= nil
	end

	Nuker = vape.Categories.World:CreateModule({
	    Name = "Nuker",
	    ConfigName = "Breaker",
	    Function = function(Callback: boolean)
	        if Callback then
	            local Current = {}
	            Session = Current
	            ActiveBlock, NextBreak = nil, 0
	            for _ = 1, 30 do
	                local Part: Part = Instance.new("Part")
	                Part.Anchored = true
	                Part.CanQuery = false
	                Part.CanCollide = false
	                Part.Transparency = 1
	                Part.Parent = Camera
	                local Highlight: BoxHandleAdornment = Instance.new("BoxHandleAdornment")
	                Highlight.Size = Vector3.one
	                Highlight.AlwaysOnTop = true
	                Highlight.ZIndex = 1
	                Highlight.Transparency = 0.5
	                Highlight.Adornee = Part
	                Highlight.Parent = Part
	                table.insert(Parts, Part)
	            end

	            local Beds = Collection("bed", Nuker)
	            local Teslas = Collection("tesla-trap", Nuker)
	            local Hives = Collection("beehive", Nuker)
	            local LuckyBlocks = Collection("LuckyBlock", Nuker)
	            local IronOres = Collection("iron_ore_mesh_block", Nuker)
	            CustomList = Collection("block", Nuker, function(List, Object: Instance)
	                if table.find(Custom.ListEnabled, Object.Name) then
	                    table.insert(List, Object)
	                end
	            end)

	            repeat
	                task.wait(1 / UpdateRate.Value)
	                if not Nuker.Enabled or Session ~= Current then
	                    break
	                end
	                if Entity.isAlive then
	                    local LocalPosition: Vector3 = Entity.character.RootPart.Position

	                    if ClosestBreak.Enabled then
	                        local Ignore: {Instance} = {LocalPlayer.Character, Camera}
	                        for _, v: any in Entity.List do
	                            if v.Character then
	                                table.insert(Ignore, v.Character)
	                            end
	                        end
	                        MouseParams.FilterDescendantsInstances = Ignore
	                        MouseOrigin, MouseDirection = Mouse.UnitRay.Origin, Mouse.UnitRay.Direction
	                        local Result: RaycastResult? = workspace:Raycast(MouseOrigin, MouseDirection * 999, MouseParams)
	                        MouseHit = Result and Result.Instance or nil
	                    end
	                    if PlayerCheck.Enabled then
	                        local Characters: {Model} = {}
	                        for _, v: any in Entity.List do
	                            if v.Player and v.Character then
	                                table.insert(Characters, v.Character)
	                            end
	                        end
	                        PlayerParams.FilterDescendantsInstances = Characters
	                    end

	                    if AttemptBreak(Bed.Enabled and Beds, LocalPosition, true) then
	                        continue
	                    end
	                    if AttemptBreak(Hive.Enabled and Hives, LocalPosition, nil, true) then
	                        continue
	                    end
	                    if AttemptBreak(Tesla.Enabled and Teslas, LocalPosition, nil, true) then
	                        continue
	                    end
	                    if AttemptBreak(IronOre.Enabled and IronOres, LocalPosition) then
	                        continue
	                    end
	                    if AttemptBreak(LuckyBlock.Enabled and LuckyBlocks, LocalPosition) then
	                        continue
	                    end
	                    if AttemptBreak(CustomList, LocalPosition) then
	                        continue
	                    end

	                    ActiveBlock = nil
	                    if PathShown then
	                        PathShown = false
	                        for _, v: Part in Parts do
	                            v.Position = Vector3.zero
	                        end
	                    end
	                end
	            until not Nuker.Enabled or Session ~= Current
	        else
	            if Session then Session.Cancelled = true end
	            if Store.breakTool and Store.breakTool.session == Session then
	                Store.breakTool = nil
	            end
	            ActiveBlock = nil
	            ClearHealthbar()
	            for _, v: Part in Parts do
	                v:ClearAllChildren()
	                v:Destroy()
	            end
	            table.clear(Parts)
	            PathShown = false
	        end
	    end,
	    ExtraText = function()
	        return Wallcheck and Wallcheck.Enabled and "Wallcheck" or "Blatant"
	    end,
	    Tooltip = "Break blocks around you automatically"
	})

	Mode = Nuker:CreateDropdown({
	    Name = "Break mode",
	    List = {"Health", "Distance"},
	    Default = "Health",
	    Tooltip = "Wallchecked beds always use strategic Health cost; this setting controls other targets"
	})
	ClosestBreak = Nuker:CreateToggle({
	    Name = "Closest break",
	    Function = function(Callback: boolean)
	        Mode.Object.Visible = not Callback
	    end,
	    Tooltip = "Chooses targets nearest your crosshair; a wallchecked bed still uses its cheapest strategic defense corridor"
	})
	Range = Nuker:CreateSlider({
	    Name = "Break range",
	    Min = 1,
	    Max = 30,
	    Default = 30,
	    Suffix = function(Val: number)
	        return Val == 1 and "stud" or "studs"
	    end
	})
	BreakSpeed = Nuker:CreateSlider({
	    Name = "Break speed",
	    Min = 0,
	    Max = 0.3,
	    Default = 0.25,
	    Decimal = 100,
	    Suffix = "seconds"
	})
	UpdateRate = Nuker:CreateSlider({
	    Name = "Update rate",
	    Min = 1,
	    Max = 120,
	    Default = 60,
	    Suffix = "hz"
	})
	Custom = Nuker:CreateTextList({
	    Name = "Custom",
	    Function = function()
	        if not CustomList then
	            return
	        end
	        table.clear(CustomList)
	        for _, v: BasePart in Store.blocks do
	            if table.find(Custom.ListEnabled, v.Name) then
	                table.insert(CustomList, v)
	            end
	        end
	    end
	})
	Bed = Nuker:CreateToggle({
	    Name = "Break Bed",
	    Default = true
	})
	Tesla = Nuker:CreateToggle({
	    Name = "Break Tesla",
	    Default = true
	})
	Hive = Nuker:CreateToggle({
	    Name = "Break Hive",
	    Default = true
	})
	LuckyBlock = Nuker:CreateToggle({
	    Name = "Break Lucky Block",
	    Default = true
	})
	IronOre = Nuker:CreateToggle({
	    Name = "Break Iron Ore",
	    Default = true
	})
	Effect = Nuker:CreateToggle({
	    Name = "Show Healthbar & Effects",
	    Function = function(Callback: boolean)
	        if CustomHealth.Object then
	            CustomHealth.Object.Visible = Callback
	        end
	    end,
	    Default = true
	})
	CustomHealth = Nuker:CreateToggle({
	    Name = "Custom Healthbar",
	    Default = true,
	    Darker = true
	})
	Animation = Nuker:CreateDropdown({
	    Name = "Animation Mode",
	    List = {"No Animation", "Minimal", "Full"},
	    Tooltip = "Minimal plays the tiny stub you get while macroing, Full plays the whole swing"
	})
	SelfBreak = Nuker:CreateToggle({Name = "Self Break"})
	Wallcheck = Nuker:CreateToggle({
	    Name = "Wallcheck",
	    Default = true,
	    Tooltip = "Uses exposed openings and the cheapest bed-defense corridor; disable for blatant direct nuking"
	})
	AutoTool = Nuker:CreateToggle({
	    Name = "Auto Tool",
	    Tooltip = "Visualises tool switching on ur client"
	})
	LimitItem = Nuker:CreateToggle({
	    Name = "Limit to items",
	    Tooltip = "Only breaks when tools are held"
	})
	PlayerCheck = Nuker:CreateToggle({
	    Name = "Player check",
	    Tooltip = "Skips a block while a player stands between you and it, so you dont mine through them"
	})
end)

-- FIN. Killaura no esta incluido y debe quedarse como en tu Lua nuevo.
