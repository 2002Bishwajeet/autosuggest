/** FAQ accordion — native <details>, made exclusive (one open at a time),
 *  matching the design's single-open accordion. The chevron rotation and the
 *  reveal animation are pure CSS, so this only enforces exclusivity. */
export function initFaq() {
    const items = Array.from(document.querySelectorAll('.faq-item'));
    if (!items.length) return;

    items.forEach(item => {
        item.addEventListener('toggle', () => {
            if (!item.open) return;
            items.forEach(other => { if (other !== item) other.open = false; });
        });
    });
}
