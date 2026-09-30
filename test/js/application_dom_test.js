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
<div id="voting-container" data-pair-hash="1-2">
  <button type="button" class="vote-button" data-option-id="1">A</button>
  <button type="button" class="vote-button" data-option-id="2">B</button>
  <p id="vote-message" hidden></p>
  <div id="results" class="hidden">
    <span data-option-id="1-percentage"></span><div data-option-id="1-bar"></div>
    <span data-option-id="2-percentage"></span><div data-option-id="2-bar"></div>
    <span id="total-votes"></span>
    <a id="next" href="/pairs/3-4">Próximo</a>
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

async function boot(fetchImpl) {
  const dom = new JSDOM(PAGE, { url: "https://example.test/", runScripts: "outside-only", pretendToBeVisual: true, virtualConsole: quiet() });
  await new Promise((r) => setTimeout(r, 10)); // let jsdom fire its own DOMContentLoaded first (the script then runs once, as in a browser with `defer`)
  const { window } = dom;
  const calls = [];
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
    assert.strictEqual(doc.getElementById("total-votes").textContent, "5");
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
    const next = doc.getElementById("next");
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
    const next = w.document.getElementById("next");
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

  await test("no inline handlers / eval / external URLs in the script", () => {
    assert.ok(!/\beval\(|new Function|innerHTML|document\.write/.test(source));
    assert.ok(!/https?:\/\//.test(source.replace(/\/\/.*$/gm, "")));
  });

  console.log(failures ? failures + " FAILED" : "all passed");
  process.exit(failures ? 1 : 0);
})();
