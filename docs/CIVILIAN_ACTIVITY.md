# Civilian movement, actions and bomb descent

Start the city to see ordinary neighborhood roaming. Trigger the siren to switch
people to evacuation speed and personality-driven emergency actions.

## Movement and appearance

Default running speed is 28–52 simulation units/s (2.8–5.2 m/s at the existing
0.1 rendering scale). Walking uses 40% of that speed. Change `speed_range` in
`resources/phase1.json` and `walking_speed_fraction` in
`resources/agent_activity.json` to tune them.

People can cross lawns, parks and other clear ground. A free-space grid and
line-of-sight simplification route around building footprints and the reservoir.
Random wandering and panic detours use independent seeded random streams. The
forest's decorative trees do not act as individual navigation obstacles.

The former capsule avatars are replaced by stylized humanoids with separate
heads, torsos, arms, legs and shoes. Skin tones, hair, hats, shirts, skirts,
backpacks and authority uniforms provide variety. Limbs animate walking,
running, dancing, helping, bracing and stumbling. District labels disappear at
close camera distances so they do not obscure people.

## Personality and crowd actions

- `NIHILIST` and `DESPAIRING` are new fictional archetypes. They may choose a
  temporary defiant dance rather than immediate evacuation. This lasts a limited
  time; they can reconsider, and helping can interrupt it.
- Highly panicked people may run a short random detour before reconsidering a
  shelter. This does not reveal the impact site or hidden shelter information.
- Aggressive or highly panicked, uncooperative people can push a nearby person.
  The recipient is displaced only into clear space, stumbles briefly, remembers
  the incident, and loses trust in the pusher. A cooldown prevents constant shoving.
- A frightened person inside a shelter may start sealing its door early. The
  door changes from `CLOSING` to `CLOSED` after the configured delay and rejects
  subsequent admission. The actor and reason are recorded in shelter history
  and the Director event feed. Existing Director door controls remain available.

The LLM contract also supports `DANCE`, `FLEE_RANDOMLY`, `HELP_AGENT` and
`FOLLOW_AGENT`. Nearby-target validation and current-state validation still
apply. Physical crowd reactions continue while inference is pending.

## Countdown and bomb fall

For a real alarm, reaching zero now starts `BOMB_FALL`, rather than immediately
destroying the city. A visible plane releases a bomb, which descends for **eight
real seconds** regardless of simulation speed. During those seconds people keep
acting and may enter open shelters. Simulation speed still controls how fast
people move; at higher speeds they can cover more distance during the descent.
Pausing freezes both the descent and whistle. Reset removes the aircraft/bomb
and stops its sound. The impact then uses the existing destruction and survival
systems. False alarms end with all-clear and do not release a bomb.

`bomb_fall_seconds` lives in `resources/agent_activity.json`. Other activity
durations use simulation time. The UI displays `FALL` with the remaining descent
time. The bomb animation is cinematic rather than a ballistic flight model.

The whistle is the CC0 **Bomb Dropping.wav** by **morganpurkis**, downloaded from
its public [Freesound preview](https://freesound.org/people/morganpurkis/sounds/398255/).
The local MP3 is unchanged; playback is slowed to fit the descent.
See `assets/audio/warnings/BOMB_SOUND_LICENSE.md` for source and licensing details.

## Verification

`tests/test_civilian_activity.gd` checks roaming, speed, open-ground routes,
humanoid limbs, dancing, pushing/trust, early door closure, eight-second timing at
1× and 10×, pause/reset, late admission and audio decoding.
`tests/render_civilian_activity.gd` renders a character lineup and bomb descent,
measures nonzero whistle PCM through an audio capture bus, and checks sound
pause/reset. The lineup hides vegetation to make the character models inspectable.
Captures are saved as `outputs/civilians-skins.png` and
`outputs/civilians-bomb-fall.png`.

The map, warnings, Phase 4 and action-validation checks remain applicable. Older
tests that expect impact exactly at the end of the warning countdown need to
advance through the new eight-second descent as well. Previous evacuation
benchmarks used different speeds and timing, so rerun them before comparing.

Checkpoint before this change: `outputs/checkpoints/pre-civilian-actions.zip`.
