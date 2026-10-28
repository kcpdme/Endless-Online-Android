extends RefCounted
static func describe(item: Dictionary) -> String:
	var lines: Array[String] = []
	if item.has("range_tiles"):
		lines.append("Bow range: %d tiles · Fire rate ×%s" % [int(item.range_tiles), str(item.get("attack_speed", 1))])
		lines.append("Basic shot impact: %d%% · arrow range adds to bow range" % roundi(float(item.get("shot_power", 1)) * 100))
	if item.has("range_bonus"): lines.append("Arrow range bonus: +%d tiles" % int(item.range_bonus))
	if item.has("warrior_shield_multiplier"): lines.append("Warrior shield armour: +%d (×2 base armour)" % (int(item.get("armor", 0)) * 2))
	return "\n".join(lines)
