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
	"xc_party_hat",
	"xc_pharaoh_headdress",
	"xc_turban",
	"xc_royal_crown",
]
const GLASSES := [
	"xc_disguise_glasses",
	"xc_cyclops_glasses",
	"xc_monocle_glasses",
	"xc_eyepatch_glasses",
	"xc_tanning_glasses",
	"xc_scuba_glasses",
	"xc_3d_glasses",
	"xc_nightvision_glasses",
	"xc_snow_glasses",
]
const NO_GLASSES_HATS := ["xc_diving_helmet", "xc_dragonborn_helmet"]
# The cloth's mid-tone; suit_recolor.gd keeps the suit's own painted shading
# around it. Picked from in-game renders: change one only with a new pick.
# The order is the lobby's step order and the online screen's swatch order
# (the owner's): teal, then warm to cool, then the neutrals light to dark.
const COLORS := {
	"xc_teal": Color8(42, 85, 82),
	"xc_pink": Color8(139, 76, 91),
	"xc_orange": Color8(144, 85, 44),
	"xc_brown": Color8(86, 62, 44),
	"xc_lime": Color8(116, 160, 42),
	"xc_white": Color8(161, 156, 143),
	"xc_charcoal": Color8(52, 58, 74),
}
# The online screen's swatch, where the mid-tone would read as another colour
# there: the screen posterizes, and charcoal's cool mid-tone lands on the
# game's blue. Picked from renders of the screen.
const SWATCHES := {"xc_charcoal": Color8(92, 92, 92)}
