extends RefCounted

# Our cosmetic ids. Saves and peers carry them as plain strings, so a released
# id never changes. Glasses ids contain "glasses" because the online screen
# picks the slot with `"glasses" in name`; hat and color ids never do.

const HATS := [
	"xc_propeller_beanie",
	"xc_army_helmet",
	"xc_diving_helmet",
	"xc_chef_hat",
	"xc_captain_hat",
	"xc_sombrero",
	"xc_head_mirror",
	"xc_fez",
	"xc_kippah",
	"xc_trapper_hat",
	"xc_football_helmet",
	"xc_beret",
	"xc_dragonborn_helmet",
]
const GLASSES := [
	"xc_disguise_glasses",
	"xc_cyclops_glasses",
	"xc_monocle_glasses",
	"xc_eyepatch_glasses",
	"xc_tanning_glasses",
	"xc_scuba_glasses",
]
const NO_GLASSES_HATS := ["xc_diving_helmet", "xc_dragonborn_helmet"]
# The cloth's mid-tone; suit_recolor.gd keeps the suit's own painted shading
# around it. The owner's picks (plan, Phase 4): change one only with a new pick.
const COLORS := {
	"xc_teal": Color8(42, 85, 82),
	"xc_pink": Color8(139, 76, 91),
	"xc_white": Color8(161, 156, 143),
	"xc_brown": Color8(86, 62, 44),
	"xc_orange": Color8(144, 85, 44),
}
