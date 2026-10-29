extends RefCounted
## Shared shop/inventory previews from the installed native pet definitions.

static func summon(game: Node, item: Dictionary) -> Dictionary:
	return (game.online.catalog.get("spells", {}) as Dictionary).get(str(int(item.get("hatch_spell", 0))), {}) as Dictionary

static func texture(game: Node, item: Dictionary) -> Texture2D:
	var pet: Dictionary = summon(game, item).get("companion", {}) as Dictionary
	var npc: Dictionary = (game.online.catalog.get("npcs", {}) as Dictionary).get(str(int(pet.get("npc_id", 0))), {}) as Dictionary
	var art: Dictionary = ((game.manifest.get("characters", {}) as Dictionary).get("npcs", {}) as Dictionary).get(str(int(npc.get("graphic", 0))), {}) as Dictionary
	var pose: Dictionary = game._frame(art, "south", "idle", 0.0)
	var texture: Texture2D = game._texture(str(pose.get("path", "")))
	if texture == null or not pose.has("region"): return texture
	var region: Array = pose.region
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(float(region[0]),float(region[1]),float(region[2]),float(region[3]))
	atlas.filter_clip = true
	return atlas

static func combat_text(pet: Dictionary) -> String:
	return "%s tier · Owner attack ×%.2f\nAccuracy +%d · Hit limit %d%%\nTarget evasion still affects hits. All pets in this tier share combat stats and effects." % [str(pet.get("tier_name", "Spirit")), float(pet.get("power", 1.0)), int(pet.get("accuracy", 0)), roundi(float(pet.get("hit_cap", 0.95)) * 100.0)]

static func description(game: Node, item: Dictionary) -> String:
	var skill: Dictionary = summon(game, item)
	var pet: Dictionary = skill.get("companion", {}) as Dictionary
	var state_text: String="Hatched Egg · permanent bound keepsake. Cannot be sold, traded, dropped or discarded. Choose this pet with the top egg icon, or use Bind in Inventory." if item.get("egg_state", "") == "hatched" else "Hatch once to unlock this species permanently and receive its Hatched Egg. Spare unhatched Eggs sell to Aeven Eggkeeper for %d Gold (40%% of shop price)." % int(item.get("egg_sell_value", 0))
	return "%s\n\nSummoner level %d · Call %d TP\nUpkeep %.1f%% max TP every 2 seconds\n\n%s\n\nOne active pet. Dismissal, TP exhaustion and death start a shared 5-minute recovery; no pet can be rebound or called during it. Pets survive every death, including PK and arena. Travel and logout keep them without starting recovery. Pets defend you from aggressive monsters; monsters never target the pet." % [combat_text(pet), int(item.get("level_requirement", 1)), int(skill.get("tp", 0)), float(pet.get("upkeep_rate", 0))*100, state_text]
