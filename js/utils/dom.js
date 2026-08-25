// AcademicFlow — tiny DOM helpers, no framework.

export function qs(selector, root = document) {
  return root.querySelector(selector);
}

export function qsa(selector, root = document) {
  return Array.from(root.querySelectorAll(selector));
}

export function el(tag, attrs = {}, children = []) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs)) {
    if (key === 'class') node.className = value;
    else if (key === 'html') node.innerHTML = value;
    else if (key.startsWith('on') && typeof value === 'function') {
      node.addEventListener(key.slice(2).toLowerCase(), value);
    } else if (value !== undefined && value !== null) {
      node.setAttribute(key, value);
    }
  }
  for (const child of [].concat(children)) {
    if (child == null) continue;
    node.appendChild(typeof child === 'string' ? document.createTextNode(child) : child);
  }
  return node;
}

export function showToast(message, type = 'info') {
  const container = qs('#toast-container') || (() => {
    const c = el('div', { id: 'toast-container', class: 'toast-container' });
    document.body.appendChild(c);
    return c;
  })();
  const toast = el('div', { class: `toast toast-${type}` }, message);
  container.appendChild(toast);
  requestAnimationFrame(() => toast.classList.add('show'));
  setTimeout(() => {
    toast.classList.remove('show');
    setTimeout(() => toast.remove(), 300);
  }, 3500);
}

export function setLoading(isLoading, container) {
  if (!container) return;
  container.classList.toggle('is-loading', isLoading);
}

export function requireAuthRedirect() {
  window.location.href = 'login.html';
}
