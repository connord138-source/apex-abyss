--!strict
-- Skins wait for their textures (PC 2026-10-16 round 2, K1): when Roblox's image
-- server failed (`HttpError: ServerProtocolError` after ~58 s), a newly worn skin drew
-- the fish untextured white until it was worn again. FishAnimator asks `ready` before
-- it puts a skin on: until every one of the skin's textures has downloaded, the fish
-- keeps a stand-in (its own texture tinted toward the shade, Cosmetics' look for a
-- skin not imported yet), and a texture whose download failed is fetched again, a
-- little later each time. After GIVE_UP seconds the skin goes on anyway (a texture
-- can report Failure and still draw: right after an import, "Asset type does not
-- match requested type", PC 2026-10-16 round 2), and the fetches carry on: once they
-- all arrive, `state` changes again so the animator puts the skin on afresh.
-- `claimTest` (the admin's "Skins: pretend my worn skin's download fails") plays
-- that out on purpose: the skin counts as failing for TEST_SECONDS, logging each
-- pretend retry as `[SkinLoader] test:`, so it shows the stand-in, goes on at
-- GIVE_UP and is put on afresh when the pretence ends.
-- A Model (an exotic variant's own model, VariantModels.<id>) waits the same way for
-- its meshes and textures (PC 2026-10-22: a shade on a fresh variant drew it a flat
-- silhouette in the shade's colour for 6-14 s while its texture downloaded).
local ContentProvider = game:GetService("ContentProvider")

local SkinLoader = {}

local MAPS = {
	"ColorMapContent",
	"NormalMapContent",
	"RoughnessMapContent",
	"MetalnessMapContent",
	"EmissiveMaskContent",
}
local RETRY_MOST = 30 -- seconds between tries at most
local TRIES_MOST = 8
local GIVE_UP = 12 -- seconds a skin waits before it goes on anyway
local TEST_SECONDS = 18 -- how long `claimTest` pretends a skin's download fails

local texturesOf: { [Instance]: { string } } = {} -- skins live in ReplicatedStorage, so strong keys
local loaded: { [string]: boolean } = {}
local fetching: { [string]: boolean } = {}
local tries: { [string]: number } = {}
local retryAt: { [string]: number } = {}
local firstAsked: { [Instance]: number } = {}
type Pretend = { untilAt: number, tries: number, retryAt: number }
local pretending: { [Instance]: Pretend } = {}

local function contentUri(skin: Instance, property: string): string?
	local ok, content = pcall(function()
		return (skin :: any)[property]
	end)
	if ok and typeof(content) == "Content" then
		local uri = (content :: any).Uri
		if typeof(uri) == "string" and uri ~= "" then
			return uri
		end
	end
	return nil
end

local function textures(skin: Instance): { string }
	local cached = texturesOf[skin]
	if cached then
		return cached
	end
	local ids: { string } = {}
	local function add(source: Instance, property: string)
		local uri = contentUri(source, property)
		if uri and not table.find(ids, uri) then
			table.insert(ids, uri)
		end
	end
	local sources: { Instance } = if skin:IsA("Model") then skin:GetDescendants() else { skin }
	for _, source in sources do
		if source:IsA("SurfaceAppearance") then
			for _, property in MAPS do
				add(source, property)
			end
		elseif source:IsA("MeshPart") then
			add(source, "MeshContent")
			add(source, "TextureContent")
		end
	end
	texturesOf[skin] = ids
	return ids
end

local function status(uri: string): Enum.AssetFetchStatus?
	local ok, result = pcall(function()
		return ContentProvider:GetAssetFetchStatus(uri)
	end)
	return if ok then result else nil
end

local function fetch(uri: string)
	fetching[uri] = true
	local n = (tries[uri] or 0) + 1
	tries[uri] = n
	retryAt[uri] = os.clock() + math.min(2 ^ n, RETRY_MOST)
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({ uri })
		end)
		fetching[uri] = false
	end)
end

-- Whether every texture of `skin` has arrived (starting or retrying the downloads
-- that haven't). Anything that isn't a SurfaceAppearance or a Model is loaded.
local function allLoaded(skin: Instance): boolean
	local pretend = pretending[skin]
	if pretend then
		local now = os.clock()
		if now < pretend.untilAt then
			if now >= pretend.retryAt then
				pretend.tries += 1
				local wait = math.min(2 ^ pretend.tries, RETRY_MOST)
				pretend.retryAt = now + wait
				print(
					`[SkinLoader] test: {skin.Parent and skin.Parent.Name or "?"}.{skin.Name} try {pretend.tries} failed (pretend), {string.format(
						"%.0f",
						now - (pretend.untilAt - TEST_SECONDS)
					)} s in, next try in {wait} s`
				)
			end
			return false
		end
		pretending[skin] = nil
		print(
			`[SkinLoader] test: {skin.Parent and skin.Parent.Name or "?"}.{skin.Name} arrived, put on afresh`
		)
	end
	if not (skin:IsA("SurfaceAppearance") or skin:IsA("Model")) then
		return true
	end
	local all = true
	for _, uri in textures(skin) do
		if loaded[uri] then
			continue
		end
		local state = status(uri)
		if state == Enum.AssetFetchStatus.Success or state == nil then
			loaded[uri] = true
			continue
		end
		all = false
		if
			state ~= Enum.AssetFetchStatus.Loading
			and not fetching[uri]
			and (tries[uri] or 0) < TRIES_MOST
			and os.clock() >= (retryAt[uri] or 0)
		then
			fetch(uri)
		end
	end
	return all
end

-- "loaded" (every texture is here), "waiting" (not yet: show the stand-in) or
-- "trying" (waited GIVE_UP: worn anyway while the fetches carry on)
function SkinLoader.state(skin: Instance): string
	if allLoaded(skin) then
		firstAsked[skin] = nil
		return "loaded"
	end
	local since = firstAsked[skin]
	if since == nil then
		since = os.clock()
		firstAsked[skin] = since
	end
	return if os.clock() - since < GIVE_UP then "waiting" else "trying"
end

-- Admin test: `skin` pretends its download fails for TEST_SECONDS from now
function SkinLoader.claimTest(skin: Instance)
	local now = os.clock()
	pretending[skin] = { untilAt = now + TEST_SECONDS, tries = 0, retryAt = now }
	firstAsked[skin] = now
	print(
		`[SkinLoader] test: {skin.Parent and skin.Parent.Name or "?"}.{skin.Name} pretends to fail for {TEST_SECONDS} s (the stand-in, worn anyway at {GIVE_UP} s)`
	)
end

-- Whether to put `skin` on now (Cosmetics' skinReady)
function SkinLoader.ready(skin: Instance): boolean
	return SkinLoader.state(skin) ~= "waiting"
end

return SkinLoader
