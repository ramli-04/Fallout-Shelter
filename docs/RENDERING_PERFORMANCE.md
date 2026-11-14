# Rendering Performance Report

## Method

The existing `tests/benchmark_visual_streaming.gd` benchmark was used with the saved 100-agent world `essaim-42-523b32dd3818c2af`. The desktop sample uses the NVIDIA GeForce RTX 5070 Ti Laptop GPU and shows 36 active avatar visuals and 97 streamed buildings. The earlier sample is `outputs/streaming/after-steady.json` (2026-11-11); the final post-animation and post-wheel-batching sample is `outputs/streaming/render-upgrade-batched.json` (2026-11-12).

These are separate runs, not a controlled capture replay. V-sync, foreground application load, and driver scheduling affect frame timings. Godot's current benchmark records CPU/sample frame times, draw calls, rendered objects, static memory, and video memory; it does not expose a reliable GPU frame-time counter in this GL Compatibility setup. No GPU timing is inferred from FPS.

## Desktop samples

| Metric | Earlier sample | Rendering upgrade | Change |
|---|---:|---:|---:|
| Simulation agents / visible avatars | 100 / 36 | 100 / 36 | Same |
| Active buildings / map buildings | 97 / 243 | 97 / 243 | Same |
| Measured sample FPS | 72.0 | 95.0 | Higher in this run; timing is not controlled |
| Frame time p50 / p95 | 7.34 / 25.28 ms | 6.94 / 23.89 ms | Lower in this run |
| Simulation + visual CPU p50 / p95 | 0.359 / 17.425 ms | 0.382 / 16.749 ms | Mixed: p50 higher, p95 lower |
| Draw calls / render objects | 1,777 / 1,777 | 1,799 / 1,799 | 22 more |
| Godot objects | 29,351 | 25,399 | 3,952 fewer |
| Scene nodes | 13,723 | 14,159 | 436 more, including per-agent skeleton/animation controllers |
| Static memory | 449.0 MB | 422.7 MB | 26.4 MB lower |
| Video memory | 63.4 MB | 55.1 MB | 8.3 MB lower |

Memory values above are decimal MB converted from the benchmark's byte counters. `render-upgrade-batched.json` is the machine-readable final sample. The medians improved in this capture, while draw calls rose by 22 and CPU p50 was slightly higher. Separate runs cannot establish a speedup because V-sync, foreground load, driver scheduling, and capture state were not fixed. Earlier same-code samples ranged from 45.7 to 51.0 measured FPS, illustrating that run-to-run spread. Repeat the same capture with V-sync and foreground load controlled before making frame-rate claims. The extra animation nodes are a known tradeoff for the shared articulated rig; animation updates run at a reduced cadence outside the 42 m full-rate range. Vehicle wheels and hubs are GPU-instanced per vehicle; 1,799 scene render instances still include the streamed city and are not a draw-call optimization claim.

## Headless diagnostic

Headless rendering tests are useful for correctness, but the dummy renderer cannot provide desktop GPU draw/video-memory counters. Do not compare headless captures to desktop samples.

## Avatar population scale

`tests/benchmark_render_population.gd` was run on the same desktop renderer for 50, 100, 250, 500, and 1,000 visible avatar nodes. It uses cloned visual records around the same saved city; it does not change the authoritative 100-agent simulation, run the AI, or validate simulation scaling. All tested characters were in the far animation LOD tier at this camera distance. These values isolate visual-scene scaling and are separate runs, so timing differences are indicative rather than a controlled GPU comparison.

| Visible avatars | Frame p50 / p95 | View sync CPU p50 / p95 | Draw calls | Static memory | Video memory |
|---:|---:|---:|---:|---:|---:|
| 50 | 6.87 / 8.76 ms | 0.44 / 0.63 ms | 1,958 | 427.2 MB | 57.4 MB |
| 100 | 7.83 / 10.86 ms | 0.78 / 1.05 ms | 2,277 | 443.2 MB | 55.5 MB |
| 250 | 13.00 / 16.64 ms | 2.31 / 2.93 ms | 3,230 | 486.3 MB | 56.2 MB |
| 500 | 21.35 / 38.43 ms | 5.22 / 5.82 ms | 4,823 | 561.3 MB | 57.4 MB |
| 1,000 | 42.17 / 84.67 ms | 10.93 / 11.65 ms | 8,006 | 706.4 MB | 59.8 MB |

The configured simulation population still caps at 400; the 500/1,000 samples are rendering-only clones and do not imply that a 1,000-agent world or its AI/traffic simulation runs at these rates. At 1,000 visible avatars, this 5070 Ti laptop sample reaches 1,000 active nodes and uses about 706 MB static memory, but the 84.67 ms p95 frame indicates the current procedural character draw cost is too high for smooth rendering. A next optimization should reduce per-character mesh submissions with a compatible skinned-mesh or GPU crowd path; the existing per-agent `AnimationTree` is retained for nearby characters.

Each run writes machine-readable values under `outputs/streaming/render-population-<count>.json`. Reproduce a sample with:

```powershell
& 'C:\Users\Moham\Downloads\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script res://tests/benchmark_render_population.gd -- 1000
```

## Follow-up profiling

- Capture repeated baseline/current runs at a fixed window size with the same V-sync setting and no other game/editor process in the foreground.
- Use RenderDoc or a GPU vendor profiler for GPU frame time; the benchmark does not provide this value.
- If CPU p95 remains above baseline, profile per-agent `AnimationTree.advance()` and streamed building construction separately before raising animation rates or mesh detail.
- Add a merged crowd-mesh or GPU-instanced distant-agent representation before targeting smooth 1,000-avatar scenes; maintain full 3D animation for nearby selected/interactive agents.
- Godot currently reports 41 ObjectDB instances and 13 resources still in use at test/benchmark shutdown. The same warning appears with the existing streaming regression test; trace ownership and cleanup before treating process-exit resource accounting as settled.
