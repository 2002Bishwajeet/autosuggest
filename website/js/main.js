/** Main entry point — orchestrates all modules */
import { initNav } from './nav.js';
import { initReveal } from './reveal.js';
import { initDemo } from './demo.js';
import { initClipboard } from './clipboard.js';
import { initFaq } from './faq.js';

document.addEventListener('DOMContentLoaded', () => {
    initNav();
    initReveal();
    initDemo();
    initClipboard();
    initFaq();
});
