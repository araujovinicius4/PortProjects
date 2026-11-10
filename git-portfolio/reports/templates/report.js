// Move panels outside the scrolling table so they cannot be clipped.
let activeProblem = null;
document.querySelectorAll('.project-description').forEach((wrapper, index) => {
    const trigger = wrapper.querySelector('.project-name');
    const panel = wrapper.querySelector('.problem-panel');
    panel.id = `problem-${index}`;
    trigger.setAttribute('aria-describedby', panel.id);
    document.body.appendChild(panel);
    let timer;
    function position() {
        const rect = trigger.getBoundingClientRect();
        const width = panel.offsetWidth;
        const height = panel.offsetHeight;
        panel.style.left = `${Math.max(8, Math.min(rect.left, innerWidth - width - 8))}px`;
        const top = rect.bottom + 8 + height <= innerHeight ? rect.bottom + 8 : rect.top - height - 8;
        panel.style.top = `${Math.max(8, Math.min(top, innerHeight - height - 8))}px`;
    }
    function close() {
        clearTimeout(timer);
        panel.hidden = true;
        trigger.setAttribute('aria-expanded', 'false');
        if (activeProblem === close) activeProblem = null;
    }
    function open() {
        clearTimeout(timer);
        if (activeProblem && activeProblem !== close) activeProblem();
        panel.hidden = false;
        trigger.setAttribute('aria-expanded', 'true');
        activeProblem = close;
        position();
    }
    function scheduleClose() { timer = setTimeout(close, 180); }
    trigger.addEventListener('mouseenter', open);
    trigger.addEventListener('mouseleave', scheduleClose);
    trigger.addEventListener('focus', open);
    trigger.addEventListener('blur', scheduleClose);
    trigger.addEventListener('click', open);
    panel.addEventListener('mouseenter', () => clearTimeout(timer));
    panel.addEventListener('mouseleave', scheduleClose);
    window.addEventListener('resize', () => { if (!panel.hidden) position(); });
    document.addEventListener('scroll', () => { if (!panel.hidden) position(); }, true);
    document.addEventListener('click', event => {
        if (!wrapper.contains(event.target) && !panel.contains(event.target)) close();
    });
});
document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && activeProblem) activeProblem();
});

function fallbackCopy(value) {
    const focused = document.activeElement;
    const field = document.createElement('textarea');
    field.value = value;
    field.setAttribute('readonly', '');
    field.style.position = 'fixed';
    field.style.opacity = '0';
    document.body.appendChild(field);
    try {
        field.select();
        if (!document.execCommand('copy')) throw new Error('Falha ao copiar');
    } finally {
        field.remove();
        if (focused) focused.focus({preventScroll: true});
    }
}

document.querySelectorAll('.copy-remote').forEach(button => {
    button.setAttribute('aria-live', 'polite');
    button.addEventListener('click', async () => {
        clearTimeout(button.copyTimer);
        try {
            try {
                if (!navigator.clipboard || !navigator.clipboard.writeText) {
                    throw new Error('Clipboard indisponível');
                }
                await navigator.clipboard.writeText(button.dataset.remote);
            } catch (_) {
                fallbackCopy(button.dataset.remote);
            }
            button.textContent = 'Copiado!';
        } catch (_) {
            button.textContent = 'Falha ao copiar';
        }
        button.copyTimer = setTimeout(() => { button.textContent = 'Copiar'; }, 2000);
    });
});
