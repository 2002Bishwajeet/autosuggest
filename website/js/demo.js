/** Hero GhostText demo — stepped line reveal on a timer.
 *  The demo lives in the hero (in view on load), so it animates on init the
 *  way the design's HeroDemo does — revealing the 5 lines one at a time
 *  (650ms apart). Under reduced motion, all lines show at once, no timers. */
export function initDemo() {
    const demoEl = document.getElementById('demo');
    if (!demoEl) return;

    const lines = Array.from(demoEl.querySelectorAll('.demo-line'));
    const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    if (reduce) {
        lines.forEach(l => l.classList.add('visible'));
        return;
    }

    let i = 0;
    const id = setInterval(() => {
        i += 1;
        const line = lines.find(l => Number(l.dataset.step) === i);
        if (line) line.classList.add('visible');
        if (i >= lines.length) clearInterval(id);
    }, 650);
}
