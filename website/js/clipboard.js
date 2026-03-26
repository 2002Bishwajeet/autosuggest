/** Copy-to-clipboard for install commands */
export function initClipboard() {
    document.querySelectorAll('[data-copy]').forEach(el => {
        el.addEventListener('click', () => {
            const text = el.dataset.copy;
            navigator.clipboard.writeText(text).then(() => {
                const original = el.innerHTML;
                el.innerHTML = '<span style="color: var(--green);">Copied to clipboard!</span>';
                setTimeout(() => { el.innerHTML = original; }, 1800);
            });
        });
    });
}
