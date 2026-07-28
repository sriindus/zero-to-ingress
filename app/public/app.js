const status = document.getElementById('status');

const set = (id, value) => {
  document.getElementById(id).textContent = value;
};

async function load() {
  try {
    const res = await fetch('/api/hello', { cache: 'no-store' });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);

    const data = await res.json();
    document.title = data.message;
    set('message', data.message);
    set('environment', data.environment);
    set('version', data.version);
    set('hostname', data.hostname);
    set('timestamp', new Date(data.timestamp).toLocaleString());

    status.classList.remove('error');
    status.textContent = 'Live from /api/hello';
  } catch (err) {
    status.classList.add('error');
    status.textContent = `Could not reach the API: ${err.message}`;
  }
}

load();
setInterval(load, 15_000);
