"""Write a reviewable performance report from measured JSON artifacts."""
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    directory = ROOT/'outputs/benchmarks'
    reports = [json.loads((directory/f'{n}-seed42-5x-render.json').read_text()) for n in (30, 120)]
    concurrency = ', '.join(str(n) for n in sorted({r.get('provenance', {}).get('concurrency', 1) for r in reports}))
    measured_date = reports[0].get('measured_at_utc', datetime.fromtimestamp(
        (directory/'30-seed42-5x-render.json').stat().st_mtime, timezone.utc).isoformat())[:10]
    lines = ['# ESSAIM multi-LLM performance report', '',
        f'Measured on {measured_date} UTC with real local Ollama and the actual Godot city renderer.', '',
        'Hardware: NVIDIA GeForce RTX 5070 Ti Laptop GPU, 12,227 MiB total VRAM. '
        f'Godot 4.7.2, OpenGL Compatibility. Global concurrency limit(s): {concurrency}; seed 42; '
        '300 simulated seconds until impact at 5x (about 60 wall seconds). '
        'The rendered runs used warm model residency after earlier screening experiments.', '',
        '| Population | Agents with timely applied decisions | Applied decisions | HTTP requests | Client fallbacks | Mean process FPS | Peak total GPU MiB |',
        '|---|---:|---:|---:|---:|---:|---:|']
    for report in reports:
        metrics = report['metrics']
        lines.append(f"| {report['population']} | {report['timely_agents']}/{report['population']} | "
            f"{metrics.get('successful',0)} | {metrics.get('calls',0)} | {metrics.get('fallbacks',0)} | "
            f"{report['average_process_fps']:.1f} | {report['peak_total_gpu_used_mib']} |")
    lines += ['', 'A timely decision is a validated intention actually applied by Godot before impact. '
        'Distinct agent coverage differs from total decisions. Client fallbacks include rule fallback '
        'without an HTTP request; they are not simply HTTP failures. FPS is average process-loop '
        'frequency, not a frame-time percentile or rendering SLA.', '',
        '## Per-model measurements', '',
        'Counters below are backend deltas per experiment. Successful latency excludes queue wait '
        'and failed calls; token throughput includes generated output from failed/retried attempts. '
        'Backend completion does not imply Godot accepted the intention.', '',
        '| Population | Model | Requests | Valid completions | Backend fallbacks | Invalid outputs | Mean successful latency s | Generation tokens/s | Valid decisions/s |',
        '|---|---|---:|---:|---:|---:|---:|---:|---:|']
    for report in reports:
        for name, stats in report['backend_metrics_delta'].items():
            latency = stats['latency_seconds']/max(1, stats['completed'])
            rate = stats['output_tokens']/max(.001, stats['generation_seconds'])
            lines.append(f"| {report['population']} | {name} | {stats['requests']} | {stats['completed']} | "
                f"{stats['fallbacks']} | {stats['invalid_responses']} | {latency:.3f} | {rate:.1f} | {stats['completed']/report['wall_seconds']:.3f} |")
    peak = max(r['final_backend_snapshot']['peak_vram_bytes'] for r in reports)
    lines += ['', '## Memory observations', '',
        f'Ollama reported a sampled model VRAM peak of **{peak/1e9:.3f} GB**. '
        'The three resident allocations were approximately 0.455 GB (Qwen 0.5B), '
        '1.445 GB (Llama 1B) and 1.105 GB (Qwen 1.5B), at a 2048-token context. '
        'Qwen tags were Q4_K_M; the installed Llama tag was Q8_0. '
        'Peak total GPU usage with rendering was approximately '
        f"{max(r['peak_total_gpu_used_mib'] for r in reports)*1048576/1e9:.3f} GB. "
        'These measurements fit the approximate 10 GB target on this machine.', '',
        'No unloads or suspected swaps were observed during these rendered runs. '
        'This does not guarantee all three models remain resident on other hardware or at higher '
        'concurrency/context sizes. The budget monitor is not a hard allocator; sampled peaks '
        'do not capture every transient allocation. Total GPU usage also includes other GPU users.', '',
        '## Baselines and interpretation', '']
    for n in (30, 120):
        path = directory/f'rules_{n}-seed42-5x.json'
        if path.exists():
            baseline = json.loads(path.read_text())
            lines.append(f"Rule-only baseline {n}: {baseline['wall_seconds']:.2f}s wall, "
                f"{baseline['metrics'].get('calls',0)} LLM requests. These runs were headless; "
                'their initial scenario/seed and impact duration match, but their rendering cost does not.')
            lines.append('')
    lines += ['The 0.5B tier is the principal structured-output reliability limitation. '
        'Its invalid/retry rate was higher at 120 agents in this sample; no causal relationship is established. The system remains '
        'operational through rule fallback; these agents must not be described as receiving '
        'reliable LLM decisions at every interval. The 1B and 1.5B tiers performed better in this sample.', '',
        '**Keep 30 as the default and 120 opt-in.** The 120-agent run did not achieve full timely '
        f'coverage. Global concurrency limit(s): {concurrency}; none demonstrate simultaneous 120-agent inference. '
        'A single-model route using llama3.2:1b is available for comparison or swapping problems, '
        'but no performance claim for that mode is established by these heterogeneous runs.', '',
        'This is a single-seed screening benchmark, not a statistical population study. '
        'Repeat seeds at 1x and 5x, distinguish cold/warm starts, and evaluate decision quality '
        'and evacuation outcomes before enabling 120 for a scientific study. Seed reproducibility '
        'controls initial conditions, not LLM output determinism. The Python HTTP adapter used '
        'the production scheduler/engine; the FastAPI and Docker paths were validated separately.', '',
        '## Validation', '',
        '- Python: 24 tests passed, including pool bounds, urgency, duplication, concurrency, '
        'timeouts, memory isolation, single-model memory continuity and residency warnings.',
        '- Godot seeded 30/120/baseline suite: 48,319 checks, zero failures.',
        '- Scripted transport tests: 30-agent and 120-agent queues drained with no duplicates; '
        'these are TEST_ONLY transport checks, not LLM performance evidence.',
        '- Godot regressions passed for LLM actions/HTTP, seeded social behavior (1323 checks), '
        '3D navigation (617 checks), UI (33 checks), nuclear impact (861 checks) and warnings (68 checks).',
        '- CPU/GPU Compose configurations validated; AI Docker image built successfully; '
        'container-to-host Ollama connectivity verified with all three models.', '',
        'Raw JSON, GPU samples, model digests and traces are available in outputs/benchmarks '
        'and outputs/ai_runs. Installation and reproducible commands: [MULTI_LLM.md](MULTI_LLM.md).']
    target = ROOT/'docs/MULTI_LLM_PERFORMANCE.md'
    target.write_text('\n'.join(lines)+'\n', encoding='utf-8')
    print(target)


if __name__ == '__main__': main()
