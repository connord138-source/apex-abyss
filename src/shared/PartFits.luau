--!strict
-- Where each per-fish rolled part model sits on its fish (owner, 2026-11-03: parts must
-- "actual blend as a variant/mutation of that fish"). Written by tools/props/parts_fit.py
-- from assets/glb/parts/fit/seats.json; rebuild rather than edit by hand.
--
-- Each model (assets/glb/parts/fit/<Fish>_<PartId>.glb, ReplicatedStorage.PartModels.
-- <Fish>_<PartId>) was authored in its fish's unit box, seated into that fish's own mesh.
-- A MeshPart is centred on its mesh's box, so a seat is just that box in the fish's root
-- space at 1 stud long (nose at z -0.5): `center` and `size`. `bone` is the bone it rides
-- (Cosmetics.follow), `skin` the fish's natural colour at its root, `gem` and `gemSize` where a
-- lure's crystal is (its middle; across and long).
local PartFits = {}

export type Seat = {
	bone: string,
	center: Vector3,
	size: Vector3,
	skin: Color3,
	gem: Vector3?,
	gemSize: Vector2?,
}

PartFits.SEATS = {
	Nibbler = {
		AnglerLure = {
			bone = "Head",
			center = Vector3.new(-0.02286, 0.27694, -0.48685),
			size = Vector3.new(0.13219, 0.44456, 0.43693),
			skin = Color3.fromRGB(213, 104, 55),
			gem = Vector3.new(-0.02677, 0.20545, -0.65713),
			gemSize = Vector2.new(0.1, 0.13),
		},
		NarwhalHorn = {
			bone = "Head",
			center = Vector3.new(-0.01944, 0.18751, -0.65788),
			size = Vector3.new(0.16493, 0.33446, 0.56256),
			skin = Color3.fromRGB(213, 103, 54),
		},
		SawSnout = {
			bone = "Head",
			center = Vector3.new(-0.02791, -0.03438, -0.74943),
			size = Vector3.new(0.18365, 0.09821, 0.66756),
			skin = Color3.fromRGB(212, 104, 54),
		},
		SailFin = {
			bone = "Spine2",
			center = Vector3.new(-0.00092, 0.3659, -0.065),
			size = Vector3.new(0.12142, 0.5054, 0.53),
			skin = Color3.fromRGB(212, 103, 54),
		},
		VeilTail = {
			bone = "Tail",
			center = Vector3.new(-0.09363, -0.0505, 0.49106),
			size = Vector3.new(0.37329, 0.99025, 0.42797),
			skin = Color3.fromRGB(199, 184, 150),
		},
	},
	Cuda = {
		AnglerLure = {
			bone = "Head",
			center = Vector3.new(-0.00044, 0.0658, -0.4281),
			size = Vector3.new(0.06776, 0.25724, 0.28939),
			skin = Color3.fromRGB(93, 116, 132),
			gem = Vector3.new(-0.00052, 0.02855, -0.54646),
			gemSize = Vector2.new(0.054, 0.075),
		},
		NarwhalHorn = {
			bone = "Head",
			center = Vector3.new(-0.00123, -0.028, -0.61049),
			size = Vector3.new(0.06211, 0.05742, 0.41735),
			skin = Color3.fromRGB(94, 116, 132),
		},
		SawSnout = {
			bone = "Head",
			center = Vector3.new(-0.00092, -0.02865, -0.65207),
			size = Vector3.new(0.09314, 0.04811, 0.46373),
			skin = Color3.fromRGB(94, 117, 131),
		},
		SailFin = {
			bone = "Spine2",
			center = Vector3.new(0.0003, 0.19195, -0.06),
			size = Vector3.new(0.06904, 0.28809, 0.28),
			skin = Color3.fromRGB(94, 117, 133),
		},
		VeilTail = {
			bone = "Tail",
			center = Vector3.new(0.00126, -0.00655, 0.47996),
			size = Vector3.new(0.08514, 0.88413, 0.30498),
			skin = Color3.fromRGB(186, 194, 204),
		},
	},
	Puffer = {
		AnglerLure = {
			bone = "Head",
			center = Vector3.new(0.00562, 0.32459, -0.46132),
			size = Vector3.new(0.11871, 0.40985, 0.42072),
			skin = Color3.fromRGB(128, 91, 66),
			gem = Vector3.new(0.00757, 0.25966, -0.6272),
			gemSize = Vector2.new(0.092, 0.12),
		},
		NarwhalHorn = {
			bone = "Head",
			center = Vector3.new(-0.00113, 0.18214, -0.66036),
			size = Vector3.new(0.13588, 0.31673, 0.46581),
			skin = Color3.fromRGB(128, 91, 67),
		},
		SawSnout = {
			bone = "Head",
			center = Vector3.new(0.00394, 0.05012, -0.7457),
			size = Vector3.new(0.15904, 0.08401, 0.59631),
			skin = Color3.fromRGB(136, 96, 72),
		},
		SailFin = {
			bone = "Spine2",
			center = Vector3.new(-0.00178, 0.39227, -0.09),
			size = Vector3.new(0.10487, 0.39254, 0.44),
			skin = Color3.fromRGB(127, 90, 66),
		},
		VeilTail = {
			bone = "Tail",
			center = Vector3.new(-0.02683, -0.01972, 0.53271),
			size = Vector3.new(0.10031, 0.67563, 0.39914),
			skin = Color3.fromRGB(133, 93, 67),
		},
	},
	MorayEel = {
		AnglerLure = {
			bone = "Head",
			center = Vector3.new(-0.01555, 0.06983, -0.45963),
			size = Vector3.new(0.06365, 0.22532, 0.24921),
			skin = Color3.fromRGB(101, 108, 32),
			gem = Vector3.new(-0.01728, 0.03773, -0.56098),
			gemSize = Vector2.new(0.048, 0.065),
		},
		NarwhalHorn = {
			bone = "Head",
			center = Vector3.new(-0.01755, -0.0101, -0.60068),
			size = Vector3.new(0.06265, 0.0496, 0.33532),
			skin = Color3.fromRGB(75, 82, 14),
		},
		SawSnout = {
			bone = "Head",
			center = Vector3.new(-0.02963, -0.01222, -0.63119),
			size = Vector3.new(0.09374, 0.04322, 0.40408),
			skin = Color3.fromRGB(91, 95, 26),
		},
		SailFin = {
			bone = "Spine3",
			center = Vector3.new(0.0044, 0.12552, -0.07),
			size = Vector3.new(0.08885, 0.23476, 0.58),
			skin = Color3.fromRGB(99, 103, 25),
		},
		VeilTail = {
			bone = "Tail",
			center = Vector3.new(-0.02687, 0.0052, 0.52052),
			size = Vector3.new(0.084, 0.37928, 0.33496),
			skin = Color3.fromRGB(71, 84, 3),
		},
	},
	ReefShark = {
		AnglerLure = {
			bone = "Head",
			center = Vector3.new(0.03502, 0.06315, -0.45348),
			size = Vector3.new(0.08624, 0.26696, 0.30467),
			skin = Color3.fromRGB(108, 115, 123),
			gem = Vector3.new(0.04047, 0.02645, -0.5766),
			gemSize = Vector2.new(0.06, 0.08),
		},
		NarwhalHorn = {
			bone = "Head",
			center = Vector3.new(0.04138, -0.03007, -0.64814),
			size = Vector3.new(0.07844, 0.04709, 0.41884),
			skin = Color3.fromRGB(107, 114, 122),
		},
		SawSnout = {
			bone = "Head",
			center = Vector3.new(0.0649, -0.03163, -0.67815),
			size = Vector3.new(0.12973, 0.04872, 0.48625),
			skin = Color3.fromRGB(108, 115, 122),
		},
		SailFin = {
			bone = "Spine2",
			center = Vector3.new(0.00164, 0.209, -0.0675),
			size = Vector3.new(0.07987, 0.3775, 0.345),
			skin = Color3.fromRGB(108, 115, 122),
		},
		VeilTail = {
			bone = "Tail",
			center = Vector3.new(0.04548, 0.00779, 0.4599),
			size = Vector3.new(0.12118, 0.78139, 0.33861),
			skin = Color3.fromRGB(108, 115, 121),
		},
	},
	Angler = {
		AnglerLure = {
			bone = "Head",
			center = Vector3.new(0.00371, 0.17545, -0.3063),
			size = Vector3.new(0.15413, 0.40149, 0.40395),
			skin = Color3.fromRGB(36, 72, 108),
			gem = Vector3.new(0.00362, 0.1902, -0.45),
			gemSize = Vector2.new(0.124, 0.19),
		},
		NarwhalHorn = {
			bone = "Head",
			center = Vector3.new(0.00038, 0.11126, -0.45829),
			size = Vector3.new(0.09706, 0.09602, 0.48729),
			skin = Color3.fromRGB(35, 64, 95),
		},
		SawSnout = {
			bone = "Head",
			center = Vector3.new(0.00281, 0.09891, -0.50431),
			size = Vector3.new(0.12434, 0.09792, 0.56385),
			skin = Color3.fromRGB(37, 63, 94),
		},
		SailFin = {
			bone = "Spine3",
			center = Vector3.new(0.00059, 0.27951, 0.06),
			size = Vector3.new(0.074, 0.47903, 0.38),
			skin = Color3.fromRGB(31, 56, 86),
		},
		VeilTail = {
			bone = "Tail",
			center = Vector3.new(-0.00193, 0.01039, 0.52111),
			size = Vector3.new(0.06383, 0.7606, 0.38879),
			skin = Color3.fromRGB(34, 49, 75),
		},
	},
} :: { [string]: { [string]: Seat } }

-- The seat of a part on a fish model (Body's MeshPlan), and the name its model is filed
-- under; nil for a body with no fitted models (a variant's own mesh)
function PartFits.seat(meshPlan: string?, partId: string): (Seat?, string)
	local seats = if meshPlan then PartFits.SEATS[meshPlan] else nil
	return if seats then seats[partId] else nil, `{meshPlan or ""}_{partId}`
end

return PartFits
