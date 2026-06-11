/** Demo window typing animation */
export function initDemo() {
    const demoEl = document.getElementById('demo');
    if (!demoEl) return;

    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                animateDemo();
                observer.unobserve(entry.target);
            }
        });
    }, { threshold: 0.3 });

    observer.observe(demoEl);
}

function animateDemo() {
    const lines = document.querySelectorAll('#demo .line');
    const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    lines.forEach(line => {
        if (reduce) {
            // No staggered typing animation; reveal all lines at once.
            line.classList.add('visible');
            return;
        }
        const delay = parseInt(line.dataset.delay) || 0;
        setTimeout(() => line.classList.add('visible'), delay);
    });
}
