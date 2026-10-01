// Runs app/assets/javascripts/application.js in jsdom and simulates double clicks, errors, timeouts.
// jsdom is NOT a dependency of the repo: `npm i jsdom` somewhere and run with NODE_PATH=<that>/node_modules
//   NODE_PATH=/tmp/jsd/node_modules node test/js/application_dom_test.js
// (the Rails test test/integration/js_dom_test.rb runs it when jsdom is available, and skips otherwise)
const fs = require("fs");
const path = require("path");
const { JSDOM, VirtualConsole } = require("jsdom");
const assert = require("assert");

const source = fs.readFileSync(path.join(__dirname, "../../app/assets/javascripts/application.js"), "utf8");

const PAGE = `<!DOCTYPE html><html><head><meta name="form-token" content="tok"></head><body>
<div id="voting-container" data-pair-hash="1-2" data-votes-suffix="">
  <button type="button" class="vote-button" data-option-id="1">A</button>
  <button type="button" class="vote-button" data-option-id="2">B</button>
  <p><a id="see-results-link" href="/pairs/1-2/results">Ver resultado</a></p>
  <p id="vote-message" hidden></p>
  <div id="results" class="hidden">
    <div class="bar-row"><span data-option-id="1-percentage"></span><div data-option-id="1-bar" class="bar-fill bar-w-0"></div></div>
    <div class="bar-row"><span data-option-id="2-percentage"></span><div data-option-id="2-bar" class="bar-fill bar-w-0"></div></div>
    <span id="total-votes"></span>
    <a id="next-link" href="/pairs/3-4" data-candidates="3-4 5-6 7-8 9-10">Próximo</a>
  </div>
</div>
<button id="submit-button">Enviar sua opção</button>
<div id="submit-modal" class="hidden">
  <form id="submit-form" novalidate>
    <input type="text" id="option-text"><span id="char-count">0</span>
    <input type="radio" name="category" id="category-good" value="good">
    <input type="radio" name="category" id="category-bad" value="bad">
    <button type="submit">Enviar</button>
    <button type="button" id="cancel-button">Cancelar</button>
  </form>
  <p id="submit-message"></p>
</div>
<p id="slow-notice" hidden></p><p id="nav-error" hidden></p>
</body></html>`;

const quiet = () => new VirtualConsole(); // jsdom cannot navigate: swallow its "not implemented" noise

async function boot(fetchImpl, before) {
  const dom = new JSDOM(PAGE, { url: "https://example.test/", runScripts: "outside-only", pretendToBeVisual: true, virtualConsole: quiet() });
  await new Promise((r) => setTimeout(r, 10)); // let jsdom fire its own DOMContentLoaded first (the script then runs once, as in a browser with `defer`)
  const { window } = dom;
  const calls = [];
  if (before) before(window);
  window.fetch = function (url, options) { calls.push({ url, options }); return fetchImpl(url, options, calls.length); };
  window.eval(source);
  window.document.dispatchEvent(new window.Event("DOMContentLoaded"));
  return { window, doc: window.document, calls };
}

const json = (body, status = 200) => Promise.resolve({ status, json: () => Promise.resolve(body) });
const tick = (ms = 0) => new Promise((r) => setTimeout(r, ms));
const click = (window, el) => el.dispatchEvent(new window.MouseEvent("click", { bubbles: true, cancelable: true, button: 0 }));

let failures = 0;
async function test(name, fn) {
  try { await fn(); console.log("ok   - " + name); } catch (e) { failures++; console.log("FAIL - " + name + "\n" + e.stack); }
}

(async () => {
  await test("first click locks ALL vote buttons synchronously; double click / Enter / tap -> ONE fetch", async () => {
    let resolve;
    const { window, doc, calls } = await boot(() => new Promise((r) => { resolve = r; }));
    const [a, b] = doc.querySelectorAll(".vote-button");
    click(window, a);
    // synchronous state, before the fetch settles
    assert.strictEqual(a.disabled, true); assert.strictEqual(b.disabled, true);
    assert.strictEqual(a.getAttribute("aria-disabled"), "true"); assert.strictEqual(b.getAttribute("aria-disabled"), "true");
    assert.ok(doc.getElementById("voting-container").classList.contains("is-voting"));
    assert.ok(a.classList.contains("vote-chosen")); assert.ok(!b.classList.contains("vote-chosen"));
    click(window, a); click(window, b); click(window, a);
    a.dispatchEvent(new window.KeyboardEvent("keydown", { key: "Enter", bubbles: true }));
    a.dispatchEvent(new window.Event("touchend", { bubbles: true }));
    click(window, a);
    assert.strictEqual(calls.length, 1, "only one fetch");
    resolve({ json: () => Promise.resolve({ success: true, percentages: { 1: 60, 2: 40 }, total_votes: 5 }) });
    await tick(5);
    assert.strictEqual(calls.length, 1);
    assert.ok(!doc.getElementById("results").classList.contains("hidden"));
    assert.strictEqual(doc.querySelector('[data-option-id="1-percentage"]').textContent, "60%");
    assert.strictEqual(doc.getElementById("total-votes").textContent, "5 votos");
    assert.strictEqual(doc.querySelector('[data-option-id="1-bar"]').style.width, "60%", "exact width through the CSSOM");
    assert.ok(doc.querySelector('[data-option-id="1-percentage"]').closest(".bar-row").classList.contains("is-winner"), "leader gets .is-winner");
    assert.ok(!doc.querySelector('[data-option-id="2-percentage"]').closest(".bar-row").classList.contains("is-winner"));
    assert.strictEqual(window.localStorage.getItem("voted_1-2"), "true");
    assert.strictEqual(a.disabled, true, "stays locked after success");
    const body = JSON.parse(calls[0].options.body);
    assert.deepStrictEqual(body, { option_id: "1", pair_hash: "1-2" });
    assert.strictEqual(calls[0].options.credentials, "omit");
  });

  await test("vote error (server message) re-enables everything and shows the message; retry works", async () => {
    let n = 0;
    const { window, doc, calls } = await boot(() => (++n === 1 ? json({ error: "Muitas votações. Aguarde um pouco." }, 429) : json({ success: true, percentages: { 1: 50, 2: 50 }, total_votes: 1 })));
    const [a, b] = doc.querySelectorAll(".vote-button");
    click(window, b);
    await tick(5);
    assert.strictEqual(a.disabled, false); assert.strictEqual(b.disabled, false);
    assert.ok(!a.hasAttribute("aria-disabled")); assert.ok(!b.hasAttribute("aria-busy"));
    const msg = doc.getElementById("vote-message");
    assert.strictEqual(msg.hidden, false); assert.match(msg.textContent, /Muitas votações/);
    assert.strictEqual(window.localStorage.getItem("voted_1-2"), null);
    click(window, a);
    await tick(5);
    assert.strictEqual(calls.length, 2);
    assert.ok(!doc.getElementById("results").classList.contains("hidden"));
    assert.strictEqual(msg.hidden, true);
  });

  await test("network failure re-enables with an error", async () => {
    const { window, doc } = await boot(() => Promise.reject(new Error("offline")));
    const [a, b] = doc.querySelectorAll(".vote-button");
    click(window, a);
    assert.strictEqual(b.disabled, true);
    await tick(5);
    assert.strictEqual(a.disabled, false); assert.strictEqual(b.disabled, false);
    assert.match(doc.getElementById("vote-message").textContent, /Erro ao votar/);
  });

  await test("submit: one click locks inputs/radios/buttons, label 'Enviando...', double submit -> ONE fetch", async () => {
    let resolve;
    const { window, doc, calls } = await boot(() => new Promise((r) => { resolve = r; }));
    doc.getElementById("submit-button").dispatchEvent(new window.Event("click", { bubbles: true }));
    doc.getElementById("option-text").value = "Poder voar";
    doc.getElementById("category-good").checked = true;
    const form = doc.getElementById("submit-form");
    const submit = () => form.dispatchEvent(new window.Event("submit", { bubbles: true, cancelable: true }));
    // the open handler clears the radios: choose again
    doc.getElementById("category-good").checked = true;
    submit();
    const btn = form.querySelector('button[type="submit"]');
    assert.strictEqual(btn.disabled, true); assert.strictEqual(btn.textContent, "Enviando...");
    form.querySelectorAll("input").forEach((i) => assert.strictEqual(i.disabled, true, i.id));
    submit(); submit(); click(window, btn);
    assert.strictEqual(calls.length, 1);
    assert.deepStrictEqual(JSON.parse(calls[0].options.body), { text: "Poder voar", category: "good" });
    resolve({ json: () => Promise.resolve({ success: true, message: "Opção enviada!" }) });
    await tick(5);
    assert.strictEqual(doc.getElementById("submit-message").textContent, "Opção enviada!");
    assert.strictEqual(btn.textContent, "Enviar"); assert.strictEqual(btn.disabled, false);
  });

  await test("submit: duplicate refusal (422 message) and network error re-enable the form", async () => {
    let n = 0;
    const { window, doc, calls } = await boot(() => (++n === 1 ? json({ error: "Essa opção já existe! Envie outra." }, 422) : Promise.reject(new Error("x"))));
    doc.getElementById("submit-button").dispatchEvent(new window.Event("click", { bubbles: true }));
    const form = doc.getElementById("submit-form");
    const fill = () => { doc.getElementById("option-text").value = "Repetida"; doc.getElementById("category-bad").checked = true; };
    const submit = () => form.dispatchEvent(new window.Event("submit", { bubbles: true, cancelable: true }));
    fill(); submit(); await tick(5);
    assert.strictEqual(doc.getElementById("submit-message").textContent, "Essa opção já existe! Envie outra.");
    assert.strictEqual(form.querySelector('button[type="submit"]').disabled, false);
    assert.strictEqual(doc.getElementById("option-text").disabled, false);
    submit(); await tick(5);
    assert.strictEqual(calls.length, 2);
    assert.match(doc.getElementById("submit-message").textContent, /Erro ao enviar/);
    assert.strictEqual(doc.getElementById("category-bad").disabled, false);
  });

  await test("Próximo: one click = one navigation; further clicks are ignored (default prevented)", async () => {
    const { window, doc } = await boot(() => json({}));
    const next = doc.getElementById("next-link");
    const first = new window.MouseEvent("click", { bubbles: true, cancelable: true, button: 0 });
    next.dispatchEvent(first);
    assert.strictEqual(first.defaultPrevented, false, "first click navigates");
    assert.strictEqual(next.getAttribute("aria-busy"), "true");
    const second = new window.MouseEvent("click", { bubbles: true, cancelable: true, button: 0 });
    next.dispatchEvent(second);
    assert.strictEqual(second.defaultPrevented, true, "second click is swallowed");
  });

  await test("Próximo that never navigates is unlocked after the timeout with a visible message", async () => {
    const realSetTimeout = setTimeout; // fake timers: run the nav timeout immediately
    const dom = new JSDOM(PAGE, { url: "https://example.test/", runScripts: "outside-only", virtualConsole: quiet() });
    const w = dom.window;
    w.fetch = () => json({});
    const timers = [];
    w.setTimeout = (fn, ms) => { timers.push({ fn, ms }); return timers.length; };
    w.eval(source);
    w.document.dispatchEvent(new w.Event("DOMContentLoaded"));
    const next = w.document.getElementById("next-link");
    click(w, next);
    const nav = timers.find((t) => t.ms >= 10000);
    assert.ok(nav, "nav timeout scheduled");
    nav.fn();
    assert.strictEqual(next.hasAttribute("aria-busy"), false);
    assert.strictEqual(w.document.getElementById("nav-error").hidden, false);
    const again = new w.MouseEvent("click", { bubbles: true, cancelable: true, button: 0 });
    next.dispatchEvent(again);
    assert.strictEqual(again.defaultPrevented, false, "can retry");
    void realSetTimeout;
  });

  await test("a hung vote request is aborted by the timeout (AbortController) and unlocks", async () => {
    const dom = new JSDOM(PAGE, { url: "https://example.test/", runScripts: "outside-only", virtualConsole: quiet() });
    const w = dom.window;
    let signal;
    w.fetch = (url, options) => { signal = options.signal; return new Promise((_, reject) => { signal.addEventListener("abort", () => reject(new Error("aborted"))); }); };
    const timers = [];
    w.setTimeout = (fn, ms) => { timers.push({ fn, ms }); return timers.length; };
    w.eval(source);
    w.document.dispatchEvent(new w.Event("DOMContentLoaded"));
    const [a, b] = w.document.querySelectorAll(".vote-button");
    click(w, a);
    assert.strictEqual(b.disabled, true);
    timers.find((t) => t.ms === 15000).fn();
    assert.ok(signal.aborted);
    await tick(5);
    assert.strictEqual(a.disabled, false); assert.strictEqual(b.disabled, false);
    assert.match(w.document.getElementById("vote-message").textContent, /Erro ao votar/);
  });

  const results = (doc) => doc.getElementById("results").classList.contains("hidden") === false;
  const href = (doc) => doc.getElementById("next-link").getAttribute("href");

  await test("a poll that has votes but was not voted by this browser opens as the VOTE screen (results hidden)", async () => {
    const { doc } = await boot(() => json({}));
    assert.strictEqual(results(doc), false);
    assert.strictEqual(doc.querySelector(".vote-button").classList.contains("hidden"), false);
    assert.strictEqual(doc.getElementById("see-results-link").parentNode.classList.contains("hidden"), false);
  });

  await test("a poll this browser already voted on STILL opens as the full vote screen; clicking reveals results without a second vote", async () => {
    const { window, doc, calls } = await boot(() => json({}), (w) => w.localStorage.setItem("voted_1-2", "true"));
    assert.strictEqual(results(doc), false);
    assert.strictEqual(doc.querySelectorAll(".vote-button").length, 2);
    doc.querySelectorAll(".vote-button").forEach((b) => assert.strictEqual(b.classList.contains("hidden"), false));
    click(window, doc.querySelector(".vote-button"));
    await tick(5);
    assert.strictEqual(calls.length, 0, "no second vote is sent");
    assert.strictEqual(results(doc), true);
  });

  await test("Próximo: first candidate not seen/voted by this browser; all seen -> first candidate", async () => {
    let r = await boot(() => json({}));
    assert.strictEqual(href(r.doc), "/pairs/3-4", "nothing seen: server's first candidate");
    r = await boot(() => json({}), (w) => w.localStorage.setItem("seen_pairs", JSON.stringify(["3-4", "5-6"])));
    assert.strictEqual(href(r.doc), "/pairs/7-8");
    r = await boot(() => json({}), (w) => w.localStorage.setItem("voted_7-8", "true")); // legacy per-pair key counts as seen
    assert.strictEqual(href(r.doc), "/pairs/3-4");
    r = await boot(() => json({}), (w) => { w.localStorage.setItem("seen_pairs", JSON.stringify(["3-4"])); w.localStorage.setItem("voted_5-6", "true"); });
    assert.strictEqual(href(r.doc), "/pairs/7-8");
    r = await boot(() => json({}), (w) => w.localStorage.setItem("seen_pairs", JSON.stringify(["3-4", "5-6", "7-8", "9-10"])));
    assert.strictEqual(href(r.doc), "/pairs/3-4", "all seen: falls back to the first candidate");
    r = await boot(() => json({}), (w) => w.localStorage.setItem("seen_pairs", "{not json"));
    assert.strictEqual(href(r.doc), "/pairs/3-4", "corrupt storage is ignored");
  });

  await test("Próximo never points to the current poll and ignores junk candidates", async () => {
    const r = await boot(() => json({}), null);
    r.doc.getElementById("next-link").dataset.candidates = "1-2 javascript:alert(1) ../x 5-6";
    r.window.dispatchEvent(new r.window.Event("pageshow"));
    const e = new r.window.Event("pageshow"); e.persisted = true; r.window.dispatchEvent(e);
    assert.strictEqual(href(r.doc), "/pairs/5-6");
  });

  await test("after voting the poll is marked seen and Próximo moves to the next unseen candidate", async () => {
    const { window, doc } = await boot(() => json({ success: true, percentages: { 1: 100 }, total_votes: 1 }), (w) => w.localStorage.setItem("seen_pairs", JSON.stringify(["3-4"])));
    assert.strictEqual(href(doc), "/pairs/5-6");
    click(window, doc.querySelector(".vote-button"));
    await tick(5);
    assert.deepStrictEqual(JSON.parse(window.localStorage.getItem("seen_pairs")), ["3-4", "1-2"]);
    assert.strictEqual(doc.getElementById("total-votes").textContent, "1 voto");
    assert.strictEqual(href(doc), "/pairs/5-6");
    assert.strictEqual(results(doc), true);
    assert.strictEqual(doc.getElementById("see-results-link").parentNode.classList.contains("hidden"), true);
  });

  await test("localStorage unavailable (private mode): page works, vote works, Próximo falls back to the server's first candidate", async () => {
    const broken = (w) => {
      Object.defineProperty(w, "localStorage", { get() { throw new w.DOMException("denied", "SecurityError"); } });
    };
    const { window, doc, calls } = await boot(() => json({ success: true, percentages: { 1: 60, 2: 40 }, total_votes: 3 }), broken);
    assert.strictEqual(href(doc), "/pairs/3-4");
    assert.strictEqual(results(doc), false);
    click(window, doc.querySelector(".vote-button"));
    await tick(5);
    assert.strictEqual(calls.length, 1);
    assert.strictEqual(results(doc), true);
    assert.strictEqual(doc.getElementById("total-votes").textContent, "3 votos");
    assert.strictEqual(href(doc), "/pairs/3-4", "no storage: the server's first candidate");
  });

  await test("setItem throwing (quota) does not break voting", async () => {
    const quota = (w) => {
      const real = w.localStorage;
      Object.defineProperty(w, "localStorage", { value: { getItem: (k) => real.getItem(k), setItem() { throw new w.DOMException("full", "QuotaExceededError"); } } });
    };
    const { window, doc } = await boot(() => json({ success: true, percentages: { 1: 50, 2: 50 }, total_votes: 2 }), quota);
    click(window, doc.querySelector(".vote-button"));
    await tick(5);
    assert.strictEqual(results(doc), true);
  });

  // ---- first-party analytics beacon ---------------------------------------------------------------
  const PAGE_WITH_SCREEN = (screen) => PAGE.replace("<body>", `<body data-screen="${screen}">`);
  async function bootAnalytics(screen, url, before, referrer) {
    const dom = new JSDOM(PAGE_WITH_SCREEN(screen), { url, ...(referrer ? { referrer } : {}), runScripts: "outside-only", pretendToBeVisual: true, virtualConsole: quiet() });
    await new Promise((r) => setTimeout(r, 10));
    const w = dom.window;
    if (before) before(w);
    const calls = [];
    w.fetch = (u, o) => { calls.push({ url: u, options: o, body: JSON.parse(o.body) }); return json({}); };
    w.eval(source);
    w.document.dispatchEvent(new w.Event("DOMContentLoaded"));
    return { w, doc: w.document, calls };
  }
  const visits = (calls) => calls.filter((c) => c.body.kind === "visit");
  const today = () => { const d = new Date(); const p = (n) => (n < 10 ? "0" : "") + n; return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate()); };

  await test("analytics: ONE visit beacon per page load with only whitelisted fields; first visit is not returning; the date is stored locally", async () => {
    const { w, calls } = await bootAnalytics("pair", "https://example.test/pairs/1-2?c=1&s=Zap&utm_source=ignored", null, "https://www.google.com/search?q=secret");
    assert.strictEqual(visits(calls).length, 1);
    const c = visits(calls)[0];
    assert.strictEqual(c.url, "/m");
    assert.strictEqual(c.options.method, "POST");
    assert.strictEqual(c.options.credentials, "omit");
    assert.strictEqual(c.options.keepalive, true);
    assert.deepStrictEqual(Object.keys(c.body).sort(), ["kind", "pair_hash", "referrer", "returning", "screen", "tag", "via_share"]);
    assert.strictEqual(c.body.referrer, "www.google.com", "host name only, never path or query");
    assert.strictEqual(c.body.tag, "Zap");
    assert.strictEqual(c.body.via_share, true);
    assert.strictEqual(c.body.returning, false);
    assert.strictEqual(c.body.screen, "pair");
    assert.strictEqual(w.localStorage.getItem("last_visit"), today());
    assert.ok(!JSON.stringify(c.body).includes("secret"));
  });

  await test("analytics: returning = last visit date before today; same day again is not returning", async () => {
    let r = await bootAnalytics("home", "https://example.test/", (w) => w.localStorage.setItem("last_visit", "2020-01-01"));
    assert.strictEqual(visits(r.calls)[0].body.returning, true);
    assert.strictEqual(r.w.localStorage.getItem("last_visit"), today());
    r = await bootAnalytics("home", "https://example.test/", (w) => w.localStorage.setItem("last_visit", today()));
    assert.strictEqual(visits(r.calls)[0].body.returning, false);
    r = await bootAnalytics("home", "https://example.test/", (w) => w.localStorage.setItem("last_visit", "junk"));
    assert.strictEqual(typeof visits(r.calls)[0].body.returning, "boolean");
  });

  await test("analytics: storage unavailable -> new visitor, page does not break", async () => {
    const broken = (w) => { Object.defineProperty(w, "localStorage", { get() { throw new w.DOMException("denied", "SecurityError"); } }); };
    const { calls } = await bootAnalytics("home", "https://example.test/", broken);
    assert.strictEqual(visits(calls).length, 1);
    assert.strictEqual(visits(calls)[0].body.returning, false);
  });

  await test("analytics: pages without data-screen (admin) send nothing; a failing fetch is swallowed", async () => {
    const dom = new JSDOM(PAGE, { url: "https://example.test/admin", runScripts: "outside-only", virtualConsole: quiet() });
    await new Promise((r) => setTimeout(r, 10));
    let n = 0;
    dom.window.fetch = () => { n++; return json({}); };
    dom.window.eval(source);
    dom.window.document.dispatchEvent(new dom.window.Event("DOMContentLoaded"));
    assert.strictEqual(n, 0);
    const d2 = new JSDOM(PAGE_WITH_SCREEN("home"), { url: "https://example.test/", runScripts: "outside-only", virtualConsole: quiet() });
    await new Promise((r) => setTimeout(r, 10));
    d2.window.fetch = () => { throw new Error("blocked"); };
    d2.window.eval(source);
    d2.window.document.dispatchEvent(new d2.window.Event("DOMContentLoaded"));
  });

  await test("analytics: Compartilhar sends one share_click beacon and the shared URL carries ?c=1", async () => {
    let shared;
    const { w, doc, calls } = await bootAnalytics("home", "https://example.test/", (win) => {
      win.navigator.share = (data) => { shared = data; return Promise.resolve(); };
      const btn = win.document.createElement("button"); btn.id = "share-button"; win.document.body.appendChild(btn);
    });
    doc.getElementById("share-button").click();
    assert.strictEqual(calls.filter((c) => c.body.kind === "share_click").length >= 1, true);
    assert.strictEqual(calls.filter((c) => c.body.kind === "share_click")[0].body.pair_hash, "1-2");
    assert.strictEqual(shared.url, "https://example.test/pairs/1-2?c=1");
  });

  await test("no inline handlers / eval / external URLs in the script", () => {
    assert.ok(!/\beval\(|new Function|innerHTML|document\.write/.test(source));
    assert.ok(!/https?:\/\//.test(source.replace(/\/\/.*$/gm, "")));
  });

  console.log(failures ? failures + " FAILED" : "all passed");
  process.exit(failures ? 1 : 0);
})();
