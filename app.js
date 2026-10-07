/* ReadAlert widget — Cobbled RAL module Delivery 1
   Follows Wayne's EDP pattern: postMessage host-context, no persistent browser storage.
   app.js is served from /ral-widget/app.js via UseStaticFiles(). */
(() => {
  const root = document.querySelector('#root');
  let context = null;

  const html = v => String(v ?? '').replace(/[&<>"']/g, c =>
    ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[c]));

  const badge = status => {
    const map = { READ:'badge-read', READING:'badge-reading', WANT_TO_READ:'badge-want' };
    return `<span class="badge ${map[status] ?? ''}">${html(status ?? '—')}</span>`;
  };

  /* ── API helper — only called after context is set ─── */
  async function api(path, options = {}) {
    if (!context?.accessToken) throw new Error('No access token — context not received yet.');
    const res = await fetch(`/api/ral/v01${path}`, {
      ...options,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${context.accessToken}`,
        ...(options.headers ?? {})
      }
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(err.message || err.title || `Request failed (${res.status})`);
    }
    const text = await res.text();
    return text ? JSON.parse(text) : null;
  }

  /* ── Main shell ──────────────────────────────────────── */
  function render() {
    root.innerHTML = `
      <header>
        <h1>ReadAlert</h1>
        <span>Track every book you read.</span>
      </header>
      <div class="tabs">
        <button class="active" id="tab-books">My Books</button>
        <button id="tab-search">Search / Scan</button>
        <button id="tab-profile">Profile</button>
      </div>
      <section id="panel"></section>`;

    document.querySelector('#tab-books').onclick   = () => { setTab('books');   loadUserBooks(); };
    document.querySelector('#tab-search').onclick  = () => { setTab('search');  renderSearch(); };
    document.querySelector('#tab-profile').onclick = () => { setTab('profile'); loadProfile(); };

    loadUserBooks();
  }

  function setTab(name) {
    document.querySelectorAll('.tabs button').forEach(b => b.classList.remove('active'));
    document.querySelector(`#tab-${name}`).classList.add('active');
  }

  /* ── My Books tab ────────────────────────────────────── */
  async function loadUserBooks() {
    const panel = document.querySelector('#panel');
    panel.innerHTML = `
      <div class="bar">
        <h2>My Reading List</h2>
        <button id="add-book">+ Add Book</button>
      </div>
      <p id="message"></p>
      <div id="list">Loading…</div>`;
    document.querySelector('#add-book').onclick = renderAddBookForm;
    try {
      const data = await api('/user-books');
      const rows = Array.isArray(data) ? data : (data?.Books ?? []);
      document.querySelector('#list').innerHTML = rows.length
        ? `<table>
             <tr><th>Title</th><th>Status</th><th>Rating</th><th>Finished</th></tr>
             ${rows.map(r => `<tr>
               <td>${html(r.BookTitle   ?? r.bookTitle)}</td>
               <td>${badge(r.ReadingStatusCode ?? r.readingStatusCode)}</td>
               <td>${html(r.Rating      ?? r.rating ?? '—')}</td>
               <td>${html(r.FinishedDate ?? r.finishedDate ?? '—')}</td>
             </tr>`).join('')}
           </table>`
        : '<p>No books yet — add one!</p>';
    } catch (e) {
      document.querySelector('#list').textContent = e.message;
    }
  }

  function renderAddBookForm() {
    document.querySelector('#list').innerHTML = `
      <form id="add-form">
        <label>Book Title (required)<input name="BookTitle" required maxlength="300"></label>
        <label>Author Name<input name="AuthorName" maxlength="200"></label>
        <label>ISBN-13<input name="ISBN13" maxlength="20"></label>
        <label>Status
          <select name="ReadingStatusCode">
            <option value="READ">Read</option>
            <option value="READING">Currently Reading</option>
            <option value="WANT_TO_READ">Want to Read</option>
          </select>
        </label>
        <label>Rating (1–5)<input name="Rating" type="number" min="1" max="5"></label>
        <label>Review<textarea name="ReviewText" maxlength="2000"></textarea></label>
        <button type="submit">Save</button>
        <button type="button" id="cancel-add">Cancel</button>
      </form>`;
    document.querySelector('#cancel-add').onclick = loadUserBooks;
    document.querySelector('#add-form').onsubmit = async e => {
      e.preventDefault();
      const data = Object.fromEntries(new FormData(e.target));
      if (data.Rating) data.Rating = parseInt(data.Rating); else delete data.Rating;
      try {
        await api('/user-books', { method: 'POST', body: JSON.stringify(data) });
        loadUserBooks();
      } catch (err) {
        document.querySelector('#message').textContent = err.message;
      }
    };
  }

  /* ── Search / Scan tab ───────────────────────────────── */
  function renderSearch() {
    const panel = document.querySelector('#panel');
    panel.innerHTML = `
      <h2>Search Books</h2>
      <p id="message"></p>
      <form id="search-form">
        <label>Search type
          <select name="SearchType">
            <option value="TITLE_SEARCH">Title</option>
            <option value="AUTHOR_SEARCH">Author</option>
            <option value="ISBN_SEARCH">ISBN</option>
            <option value="ANY">Any</option>
          </select>
        </label>
        <label>Search text<input name="SearchText" required maxlength="300"></label>
        <button type="submit">Search</button>
      </form>
      <hr style="margin:18px 0">
      <form id="scan-form">
        <label>Scan / type ISBN<input name="ISBN13" placeholder="e.g. 9780553418026" maxlength="20"></label>
        <button type="submit">Scan ISBN</button>
      </form>
      <div id="search-results" style="margin-top:18px"></div>`;

    document.querySelector('#search-form').onsubmit = async e => {
      e.preventDefault();
      const { SearchType, SearchText } = Object.fromEntries(new FormData(e.target));
      document.querySelector('#message').textContent = '';
      try {
        const data = await api('/books/search', { method:'POST', body: JSON.stringify({ SearchType, SearchText, Limit: 25 }) });
        showSearchResults(data);
      } catch (err) { document.querySelector('#message').textContent = err.message; }
    };

    document.querySelector('#scan-form').onsubmit = async e => {
      e.preventDefault();
      const { ISBN13 } = Object.fromEntries(new FormData(e.target));
      document.querySelector('#message').textContent = '';
      try {
        const data = await api('/books/scan', { method:'POST', body: JSON.stringify({ ISBN13 }) });
        showSearchResults(data);
      } catch (err) { document.querySelector('#message').textContent = err.message; }
    };
  }

  function showSearchResults(data) {
    const el = document.querySelector('#search-results');
    if (!data) return;
    const books = data.Books ?? [];
    el.innerHTML = `<p><strong>${data.MatchCount ?? 0} result(s)</strong> — ${html(data.ResultStatusCode)}</p>` + (
      books.length
        ? `<table>
             <tr><th>Title</th><th>Author</th><th>ISBN-13</th></tr>
             ${books.map(b => `<tr>
               <td>${html(b.BookTitle)}</td>
               <td>${html(b.AuthorName ?? '—')}</td>
               <td>${html(b.ISBN13 ?? '—')}</td>
             </tr>`).join('')}
           </table>`
        : '<p>No matches found.</p>');
  }

  /* ── Profile tab ─────────────────────────────────────── */
  async function loadProfile() {
    const panel = document.querySelector('#panel');
    panel.innerHTML = `<h2>Reader Profile</h2><p id="message"></p><div id="profile-content">Loading…</div>`;
    try {
      const data = await api('/reader-profile');
      const profiles = Array.isArray(data) ? data : [];
      if (profiles.length === 0) {
        document.querySelector('#profile-content').innerHTML = `
          <p>No profile yet.</p>
          <button id="create-profile">Create Profile</button>`;
        document.querySelector('#create-profile').onclick = () => renderProfileForm(null);
      } else {
        const p = profiles[0];
        document.querySelector('#profile-content').innerHTML = `
          <table>
            <tr><th>Display Name</th><td>${html(p.ReaderDisplayName)}</td></tr>
            <tr><th>Status</th><td>${html(p.ReaderStatusCode)}</td></tr>
            <tr><th>Alert Opt-In</th><td>${p.AlertOptIn ? 'Yes' : 'No'}</td></tr>
          </table>
          <button id="edit-profile" style="margin-top:12px">Edit Profile</button>`;
        document.querySelector('#edit-profile').onclick = () => renderProfileForm(p);
      }
    } catch (e) {
      document.querySelector('#profile-content').textContent = e.message;
    }
  }

  function renderProfileForm(existing) {
    document.querySelector('#profile-content').innerHTML = `
      <form id="profile-form">
        <label>Display Name<input name="ReaderDisplayName" maxlength="200" value="${html(existing?.ReaderDisplayName ?? '')}"></label>
        <label>Preferred Genres<input name="PreferredGenres" maxlength="500" value="${html(existing?.PreferredGenres ?? '')}"></label>
        <label>Alert Opt-In
          <select name="AlertOptIn">
            <option value="true"  ${existing?.AlertOptIn ? 'selected' : ''}>Yes</option>
            <option value="false" ${!existing?.AlertOptIn ? 'selected' : ''}>No</option>
          </select>
        </label>
        <button type="submit">${existing ? 'Update' : 'Create'}</button>
        <button type="button" id="cancel-profile">Cancel</button>
      </form>`;
    document.querySelector('#cancel-profile').onclick = loadProfile;
    document.querySelector('#profile-form').onsubmit = async e => {
      e.preventDefault();
      const data = Object.fromEntries(new FormData(e.target));
      data.AlertOptIn = data.AlertOptIn === 'true';
      try {
        await api('/reader-profile', { method: existing ? 'PUT' : 'POST', body: JSON.stringify(data) });
        loadProfile();
      } catch (err) {
        document.querySelector('#message').textContent = err.message;
      }
    };
  }

  /* ── Cobbled host-context handshake (Wayne's pattern) ── */
  window.addEventListener('message', event => {
    // Only accept messages from the parent frame on the same origin
    if (event.origin !== location.origin) return;
    if (event.data?.contract !== 'cobbled.host-context.v1') return;
    if (event.data?.moduleCode !== 'RAL') return;

    context = event.data;  // context.accessToken is now a real signed JWT

    parent.postMessage(
      { contract: 'cobbled.module-context-accepted.v1', moduleCode: 'RAL' },
      event.origin
    );

    render();  // only called AFTER context (and accessToken) is set
  });

  // Tell the parent frame we are ready to receive context
  parent.postMessage({ contract: 'cobbled.module-ready.v1', moduleCode: 'RAL' }, '*');
})();
