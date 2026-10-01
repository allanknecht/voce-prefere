// Você Prefere? - the only script of the site. Served from our own origin
// (Content-Security-Policy: script-src 'self'), so no inline scripts are needed.
(function () {
  "use strict";

  var tokenMeta = document.querySelector('meta[name="form-token"]');

  // ---- Loading state -----------------------------------------------------------
  // The free hosting sleeps when idle, so the first request can take a while. The clicked
  // button / link / submit gets aria-busy="true" (+ a small spinner, see application.css)
  // and is protected against double clicks. After SLOW_MS a discreet notice explains
  // the wait. Without JS nothing changes: links and forms simply work.
  var SLOW_MS = 3000;
  var busyElements = [];
  var slowTimer = null;
  var slowNotice = document.getElementById("slow-notice");

  function refreshSlowTimer() {
    if (busyElements.length > 0) {
      if (!slowTimer) {
        slowTimer = setTimeout(function () {
          if (slowNotice) slowNotice.hidden = false;
        }, SLOW_MS);
      }
    } else {
      clearTimeout(slowTimer);
      slowTimer = null;
      if (slowNotice) slowNotice.hidden = true;
    }
  }

  function setBusy(el, busy) {
    if (!el) return;
    var index = busyElements.indexOf(el);
    if (busy && index === -1) {
      busyElements.push(el);
      el.setAttribute("aria-busy", "true");
      el.classList.add("is-loading");
      if (el.tagName === "INPUT") { // <input type=submit> cannot show a spinner: swap its label
        el.dataset.label = el.value;
        el.value = "Carregando…";
      }
    } else if (!busy && index !== -1) {
      busyElements.splice(index, 1);
      el.removeAttribute("aria-busy");
      el.classList.remove("is-loading");
      if (el.tagName === "INPUT" && el.dataset.label !== undefined) el.value = el.dataset.label;
    }
    refreshSlowTimer();
  }

  function isBusy(el) { return el.getAttribute("aria-busy") === "true"; }

  // Coming back with the browser's back button (bfcache) must not show a stuck spinner.
  window.addEventListener("pageshow", function (event) {
    if (!event.persisted) return;
    busyElements.slice().forEach(function (el) { setBusy(el, false); });
    document.querySelectorAll("[data-locked]").forEach(function (el) { el.disabled = false; delete el.dataset.locked; });
  });

  // Plain navigation links ("Próximo", ...): ONE click = ONE navigation. The clicked link is marked
  // busy and further clicks are ignored until the page changes. If the navigation never happens
  // (aborted by the browser, offline, server error page that does not replace the document) the
  // link is unlocked after NAV_TIMEOUT_MS with a visible message, so it can never stay dead.
  var NAV_TIMEOUT_MS = 25000;
  var navError = document.getElementById("nav-error");
  var navLock = false; // synchronous flag: set before anything else can run

  function showNavError(text) {
    if (!navError) return;
    navError.textContent = text;
    navError.hidden = !text;
  }

  document.addEventListener("click", function (event) {
    var link = event.target.closest && event.target.closest("a[href]");
    if (!link) return;
    if (navLock || isBusy(link)) { event.preventDefault(); return; }
    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    if ((link.target && link.target !== "_self") || link.hasAttribute("download")) return;
    if (link.origin !== window.location.origin || link.getAttribute("href").charAt(0) === "#") return;
    navLock = true;
    showNavError("");
    setBusy(link, true);
    setTimeout(function () {
      if (!navLock) return; // the page changed meanwhile (we would not be running) or was unlocked
      navLock = false;
      setBusy(link, false);
      showNavError("Está demorando mais que o normal. Toque de novo para tentar outra vez.");
    }, NAV_TIMEOUT_MS);
  });

  window.addEventListener("pageshow", function (event) {
    if (!event.persisted) return;
    navLock = false;
    showNavError("");
    updateNextLink();
  });

  // Regular (non-JS-handled) forms, e.g. the admin login / approve buttons.
  document.addEventListener("submit", function (event) {
    var form = event.target;
    if (event.defaultPrevented || form.id === "submit-form") return;
    var button = event.submitter || form.querySelector('button[type="submit"], input[type="submit"], button:not([type])');
    if (form.dataset.submitting) { event.preventDefault(); return; }
    form.dataset.submitting = "true";
    setBusy(button, true);
  });

  window.addEventListener("pageshow", function (event) {
    if (!event.persisted) return;
    document.querySelectorAll("form[data-submitting]").forEach(function (form) { delete form.dataset.submitting; });
  });

  // POST JSON with a timeout (AbortController): a hung request ends with an error instead of a
  // locked page. `signal` lets the caller cancel a request that became obsolete. Always rejects on
  // network errors / timeouts; resolves with the parsed body (errors carry {error: "..."}).
  var REQUEST_TIMEOUT_MS = 15000;

  function postJSON(url, payload) {
    var headers = { "Content-Type": "application/json", "Accept": "application/json" };
    if (tokenMeta) headers["X-Form-Token"] = tokenMeta.content;
    var controller = typeof AbortController === "function" ? new AbortController() : null;
    var timer = controller ? setTimeout(function () { controller.abort(); }, REQUEST_TIMEOUT_MS) : null;
    var options = { method: "POST", headers: headers, body: JSON.stringify(payload), credentials: "omit" };
    if (controller) options.signal = controller.signal;
    return fetch(url, options)
      .then(function (response) { return response.json(); })
      .then(function (data) { clearTimeout(timer); return data; },
            function (error) { clearTimeout(timer); throw error; });
  }

  function copyToClipboard(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(function () { alert("Link copiado!"); },
        function () { prompt("Copie o link:", text); });
    } else {
      prompt("Copie o link:", text);
    }
  }

  // Progress bars: widths come from data attributes (inline style attributes are
  // blocked by our CSP, setting them through the DOM API is allowed).
  function applyBarWidths() {
    document.querySelectorAll("[data-width]").forEach(function (el) {
      var width = parseFloat(el.dataset.width);
      el.style.width = (isNaN(width) ? 0 : Math.max(0, Math.min(100, width))) + "%";
    });
  }

  // ---- Local storage (never sent to the server, no cookies) ---------------------------------
  // Which polls this browser already voted on / saw. Private mode or blocked storage must not
  // break the page: every access is wrapped, and an in-memory fallback keeps one page working.
  var SEEN_KEY = "seen_pairs";
  var SEEN_MAX = 500;
  var memoryStore = {};
  var store = {
    get: function (key) {
      try { var value = window.localStorage.getItem(key); return value === undefined ? null : value; }
      catch (e) { return Object.prototype.hasOwnProperty.call(memoryStore, key) ? memoryStore[key] : null; }
    },
    set: function (key, value) {
      try { window.localStorage.setItem(key, value); } catch (e) { memoryStore[key] = value; }
    }
  };

  function seenPairs() {
    try {
      var list = JSON.parse(store.get(SEEN_KEY) || "[]");
      return Array.isArray(list) ? list : [];
    } catch (e) { return []; }
  }

  function isSeen(hash) {
    return seenPairs().indexOf(hash) !== -1 || store.get("voted_" + hash) !== null;
  }

  function markSeen(hash) {
    var list = seenPairs().filter(function (h) { return h !== hash; });
    list.push(hash);
    store.set(SEEN_KEY, JSON.stringify(list.slice(-SEEN_MAX)));
  }

  // "Próximo": the server embeds a few candidate polls (same category, never the current one,
  // fewest votes first) in data-candidates and the plain href already points to the first one
  // (that is what works without JS). Here the link is pointed to the first candidate this browser
  // has not voted on; if all were seen it keeps the first one. Decided when the page loads and
  // after each vote, never at click time, so one click is always one fixed destination.
  function updateNextLink() {
    var link = document.getElementById("next-link");
    if (!link) return;
    var candidates = (link.dataset.candidates || "").split(/\s+/).filter(function (h) { return /^\d+-\d+$/.test(h); });
    if (candidates.length === 0) return;
    var current = (document.getElementById("voting-container") || {}).dataset;
    var fresh = candidates.filter(function (h) { return (!current || h !== current.pairHash) && !isSeen(h); });
    var chosen = fresh.length > 0 ? fresh[0] : candidates[0];
    link.setAttribute("href", "/pairs/" + chosen);
  }

  // ---- First-party analytics (see PRIVACY.md) ----------------------------------------------
  // One tiny POST /m after the page loaded, one when Compartilhar is clicked. No cookie, no id:
  // only the page kind, the poll hash, the referrer's HOST NAME (never path/query), a short
  // ?s= / ?utm_source= tag, "opened via a shared link" (?c=1) and ONE boolean: `returning`,
  // true when the last visit date kept in localStorage is before today (the date never leaves
  // the browser). Without storage (private mode) every visit counts as new.
  var LAST_VISIT_KEY = "last_visit";

  function localDate() {
    var d = new Date();
    function two(n) { return (n < 10 ? "0" : "") + n; }
    return d.getFullYear() + "-" + two(d.getMonth() + 1) + "-" + two(d.getDate());
  }

  function track(kind, extra) {
    try {
      if (typeof fetch !== "function") return;
      var body = { kind: kind };
      Object.keys(extra || {}).forEach(function (key) { body[key] = extra[key]; });
      fetch("/m", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body), keepalive: true, credentials: "omit" })
        .catch(function () {});
    } catch (e) { /* analytics must never break the page */ }
  }

  function initAnalytics() {
    var screen = document.body && document.body.dataset.screen;
    if (!screen) return; // admin and other non-public pages carry no data-screen: nothing is sent
    var today = localDate();
    var last = store.get(LAST_VISIT_KEY);
    var query = new URLSearchParams(window.location.search);
    var host = "";
    try { host = document.referrer ? new URL(document.referrer).hostname : ""; } catch (e) { host = ""; }
    var container = document.getElementById("voting-container");
    track("visit", {
      screen: screen,
      pair_hash: container ? container.dataset.pairHash : undefined,
      referrer: host,
      tag: query.get("s") || query.get("utm_source") || undefined,
      via_share: query.get("c") === "1",
      returning: !!last && last < today
    });
    store.set(LAST_VISIT_KEY, today);
  }

  // ---- Voting (home, /pairs/:hash, /pairs/day) --------------------------------
  function pluralVotes(count, suffix) {
    return count + (Number(count) === 1 ? " voto" : " votos") + (suffix ? " " + suffix : "");
  }

  function initVoting() {
    var container = document.getElementById("voting-container");
    if (!container) return;

    var results = document.getElementById("results");
    var buttons = document.querySelectorAll(".vote-button");
    var pairHash = container.dataset.pairHash;
    var votedKey = "voted_" + pairHash; // localStorage only: never sent to the server
    var seeResults = document.getElementById("see-results-link");

    function showResults() {
      buttons.forEach(function (b) { b.classList.add("hidden"); });
      if (seeResults && seeResults.parentNode) seeResults.parentNode.classList.add("hidden");
      results.classList.remove("hidden");
    }

    // The leading option(s) wear .is-winner (highlighted percentage + yellow bar), as on the server render.
    function markWinners(percentages) {
      var top = Math.max.apply(null, Object.keys(percentages).map(function (id) { return Number(percentages[id]); }));
      Object.keys(percentages).forEach(function (optionId) {
        var label = document.querySelector('[data-option-id="' + optionId + '-percentage"]');
        var row = label && label.closest(".bar-row");
        if (row) row.classList.toggle("is-winner", top > 0 && Number(percentages[optionId]) === top);
      });
    }

    function updateResults(percentages, totalVotes) {
      Object.keys(percentages).forEach(function (optionId) {
        var pct = percentages[optionId];
        var label = document.querySelector('[data-option-id="' + optionId + '-percentage"]');
        var bar = document.querySelector('[data-option-id="' + optionId + '-bar"]');
        if (label) label.textContent = pct + "%";
        if (bar) {
          bar.dataset.width = pct;
          bar.style.width = pct + "%";
        }
      });
      markWinners(percentages);
      document.getElementById("total-votes").textContent = pluralVotes(totalVotes, container.dataset.votesSuffix);
    }

    updateNextLink();
    // The page ALWAYS opens as the full vote screen (two option buttons), also for a poll this
    // browser already voted on or one whose votes were deleted: a results card without option
    // buttons is what looked like a broken/empty screen. Clicking an option of an already-voted
    // poll reveals the results without sending a second vote (see vote()).

    var voteMessage = document.getElementById("vote-message");
    var voteLocked = false; // THE lock: set synchronously at the start of the handler, before any fetch

    function say(text) {
      if (!voteMessage) { if (text) alert(text); return; }
      voteMessage.textContent = text;
      voteMessage.hidden = !text;
    }

    // Every vote button at once: disabled + aria-disabled (+ CSS pointer-events: none / wait cursor).
    function lockVoting(locked, chosen) {
      container.classList.toggle("is-voting", locked);
      buttons.forEach(function (b) {
        b.disabled = locked;
        if (locked) b.setAttribute("aria-disabled", "true"); else b.removeAttribute("aria-disabled");
        b.classList.toggle("vote-chosen", locked && b === chosen);
      });
    }

    function vote(button) {
      if (voteLocked) return; // double click / double tap / Enter + click: ignored by the flag
      if (store.get(votedKey) !== null) { showResults(); return; }
      voteLocked = true;
      lockVoting(true, button);
      setBusy(button, true);
      say("");

      var finish = function () { setBusy(button, false); };
      postJSON("/votes", { option_id: button.dataset.optionId, pair_hash: pairHash })
        .then(function (data) {
          if (data && data.success) {
            store.set(votedKey, "true");
            markSeen(pairHash);
            updateNextLink();
            updateResults(data.percentages, data.total_votes);
            finish();
            showResults(); // stays locked: there is nothing left to vote on
          } else {
            finish();
            voteLocked = false; lockVoting(false);
            say((data && data.error) || "Erro ao votar. Tente novamente.");
          }
        })
        .catch(function () {
          finish();
          voteLocked = false; lockVoting(false);
          say("Erro ao votar. Verifique a conexão e tente novamente.");
        });
    }

    buttons.forEach(function (button) {
      button.addEventListener("click", function (event) { event.preventDefault(); vote(button); });
    });

    var share = document.getElementById("share-button");
    if (share) {
      share.addEventListener("click", function () {
        var url = window.location.origin + "/pairs/" + pairHash + "?c=1"; // c=1: "opened a shared link"
        track("share_click", { pair_hash: pairHash });
        if (navigator.share) {
          navigator.share({ title: "Você Prefere?", text: "Veja o que eu escolhi!", url: url })
            .catch(function () { copyToClipboard(url); });
        } else {
          copyToClipboard(url);
        }
      });
    }
  }

  // ---- Submit an option (home) -------------------------------------------------
  function initSubmit() {
    var openButton = document.getElementById("submit-button");
    var modal = document.getElementById("submit-modal");
    if (!openButton || !modal) return;

    var form = document.getElementById("submit-form");
    var input = document.getElementById("option-text");
    var counter = document.getElementById("char-count");
    var message = document.getElementById("submit-message");

    function say(text, ok) {
      message.textContent = text;
      message.className = "form-message " + (ok ? "is-ok" : "is-error");
    }

    openButton.addEventListener("click", function () {
      modal.classList.remove("hidden");
      input.value = "";
      counter.textContent = "0";
      message.textContent = "";
      form.querySelectorAll('input[name="category"]').forEach(function (radio) { radio.checked = false; }); // nothing preselected
      input.focus();
    });

    document.getElementById("cancel-button").addEventListener("click", function () {
      modal.classList.add("hidden");
    });

    input.addEventListener("input", function () { counter.textContent = input.value.length; });

    var submitLocked = false; // THE lock, set synchronously before the fetch
    var fields = form.querySelectorAll("input, button");
    var submitButton = form.querySelector('button[type="submit"]');
    var submitLabel = submitButton.textContent;

    function lockForm(locked) {
      fields.forEach(function (field) {
        if (field.id === "cancel-button") { field.disabled = locked; return; }
        field.disabled = locked;
        if (locked) field.setAttribute("aria-disabled", "true"); else field.removeAttribute("aria-disabled");
      });
      form.classList.toggle("is-submitting", locked);
      submitButton.textContent = locked ? "Enviando..." : submitLabel;
      if (locked) submitButton.setAttribute("aria-busy", "true"); else submitButton.removeAttribute("aria-busy");
    }

    form.addEventListener("submit", function (event) {
      event.preventDefault();
      if (submitLocked) return; // Enter + click, double tap...
      var text = input.value.trim();
      if (!text || text.length > 120) { say("Texto inválido (máx 120 caracteres)", false); return; }
      var chosen = form.querySelector('input[name="category"]:checked');
      if (!chosen) { say("Escolha se a opção é Boa ou Ruim", false); return; }

      submitLocked = true;
      var category = chosen.value; // read BEFORE the radios are disabled
      lockForm(true);
      say("Enviando...", true);

      postJSON("/options", { text: text, category: category })
        .then(function (data) {
          if (data && data.success) {
            say(data.message, true);
            input.value = "";
            counter.textContent = "0";
            chosen.checked = false;
            lockForm(false);
            submitLocked = false;
            setTimeout(function () { modal.classList.add("hidden"); }, 2000);
          } else {
            say((data && data.error) || "Erro ao enviar. Tente novamente.", false);
            lockForm(false);
            submitLocked = false;
          }
        })
        .catch(function () {
          say("Erro ao enviar. Verifique a conexão e tente novamente.", false);
          lockForm(false);
          submitLocked = false;
        });
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    applyBarWidths();
    initAnalytics();
    initVoting();
    initSubmit();
  });
})();
