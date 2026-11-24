--!strict
-- How far this client draws, as a share of full range (1 = everything, down to
-- SchoolController's DETAIL_LOW on a device whose frames crawl). SchoolController works
-- it out from the frame time and writes it here every frame; the others that scale with
-- it read it (the kelp's sway, the crabs, the ambient life), with no need to require
-- SchoolController. A phone or tablet starts under 1 (docs/GAMEPLAN.md round 1 item 16).
local Detail = {
	value = 1,
}

return Detail
