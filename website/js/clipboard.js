/** Copy-to-clipboard for install commands & code blocks.
 *  Each copyable block is `.code-block[data-copy]` containing a `.code-copy`
 *  button. Clicking the button (or the block) copies and flips the label to
 *  "copied" (green) for 1.6s, matching the design's CodeBlock. */
export function initClipboard() {
    document.querySelectorAll('[data-copy]').forEach(block => {
        const btn = block.querySelector('.code-copy');
        const text = block.dataset.copy;

        const copy = () => {
            if (!navigator.clipboard || !text) return;
            navigator.clipboard.writeText(text).then(() => {
                if (!btn) return;
                btn.textContent = 'copied';
                btn.classList.add('copied');
                setTimeout(() => {
                    btn.textContent = 'copy';
                    btn.classList.remove('copied');
                }, 1600);
            }).catch(() => {});
        };

        if (btn) btn.addEventListener('click', (e) => { e.stopPropagation(); copy(); });
        block.addEventListener('click', copy);
    });
}
