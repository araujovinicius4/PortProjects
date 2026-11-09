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
