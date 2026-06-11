/** Navigation scroll effect + mobile toggle */
export function initNav() {
    const nav = document.getElementById('navbar');
    if (!nav) return;

    // Scroll shadow
    window.addEventListener('scroll', () => {
        nav.classList.toggle('scrolled', window.scrollY > 10);
    }, { passive: true });

    // Mobile hamburger
    const toggle = nav.querySelector('.nav-toggle');
    const links = nav.querySelector('.nav-links');
    if (toggle && links) {
        const setOpen = (open) => {
            links.classList.toggle('open', open);
            toggle.setAttribute('aria-expanded', String(open));
        };
        toggle.addEventListener('click', () => {
            setOpen(!links.classList.contains('open'));
        });

        // Close on link click
        links.querySelectorAll('a').forEach(a => {
            a.addEventListener('click', () => setOpen(false));
        });
    }

    // Smooth scroll for in-page anchor links
    document.querySelectorAll('a[href^="#"]').forEach(a => {
        a.addEventListener('click', (e) => {
            const hash = a.getAttribute('href');
            if (!hash || hash === '#') return; // bare "#" (logo) → no smooth scroll
            const target = document.querySelector(hash);
            if (target) {
                e.preventDefault();
                target.scrollIntoView({ behavior: 'smooth', block: 'start' });
            }
        });
    });
}
