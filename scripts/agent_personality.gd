extends RefCounted
## Tendencies blended with individual trait variation; no archetype guarantees an outcome.

const TYPES := ["PANICKED", "SKEPTICAL", "GULLIBLE", "DENIAL", "FAMILY-ORIENTED", "SURVIVALIST", "COOPERATIVE", "AGGRESSIVE", "LEADER", "FOLLOWER", "SELF-SACRIFICING", "OVERWHELMED", "OPTIMISTIC", "CAUTIOUS", "OPPORTUNISTIC"]
const TRAITS := ["panic_level", "trust_level", "skepticism", "cooperation", "risk_tolerance", "self_preservation", "empathy", "authority_trust", "sociability"]
const MEANS := [
	[75,50,35,40,65,75,40,50,50], [30,30,85,45,40,65,50,40,35],
	[40,85,15,60,60,55,65,75,70], [25,40,65,40,70,50,45,30,35],
	[45,65,45,75,45,55,85,60,70], [25,40,60,30,55,90,40,55,25],
	[35,70,40,90,40,50,85,65,85], [55,30,35,15,85,90,20,30,40],
	[30,65,45,80,55,65,75,75,90], [45,80,30,65,45,60,60,70,85],
	[40,65,35,95,60,25,95,65,70], [65,50,50,40,30,55,65,55,40],
	[25,75,25,60,75,50,65,65,65], [35,45,70,50,15,75,60,60,40],
	[30,50,45,35,70,85,35,50,60]]

static func assign(agent: Dictionary, index: int, order: Array, rng: RandomNumberGenerator, config: Dictionary) -> void:
	var primary: String = order[index % order.size()]
	var secondary := ""
	if rng.randf() < config["secondary_personality_probability"]:
		secondary = TYPES[(TYPES.find(primary) + rng.randi_range(1, TYPES.size()-1)) % TYPES.size()]
	agent["primary_personality"] = primary
	agent["personality"] = primary
	agent["secondary_personality"] = secondary
	for i in range(TRAITS.size()):
		var mean: float = MEANS[TYPES.find(primary)][i]
		if not secondary.is_empty():
			mean = mean * 0.75 + float(MEANS[TYPES.find(secondary)][i]) * 0.25
		agent[TRAITS[i]] = clampf(mean + rng.randf_range(-config["trait_jitter"], config["trait_jitter"]), 0, 100)
	agent["trust_in_authority"] = agent["authority_trust"]
	agent["current_goal"] = "Live normally; await public warnings"
	agent["personal_memory"] = []
	agent["rumors_heard"] = []
	agent["messages"] = []
	agent["heard_ids"] = {}
	agent["shared_ids"] = {}
	agent["alarm_confidence"] = 0.65 if primary == "DENIAL" else 0.8
	agent["perceived_warning_seconds"] = rng.randf_range(config["public_warning_estimate_range"][0], config["public_warning_estimate_range"][1])
	agent["reaction_delay"] = rng.randf_range(config["denial_delay_range"][0], config["denial_delay_range"][1]) if primary == "DENIAL" else rng.randf_range(0, 4)
	if primary == "AGGRESSIVE":
		agent["admission_priority"] = int(float(agent["admission_priority"])*0.7)
		agent["reaction_delay"] *= 0.5
	agent["wait_until"] = 0.0
	agent["freeze_cooldown_until"] = 0.0
	agent["helped_ids"] = []
	agent["avoided_locations"] = []
	agent["recommendations"] = {}
	agent["companion_id"] = ""
	agent["health"] = 100.0
	agent["survival_status"] = "UNDETERMINED"
