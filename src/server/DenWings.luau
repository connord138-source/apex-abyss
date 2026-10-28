--!strict
-- The den's wings and aquarium tanks as built things (2026-10-28; the proposal the
-- owner approved: "i like the den changes lets do that and try it out"; Config/Dens
-- wings and aquarium, Shared/DenSpace wingPlans, tanks and fixtures). DenBuilder calls
-- it with the den's frame and shape:
--  * every wing: a stone arch and lanterns at its passage's mouth, its name over the
--    passage on its own end wall, orb lamps down its middle;
--  * the Trophy Gallery: plinths showing the owner's biggest catch overall and at each
--    rarity (the real fish, in its rare look) and the boss trophies, each with a plaque;
--  * the Grotto Pool: a second Haul Pool in a stone basin (HuntService banks at it,
--    DenWings.pools) and a curtain of bubbles rising from a basin at its far end;
--  * the Observatory: a brass-framed round window onto the sea (DenCarve cuts it; the
--    client swims whales, mantas and jellies past it) and a dais facing it;
--  * the Great Hall: chandeliers under its high vault (its pillars are DenBuilder's);
--  * the aquarium tanks down the side walls and the Aquarium Hall's: glass, water, a
--    sand bed, a lamp and a plaque; the client swims each tank's fish in it
--    (AquariumController, by the `AquariumTank` tag and its attributes).
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DenItems = require(ReplicatedStorage.Shared.DenItems)
local DenSpace = require(ReplicatedStorage.Shared.DenSpace)
local PreyDisplay = require(ReplicatedStorage.Shared.PreyDisplay)
local Decor = require(script.Parent.Decor)
local DenCarve = require(script.Parent.DenCarve)

local Dens = Config.Dens

local DenWings = {}

local STONE = Color3.fromRGB(176, 164, 140)
local STONE_DARK = Color3.fromRGB(128, 118, 100)
local LAMP = Color3.fromRGB(255, 222, 180)
local POOL = Color3.fromRGB(80, 230, 255)
local WATER = Color3.fromRGB(56, 148, 176)
local SAND = Color3.fromRGB(214, 196, 150)
local GLASS = Color3.fromRGB(196, 232, 246)

-- What the Trophy Gallery shows: the owner's biggest catches (overall first, then one
-- for each rarity, Config/Catch), and the boss trophies
export type Catch = { prey: string, rarity: string, kg: number }
export type Gallery = {
	biggest: Catch?,
	byRarity: { [string]: Catch },
	teeth: number,
	beaks: number,
	title: string,
}

-- A tank's fish (Config/Dens aquarium): the prey and its rarity
export type Stock = { [string]: { prey: string, rarity: string } }

local function part(parent: Instance, props: { [string]: any }): Part
	local p = Decor.part(parent, props)
	if props.CanCollide == nil then
		p.CanCollide = false
	end
	p.CastShadow = props.CastShadow == true
	return p
end

local function lightOn(on: Instance, color: Color3, range: number, brightness: number): PointLight
	local made = Instance.new("PointLight")
	made.Color = color
	made.Range = range
	made.Brightness = brightness
	made.Parent = on
	return made
end

local function prettyMass(kg: number): string
	if kg >= 1000 then
		return string.format("%.1f T", kg / 1000)
	elseif kg >= 10 then
		return string.format("%d KG", math.floor(kg + 0.5))
	end
	return string.format("%.1f KG", kg)
end

-- The Haul Pools beyond the Nook's, in the world, by den (HuntService banks at them)
local poolsByDen: { [number]: { Vector3 } } = {}
function DenWings.pools(index: number): { Vector3 }
	return poolsByDen[index] or {}
end

-- An orb lamp hanging from a vault at `top` (local y) over (x, z); its cord is
-- reached up to the real rock by a ray later (DenWings.seat)
local function orbLamp(
	parent: Instance,
	frame: CFrame,
	x: number,
	top: number,
	z: number,
	glow: Color3,
	cords: { Part },
	brightness: number
)
	local function spot(y: number): CFrame
		return DenSpace.spot(frame, x, y, z)
	end
	table.insert(
		cords,
		part(parent, {
			Name = "Cord",
			Size = Vector3.new(0.15, 2.3, 0.15),
			CFrame = spot(top - 2.15),
			Color = STONE,
			Material = Enum.Material.Metal,
		})
	)
	local orb = part(parent, {
		Name = "Orb",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 2.2,
		CFrame = spot(top - 4.4),
		Color = glow:Lerp(Color3.new(1, 1, 1), 0.5),
		Material = Enum.Material.Glass,
		Transparency = 0.2,
	})
	orb.Name = "Orb"
	local core = part(parent, {
		Name = "Core",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one,
		CFrame = spot(top - 4.4),
		Color = LAMP,
		Material = Enum.Material.Neon,
	})
	lightOn(core, LAMP, 40, brightness)
end

-- Cords reach up to the rock once the Terrain answers rays (as DenBuilder's)
local function seatCords(cords: { Part })
	task.delay(0.5, function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { workspace.Terrain }
		for _, cord in cords do
			if cord.Parent == nil then
				continue
			end
			local low = cord.Position - Vector3.new(0, cord.Size.Y / 2, 0)
			local hit = workspace:Raycast(low, Vector3.new(0, 14, 0), params)
			if hit then
				local length = math.max(hit.Position.Y + 0.3 - low.Y, 0.5)
				cord.Size = Vector3.new(0.15, length, 0.15)
				cord.CFrame = CFrame.new(low + Vector3.new(0, length / 2, 0))
			end
		end
	end)
end

-- A round rim of stones `radius` out round (x, z) on the deck
local function rim(parent: Instance, frame: CFrame, x: number, z: number, radius: number, height: number)
	local deck = DenSpace.storey(1).deck
	local count = math.max(12, math.floor(radius * 2.2))
	local length = 2 * math.pi * radius / count + 0.12
	for i = 1, count do
		local around = DenSpace.spot(frame, x, deck, z) * CFrame.Angles(0, (i - 0.5) / count * 2 * math.pi, 0)
		part(parent, {
			Name = "Rim",
			Size = Vector3.new(length, height, 0.9),
			CFrame = around * CFrame.new(0, height / 2 - 0.15, -radius),
			Color = STONE:Lerp(Color3.new(1, 1, 1), 0.06),
			Material = Enum.Material.Slate,
			CanCollide = true,
		})
	end
end

-- The arch at a wing passage's mouth in the house: two jambs and a keystone band, a
-- lantern on each jamb facing into the house; the wing's name over the passage on
-- the wing's end wall
local function passage(parent: Instance, frame: CFrame, plan: DenSpace.WingPlan, glow: Color3)
	local tune = Dens.wing
	local deck = DenSpace.storey(1).deck
	local x = plan.side * (plan.wall - 0.4)
	local inward = -plan.side
	for _, dz in { tune.passageHalf + 0.9, -(tune.passageHalf + 0.9) } do
		local foot = DenSpace.spot(frame, x, deck, plan.z + dz)
		part(parent, {
			Name = "Jamb",
			Size = Vector3.new(1.6, tune.passageWall + 1, 1.8),
			CFrame = foot * CFrame.new(0, (tune.passageWall + 1) / 2, 0),
			Color = STONE,
			Material = Enum.Material.Slate,
			CanCollide = true,
		})
		Decor.lantern(
			parent,
			DenSpace.spot(frame, x + inward * 1.6, deck + tune.passageWall - 2.5, plan.z + dz)
				* CFrame.Angles(0, if plan.side > 0 then math.pi / 2 else -math.pi / 2, 0),
			0,
			true,
			18,
			glow:Lerp(Decor.GLASS_LIT, 0.4)
		)
	end
	-- The arch's band of voussoirs over the opening
	local radius = tune.passageHalf + 0.6
	local middle = tune.passageCrown - tune.passageHalf
	for i = 0, 8 do
		local a = math.pi * i / 8
		local dz = math.cos(a) * radius
		local dy = math.sin(a) * radius
		part(parent, {
			Name = "Voussoir",
			Size = Vector3.new(1.4, 1.1, 2.4),
			CFrame = DenSpace.spot(frame, x, middle + dy, plan.z + dz) * CFrame.Angles(a - math.pi / 2, 0, 0),
			Color = if i == 4 then glow else STONE:Lerp(Color3.new(1, 1, 1), 0.08),
			Material = if i == 4 then Enum.Material.Neon else Enum.Material.SmoothPlastic,
		})
	end
	-- The name, on the wing's own end wall over the passage (facing into the wing)
	local face = DenSpace.spot(frame, plan.side * (plan.x1 + 0.7), tune.passageCrown + 3.2, plan.z)
		* CFrame.Angles(0, if plan.side > 0 then -math.pi / 2 else math.pi / 2, 0)
	local plaque = Decor.plaque(parent, face, Vector2.new(14, 3.2), Decor.LACQUER, false)
	plaque.title.Text = Decor.oneLine(plan.def.name)
end

-- A plinth on the gallery's deck, `radius` round, with a fish (or the boss trophies)
-- over it and a plaque on the side facing `facing` (a unit direction in the den's x/z)
local function plinth(
	parent: Instance,
	frame: CFrame,
	fixture: DenSpace.Fixture,
	facing: Vector2,
	title: string,
	sub: string,
	glow: Color3
): CFrame
	local deck = DenSpace.storey(1).deck
	local height = if fixture.kind == "boss" then 3 else 3.8
	local foot = DenSpace.spot(frame, fixture.x, deck, fixture.z)
	local column = Decor.upright(parent, "Plinth", foot, height, fixture.radius - 0.5)
	column.Color = STONE:Lerp(Color3.new(1, 1, 1), 0.12)
	column.CanCollide = true
	local cap = Decor.upright(parent, "PlinthCap", foot * CFrame.new(0, height, 0), 0.5, fixture.radius)
	cap.Color = Decor.BRASS
	local base = Decor.upright(parent, "PlinthBase", foot, 0.7, fixture.radius + 0.4)
	base.Color = STONE_DARK
	local ring =
		Decor.upright(parent, "PlinthGlow", foot * CFrame.new(0, height + 0.5, 0), 0.08, fixture.radius - 0.2)
	ring.Color = glow
	ring.Material = Enum.Material.Neon
	-- The plaque leans against the plinth's side, facing out along `facing`
	local out = Vector3.new(facing.X, 0, -facing.Y) -- (the den's z runs the other way to a CFrame's)
	local at = foot.Position
		+ frame:VectorToWorldSpace(out) * (fixture.radius + 0.1)
		+ Vector3.new(0, height * 0.55, 0)
	local look = at + frame:VectorToWorldSpace(out)
	local plaque = Decor.plaque(parent, CFrame.lookAt(at, look), Vector2.new(5.6, 2.2), Decor.LACQUER, true)
	plaque.title.Text = Decor.oneLine(title)
	if plaque.sub then
		plaque.sub.Text = Decor.oneLine(sub)
	end
	local lamp = part(parent, {
		Name = "PlinthLight",
		Size = Vector3.one * 0.4,
		CFrame = foot * CFrame.new(0, height + 7, 0),
		Transparency = 1,
	})
	lightOn(lamp, LAMP, 14, 1.1)
	return foot * CFrame.new(0, height + 0.5, 0)
end

local function trophyGallery(
	parent: Instance,
	frame: CFrame,
	plan: DenSpace.WingPlan,
	fixtures: { DenSpace.Fixture },
	gallery: Gallery,
	glow: Color3
)
	local rarities = { "Normal" }
	for _, rarity in Config.Catch.rarities do
		table.insert(rarities, rarity.id)
	end
	for _, fixture in fixtures do
		if
			math.abs(fixture.x - plan.cx) > plan.def.length / 2 + 1
			or math.abs(fixture.z - plan.z) > plan.def.depth
		then
			continue
		end
		-- Plaques face the gallery's middle aisle; the centre one faces the way in
		local toward = Vector2.new(0, plan.z - fixture.z)
		if toward.Magnitude < 1 then
			toward = Vector2.new(-plan.side, 0)
		end
		toward = toward.Unit
		if fixture.kind == "boss" then
			local top = plinth(
				parent,
				frame,
				fixture,
				Vector2.new(-plan.side, 0),
				"BOSS TROPHIES",
				`{gallery.teeth} TEETH · {gallery.beaks} BEAKS`,
				glow
			)
			-- A Megalodon tooth and a Kraken beak on it, if won
			if gallery.teeth > 0 then
				part(parent, {
					Name = "Tooth",
					Size = Vector3.new(1.2, 3.4, 2.2),
					CFrame = top * CFrame.new(-1.2, 1.7, 0) * CFrame.Angles(0, 0, math.rad(8)),
					Color = Color3.fromRGB(236, 232, 220),
					Material = Enum.Material.SmoothPlastic,
				}).Shape =
					Enum.PartType.Wedge
			end
			if gallery.beaks > 0 then
				for _, sign in { -1, 1 } do
					local beak = part(parent, {
						Name = "Beak",
						Size = Vector3.new(0.9, 1.8, 2.4),
						CFrame = top
							* CFrame.new(1.4, 1 + sign * 0.5, 0)
							* CFrame.Angles(math.rad(sign * 25), 0, if sign > 0 then 0 else math.pi),
						Color = Color3.fromRGB(40, 30, 50),
						Material = Enum.Material.SmoothPlastic,
					})
					beak.Shape = Enum.PartType.Wedge
				end
			end
			continue
		end
		local catch: Catch? = nil
		local label = "BIGGEST CATCH"
		if fixture.index == 1 then
			catch = gallery.biggest
		else
			local rarity = rarities[fixture.index - 1]
			if rarity then
				catch = gallery.byRarity[rarity]
				local def = Config.Catch.byId[rarity]
				label = if def then `BIGGEST {def.name}` else "BIGGEST"
			end
		end
		local prey = if catch then Config.Prey.byId[catch.prey] else nil
		local title = if catch and prey
			then (if catch.rarity == "Normal"
				then prey.name
				else `{(Config.Catch.byId[catch.rarity] or { name = "" }).name} {prey.name}`)
			else "NOT CAUGHT YET"
		local top = plinth(
			parent,
			frame,
			fixture,
			toward,
			title,
			if catch then `{label} · {prettyMass(catch.kg)}` else label,
			glow
		)
		if catch and prey then
			local length =
				math.clamp(2 + math.sqrt(catch.kg) * 0.7, 2.5, if fixture.index == 1 then 8 else 5.5)
			local display = PreyDisplay.build(catch.prey, catch.rarity, length)
			PreyDisplay.place(
				display,
				top * CFrame.new(0, 1 + length * 0.18, 0) * CFrame.Angles(0, math.rad(60), 0)
			)
			display.model.Parent = parent
		end
	end
end

local function grottoPool(
	parent: Instance,
	frame: CFrame,
	plan: DenSpace.WingPlan,
	glow: Color3,
	index: number
)
	local deck = DenSpace.storey(1).deck
	local r = DenSpace.POOL_RADIUS
	-- The pool: a glowing disc in a stone basin, as the Nook's
	local disc = Decor.disc(
		parent,
		"GrottoHaulPool",
		DenSpace.spot(frame, plan.cx, deck - 0.1, plan.z) * CFrame.Angles(math.rad(-90), 0, 0),
		r,
		1
	)
	disc.Color = POOL
	disc.Material = Enum.Material.Neon
	disc.Transparency = 0.25
	lightOn(disc, POOL, 22, 1.6)
	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Rate = 6
	bubbles.Lifetime = NumberRange.new(2, 4)
	bubbles.Speed = NumberRange.new(2, 5)
	bubbles.SpreadAngle = Vector2.new(20, 20)
	bubbles.Size = NumberSequence.new(0.35, 0.1)
	bubbles.Transparency = NumberSequence.new(0.2, 1)
	bubbles.Color = ColorSequence.new(Color3.fromRGB(220, 250, 255))
	bubbles.LightEmission = 0.4
	bubbles.EmissionDirection = Enum.NormalId.Left
	bubbles.Parent = disc
	rim(parent, frame, plan.cx, plan.z, r + 0.45, 1.1)
	poolsByDen[index] = poolsByDen[index] or {}
	table.insert(poolsByDen[index], DenSpace.spot(frame, plan.cx, deck, plan.z).Position)
	-- The falls: a basin at the far end and a broad curtain of bubbles rising from it
	-- to the vault, lit from below
	local falls = DenSpace.spot(frame, plan.side * (plan.x1 + plan.def.length * 0.93), deck, plan.z)
	rim(parent, frame, plan.side * (plan.x1 + plan.def.length * 0.93), plan.z, 4, 1.4)
	local well = Decor.disc(
		parent,
		"FallsWell",
		falls * CFrame.Angles(math.rad(-90), 0, 0) * CFrame.new(0, 0, 0.1),
		3.6,
		0.6
	)
	well.Color = glow:Lerp(POOL, 0.5)
	well.Material = Enum.Material.Neon
	well.Transparency = 0.3
	lightOn(well, POOL, 30, 2)
	local sheet = part(parent, {
		Name = "FallsSource",
		Size = Vector3.new(7, 0.2, 2),
		CFrame = falls * CFrame.new(0, 0.4, 0) * CFrame.Angles(0, math.pi / 2, 0),
		Transparency = 1,
	})
	local curtain = Instance.new("ParticleEmitter")
	curtain.Name = "BubbleFalls"
	curtain.Rate = 55
	curtain.Lifetime = NumberRange.new(4, 5.5)
	curtain.Speed = NumberRange.new(5, 8)
	curtain.Acceleration = Vector3.new(0, 1.5, 0)
	curtain.SpreadAngle = Vector2.new(4, 4)
	curtain.EmissionDirection = Enum.NormalId.Top
	curtain.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(0.5, 0.5),
		NumberSequenceKeypoint.new(1, 0.7),
	})
	curtain.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.85, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	curtain.Color = ColorSequence.new(Color3.fromRGB(226, 252, 255), POOL)
	curtain.LightEmission = 0.5
	curtain.Shape = Enum.ParticleEmitterShape.Box
	curtain.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	curtain.Parent = sheet
	-- Corals and kelp round the pool's rim and the falls
	local rng = Random.new(index * 131 + 7)
	for i = 1, 12 do
		local a = (i + rng:NextNumber()) / 12 * 2 * math.pi
		local d = r + rng:NextNumber(2.5, 6)
		local foot = DenSpace.spot(frame, plan.cx + math.cos(a) * d, deck, plan.z + math.sin(a) * d)
		local kinds = { "Brain", "Fan", "Staghorn", "Anemone", "Kelp" }
		DenItems.piece(
			parent,
			kinds[(i % #kinds) + 1],
			foot * CFrame.Angles(0, rng:NextNumber(0, 2 * math.pi), 0),
			rng:NextNumber(1.6, 3.4),
			Decor.CORALS[(i % #Decor.CORALS) + 1],
			rng
		)
	end
end

local function observatory(
	parent: Instance,
	frame: CFrame,
	plan: DenSpace.WingPlan,
	fixtures: { DenSpace.Fixture },
	glow: Color3
)
	local deck = DenSpace.storey(1).deck
	local far = plan.x2
	local middle = deck + DenCarve.WINDOW_Y
	local radius = DenCarve.WINDOW_RADIUS
	local facingIn = if plan.side > 0 then math.pi / 2 else -math.pi / 2
	-- The glass, in the window's mouth (solid: the sea stays outside)
	local paneAt = DenSpace.spot(frame, plan.side * (far + 0.6), middle, plan.z)
		* CFrame.Angles(0, facingIn, 0)
	local pane = Decor.disc(parent, "ObservatoryWindow", paneAt, radius + 1, 0.4)
	pane.Color = GLASS
	pane.Material = Enum.Material.Glass
	pane.Transparency = 0.82
	pane.CanCollide = true
	pane:SetAttribute("Out", frame:VectorToWorldSpace(Vector3.new(plan.side, 0, 0)))
	pane:SetAttribute("Radius", radius)
	CollectionService:AddTag(pane, "ObservatoryWindow")
	-- A brass ring round it with bolts, and four spokes' worth of mullions
	local count = 28
	local ringR = radius + 0.4
	local length = 2 * math.pi * ringR / count + 0.15
	for i = 1, count do
		local a = (i - 0.5) / count * 2 * math.pi
		local seg = paneAt * CFrame.Angles(0, 0, a) * CFrame.new(0, ringR, -0.6)
		part(parent, {
			Name = "WindowRing",
			Size = Vector3.new(length, 1.4, 1.3),
			CFrame = seg,
			Color = Decor.BRASS,
			Material = Enum.Material.SmoothPlastic,
		})
		if i % 4 == 0 then
			part(parent, {
				Name = "WindowBolt",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 0.7,
				CFrame = seg * CFrame.new(0, 0, -0.75),
				Color = Decor.BRASS_LIGHT,
			})
		end
	end
	for _, a in { 0, math.pi / 2 } do
		part(parent, {
			Name = "Mullion",
			Size = Vector3.new(0.35, radius * 2, 0.35),
			CFrame = paneAt * CFrame.Angles(0, 0, a) * CFrame.new(0, 0, -0.35),
			Color = Decor.BRASS_DARK,
		})
	end
	-- The dais facing it: a low round stage with a brass rim and a glowing inlay
	for _, fixture in fixtures do
		if fixture.kind ~= "dais" or math.abs(fixture.x - plan.cx) > plan.def.length / 2 then
			continue
		end
		local foot = DenSpace.spot(frame, fixture.x, deck, fixture.z)
		local stage = Decor.upright(parent, "Dais", foot, 0.9, fixture.radius - 0.3)
		stage.Color = STONE:Lerp(Color3.new(0.2, 0.25, 0.3), 0.3)
		stage.Material = Enum.Material.SmoothPlastic
		stage.CanCollide = true
		local inlay =
			Decor.upright(parent, "DaisInlay", foot * CFrame.new(0, 0.9, 0), 0.06, fixture.radius - 1.4)
		inlay.Color = glow
		inlay.Material = Enum.Material.Neon
		inlay.Transparency = 0.4
		local edge = Decor.upright(parent, "DaisRim", foot, 1.05, fixture.radius)
		edge.Color = Decor.BRASS
		edge.Transparency = 0
		-- (the rim's middle is hidden in the stage)
	end
	-- A soft cool light from the window side, the room otherwise dim
	local wash = part(parent, {
		Name = "WindowWash",
		Size = Vector3.one * 0.5,
		CFrame = DenSpace.spot(frame, plan.side * (far - 6), middle, plan.z),
		Transparency = 1,
	})
	lightOn(wash, Color3.fromRGB(140, 200, 255), 40, 1.2)
end

local function greatHall(
	parent: Instance,
	frame: CFrame,
	plan: DenSpace.WingPlan,
	glow: Color3,
	cords: { Part }
)
	-- Chandeliers: a brass ring of orbs hanging from the high vault, three down the hall
	local _, ceiling = DenSpace.wallOf(plan.room)
	for i = 1, 3 do
		local x = plan.side * (plan.x1 + plan.def.length * (i / 4))
		local top = ceiling
		table.insert(
			cords,
			part(parent, {
				Name = "Cord",
				Size = Vector3.new(0.2, 6, 0.2),
				CFrame = DenSpace.spot(frame, x, top - 3, plan.z),
				Color = Decor.IRON,
				Material = Enum.Material.Metal,
			})
		)
		local hub = DenSpace.spot(frame, x, top - 7, plan.z)
		local ringPart =
			Decor.disc(parent, "ChandelierRing", hub * CFrame.Angles(math.rad(-90), 0, 0), 4.2, 0.4)
		ringPart.Color = Decor.BRASS
		for k = 1, 8 do
			local a = k / 8 * 2 * math.pi
			local at = hub * CFrame.new(math.cos(a) * 4.2, 0.6, math.sin(a) * 4.2)
			local orb = part(parent, {
				Name = "ChandelierOrb",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 1.3,
				CFrame = at,
				Color = glow:Lerp(Color3.new(1, 1, 1), 0.55),
				Material = Enum.Material.Neon,
				Transparency = 0.1,
			})
			if k % 4 == 0 then
				lightOn(orb, LAMP, 44, 0.9)
			end
		end
	end
end

-- Every wing of a den: rebuilt in `parent` (DenBuilder clears it first)
function DenWings.build(
	parent: Instance,
	index: number,
	frame: CFrame,
	shape: DenSpace.Shape,
	glow: Color3,
	gallery: Gallery
)
	poolsByDen[index] = {}
	local cords: { Part } = {}
	local fixtures = DenSpace.fixtures(shape)
	local deck = DenSpace.storey(1).deck
	for _, plan in DenSpace.wingPlans(shape) do
		local folder = Instance.new("Folder")
		folder.Name = `{plan.slot.id}{plan.def.id}`
		folder.Parent = parent
		passage(folder, frame, plan, glow)
		-- Orb lamps down the middle (the Great Hall has chandeliers, the Observatory
		-- stays dim so its window reads)
		local id = plan.def.id
		if id ~= "GreatHall" then
			local step = 16
			local n = math.max(1, math.floor(plan.def.length / step))
			local _, ceiling = DenSpace.wallOf(plan.room)
			for i = 1, n do
				local t = (i - 0.5) / n
				if id == "Observatory" and t > 0.5 then
					continue
				end
				local x = plan.side * (plan.x1 + plan.def.length * t)
				local z = plan.z
				-- (off the middle where a fixture stands under it)
				for _, fixture in fixtures do
					if (fixture.x - x) ^ 2 + (fixture.z - z) ^ 2 < (fixture.radius + 3) ^ 2 then
						z += 8
					end
				end
				orbLamp(folder, frame, x, ceiling, z, glow, cords, if id == "Observatory" then 0.4 else 0.75)
			end
		end
		if id == "TrophyGallery" then
			trophyGallery(folder, frame, plan, fixtures, gallery, glow)
		elseif id == "GrottoPool" then
			grottoPool(folder, frame, plan, glow, index)
		elseif id == "Observatory" then
			observatory(folder, frame, plan, fixtures, glow)
		elseif id == "GreatHall" then
			greatHall(folder, frame, plan, glow, cords)
		elseif id == "AquariumHall" then
			-- A glowing runner down the middle between the tanks
			part(folder, {
				Name = "Runner",
				Size = Vector3.new(plan.def.length - 8, 0.08, 1.2),
				CFrame = DenSpace.spot(frame, plan.cx, deck + 0.04, plan.z),
				Color = glow,
				Material = Enum.Material.Neon,
				Transparency = 0.35,
			})
		end
	end
	seatCords(cords)
end

-- The aquarium tanks of a den (Config/Dens aquarium, DenSpace.tanks), each with its
-- fish's plaque; the fish swim on the client (the tank's Water part carries
-- `AquariumTank` and the tank id, prey and rarity). Seated onto the real rock by a
-- ray once the Terrain answers, like the trophy wall.
function DenWings.tanks(parent: Instance, frame: CFrame, shape: DenSpace.Shape, glow: Color3, stock: Stock)
	local tune = Dens.aquarium
	local size = tune.size
	local models: { { model: Model, front: Vector3, normal: Vector3 } } = {}
	for _, tank in DenSpace.tanks(shape) do
		local model = Instance.new("Model")
		model.Name = `Tank{tank.id}`
		local normal = frame:VectorToWorldSpace(Vector3.new(tank.nx, 0, -tank.nz))
		local frontAt = DenSpace.spot(frame, tank.x, tank.y, tank.z).Position
		local face = CFrame.lookAt(frontAt, frontAt + normal)
		-- The box: its glass 1.3 studs out into the room from the wall, the rest set
		-- into the rock (`face`'s -Z points into the room), walled on five sides
		local inner = size.Z
		local dark = Color3.fromRGB(24, 44, 56)
		part(model, {
			Name = "TankBack",
			Size = Vector3.new(size.X + 1.2, size.Y + 1.2, 0.6),
			CFrame = face * CFrame.new(0, 0, inner - 1.3 + 0.3),
			Color = dark,
		})
		for _, sx in { -1, 1 } do
			part(model, {
				Name = "TankSide",
				Size = Vector3.new(0.6, size.Y + 1.2, inner),
				CFrame = face * CFrame.new(sx * (size.X / 2 + 0.3), 0, inner / 2 - 1.3),
				Color = dark,
			})
		end
		for _, sy in { -1, 1 } do
			part(model, {
				Name = "TankEnd",
				Size = Vector3.new(size.X + 1.2, 0.6, inner),
				CFrame = face * CFrame.new(0, sy * (size.Y / 2 + 0.3), inner / 2 - 1.3),
				Color = dark,
			})
		end
		local fish = stock[tank.id]
		local rarity = if fish then Config.Catch.byId[fish.rarity] else nil
		local tint = if rarity then rarity.color else WATER
		local water = part(model, {
			Name = "Water",
			Size = Vector3.new(size.X, size.Y, size.Z),
			CFrame = face * CFrame.new(0, 0, size.Z / 2 - 1.3),
			Color = WATER:Lerp(tint, 0.25),
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0.82,
		})
		water:SetAttribute("TankId", tank.id)
		if fish then
			water:SetAttribute("Prey", fish.prey)
			water:SetAttribute("Rarity", fish.rarity)
		end
		CollectionService:AddTag(water, "AquariumTank")
		lightOn(water, if fish then WATER:Lerp(tint, 0.5) else WATER, 14, if fish then 1.2 else 0.5)
		-- A sand bed, a few kelp blades and a shell
		part(model, {
			Name = "TankSand",
			Size = Vector3.new(size.X - 0.2, 0.7, size.Z - 0.4),
			CFrame = water.CFrame * CFrame.new(0, -size.Y / 2 + 0.35, 0),
			Color = SAND,
			Material = Enum.Material.SmoothPlastic,
		})
		local rng = Random.new(#tank.id * 97 + string.byte(tank.id, -1))
		for k = 1, 3 do
			Decor.kelp(
				model,
				water.CFrame
					* CFrame.new(-size.X / 2 + 1.2 + (k - 1) * (size.X - 2.4) / 2, -size.Y / 2 + 0.7, 0.6),
				3,
				1.6,
				rng
			)
		end
		-- The glass front and a brass frame round it
		part(model, {
			Name = "TankGlass",
			Size = Vector3.new(size.X, size.Y, 0.2),
			CFrame = face * CFrame.new(0, 0, -1.3),
			Color = GLASS,
			Material = Enum.Material.Glass,
			Transparency = 0.9,
			CanCollide = true,
		})
		for _, edge in { { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } } do
			local horizontal = edge[1] == 0
			part(model, {
				Name = "TankFrame",
				Size = if horizontal
					then Vector3.new(size.X + 1.2, 0.6, 0.6)
					else Vector3.new(0.6, size.Y + 1.2, 0.6),
				CFrame = face * CFrame.new(edge[1] * (size.X / 2 + 0.3), edge[2] * (size.Y / 2 + 0.3), -1.45),
				Color = Decor.BRASS,
			})
		end
		local lampBar = part(model, {
			Name = "TankLamp",
			Size = Vector3.new(size.X - 1, 0.25, 0.4),
			CFrame = face * CFrame.new(0, size.Y / 2 - 0.3, 0),
			Color = glow:Lerp(Color3.new(1, 1, 1), 0.6),
			Material = Enum.Material.Neon,
		})
		lampBar.Transparency = 0.2
		-- The plaque under it
		local prey = if fish then Config.Prey.byId[fish.prey] else nil
		local rate = if fish then tune.rates[fish.rarity] else nil
		local plaque = Decor.plaque(
			model,
			face * CFrame.new(0, -size.Y / 2 - 1.6, -1.6),
			Vector2.new(7.5, 1.9),
			Decor.LACQUER,
			true
		)
		plaque.title.Text = if fish and prey
			then Decor.oneLine(if rarity then `{rarity.name} {prey.name}` else prey.name)
			else Decor.oneLine("Empty tank")
		if plaque.sub then
			plaque.sub.Text = if rate
				then Decor.oneLine(`{rate.coral} coral an hour`)
				else Decor.oneLine("Stock it")
		end
		model.Parent = parent
		table.insert(models, { model = model, front = frontAt, normal = normal })
	end
	-- Seat each tank on the real rock: a ray from the room toward the wall
	task.delay(0.6, function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { workspace.Terrain }
		for _, entry in models do
			if entry.model.Parent == nil then
				continue
			end
			local from = entry.front + entry.normal * 10
			local hit = workspace:Raycast(from, -entry.normal * 16, params)
			if hit then
				-- The wall should sit 1.5 studs behind the glass
				local shift = (hit.Position - entry.front):Dot(entry.normal) + 1.5
				shift = math.clamp(shift, -4, 4)
				if math.abs(shift) > 0.2 then
					entry.model:PivotTo(entry.model:GetPivot() + entry.normal * shift)
				end
			end
		end
	end)
end

return DenWings
