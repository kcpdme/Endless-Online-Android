extends RefCounted
## Shared shop/inventory previews from the installed native pet definitions.

static func summon(game: Node, item: Dictionary) -> Dictionary:
	return (game.online.catalog.get("spells", {}) as Dictionary).get(str(int(item.get("hatch_spell", 0))), {}) as Dictionary

static func texture(game: Node, item: Dictionary) -> Texture2D:
	var pet: Dictionary = summon(game, item).get("companion", {}) as Dictionary
	var npc: Dictionary = (game.online.catalog.get("npcs", {}) as Dictionary).get(str(int(pet.get("npc_id", 0))), {}) as Dictionary
	var art: Dictionary = ((game.manifest.get("characters", {}) as Dictionary).get("npcs", {}) as Dictionary).get(str(int(npc.get("graphic", 0))), {}) as Dictionary
	var pose: Dictionary = game._frame(art, "south", "idle", 0.0)
	return game._texture(str(pose.get("path", "")))

static func combat_text(pet: Dictionary) -> String:
	return "%s tier · Owner attack ×%.2f\nAccuracy +%d · Hit limit %d%%\nTarget evasion still affects hits. All pets in this tier share combat stats and effects." % [str(pet.get("tier_name", "Spirit")), float(pet.get("power", 1.0)), int(pet.get("accuracy", 0)), roundi(float(pet.get("hit_cap", 0.95)) * 100.0)]

static func description(game: Node, item: Dictionary) -> String:
	var skill: Dictionary = summon(game, item)
	var pet: Dictionary = skill.get("companion", {}) as Dictionary
	return "%s\n\nSummoner level %d · Call %d TP\nUpkeep %d TP every 2 seconds\nDamage scales from your equipped attack stat, before target defence.\n\nHatch to create one living bond, then cast its summon. Death breaks the bond; hatch another egg afterward. Spare eggs stay safe.\n\nBound: cannot trade, drop, sell or share in a chest. Defends you when an aggressive monster hurts you. Monsters never target the pet. Travel, logout, dismissal and TP exhaustion keep the bond. Release a bond at a skill master to choose another pet; the used egg is not returned." % [combat_text(pet), int(item.get("level_requirement", 1)), int(skill.get("tp", 0)), int(pet.get("upkeep", 0))]
