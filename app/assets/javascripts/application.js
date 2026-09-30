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

  // Plain navigation links: mark the clicked link, ignore further clicks until the page changes.
  document.addEventListener("click", function (event) {
    var link = event.target.closest && event.target.closest("a[href]");
    if (!link) return;
    if (isBusy(link)) { event.preventDefault(); return; }
    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    if ((link.target && link.target !== "_self") || link.hasAttribute("download")) return;
    if (link.origin !== window.location.origin || link.getAttribute("href").charAt(0) === "#") return;
    setBusy(link, true);
  });

  // Regular (non-JS-handled) forms, e.g. the admin login / approve / reject buttons.
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

  function postJSON(url, payload) {
    var headers = { "Content-Type": "application/json", "Accept": "application/json" };
    if (tokenMeta) headers["X-Form-Token"] = tokenMeta.content;
    return fetch(url, { method: "POST", headers: headers, body: JSON.stringify(payload), credentials: "omit" })
      .then(function (response) { return response.json(); });
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

  // ---- Voting (home, /pairs/:hash, /pairs/day) --------------------------------
  function initVoting() {
    var container = document.getElementById("voting-container");
    if (!container) return;

    var results = document.getElementById("results");
    var buttons = document.querySelectorAll(".vote-button");
    var pairHash = container.dataset.pairHash;
    var votedKey = "voted_" + pairHash; // localStorage only: never sent to the server

    function showResults() {
      buttons.forEach(function (b) { b.classList.add("hidden"); });
      results.classList.remove("hidden");
    }

    function updateResults(percentages, totalVotes) {
      Object.keys(percentages).forEach(function (optionId) {
        var pct = percentages[optionId];
        var label = document.querySelector('[data-option-id="' + optionId + '-percentage"]');
        var bar = document.querySelector('[data-option-id="' + optionId + '-bar"]');
        if (label) label.textContent = pct + "%";
        if (bar) bar.style.width = pct + "%";
      });
      document.getElementById("total-votes").textContent = totalVotes;
    }

    if (localStorage.getItem(votedKey)) showResults();

    function lockVoting(locked) {
      buttons.forEach(function (b) { b.disabled = locked; });
    }

    buttons.forEach(function (button) {
      button.addEventListener("click", function () {
        if (localStorage.getItem(votedKey)) { showResults(); return; }
        if (isBusy(button)) return; // double click while the vote is in flight

        lockVoting(true);
        setBusy(button, true);

        postJSON("/votes", { option_id: button.dataset.optionId, pair_hash: pairHash })
          .then(function (data) {
            if (data.success) {
              localStorage.setItem(votedKey, "true");
              updateResults(data.percentages, data.total_votes);
              showResults();
            } else {
              alert(data.error || "Erro ao votar");
            }
          })
          .catch(function () { alert("Erro ao votar. Tente novamente."); })
          .then(function () { setBusy(button, false); lockVoting(false); });
      });
    });

    var share = document.getElementById("share-button");
    if (share) {
      share.addEventListener("click", function () {
        var url = window.location.origin + "/pairs/" + pairHash;
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
      message.className = "mt-3 text-sm text-center " + (ok ? "text-green-600" : "text-red-600");
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

    form.addEventListener("submit", function (event) {
      event.preventDefault();
      var text = input.value.trim();
      if (!text || text.length > 120) { say("Texto inválido (máx 120 caracteres)", false); return; }
      var chosen = form.querySelector('input[name="category"]:checked');
      if (!chosen) { say("Escolha se a opção é Boa ou Ruim", false); return; }

      var submitButton = form.querySelector('button[type="submit"]');
      if (isBusy(submitButton)) return;
      setBusy(submitButton, true);
      submitButton.disabled = true;

      postJSON("/options", { text: text, category: chosen.value })
        .then(function (data) {
          if (data.success) {
            say(data.message, true);
            input.value = "";
            counter.textContent = "0";
            chosen.checked = false;
            setTimeout(function () { modal.classList.add("hidden"); }, 2000);
          } else {
            say(data.error, false);
          }
        })
        .catch(function () { say("Erro ao enviar. Tente novamente.", false); })
        .then(function () { setBusy(submitButton, false); submitButton.disabled = false; });
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    applyBarWidths();
    initVoting();
    initSubmit();
  });
})();
