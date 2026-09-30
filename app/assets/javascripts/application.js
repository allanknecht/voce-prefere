// Você Prefere? - the only script of the site. Served from our own origin
// (Content-Security-Policy: script-src 'self'), so no inline scripts are needed.
(function () {
  "use strict";

  var tokenMeta = document.querySelector('meta[name="form-token"]');

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

    buttons.forEach(function (button) {
      button.addEventListener("click", function () {
        if (localStorage.getItem(votedKey)) { showResults(); return; }

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
          .catch(function () { alert("Erro ao votar. Tente novamente."); });
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

      postJSON("/options", { text: text })
        .then(function (data) {
          if (data.success) {
            say(data.message, true);
            input.value = "";
            counter.textContent = "0";
            setTimeout(function () { modal.classList.add("hidden"); }, 2000);
          } else {
            say(data.error, false);
          }
        })
        .catch(function () { say("Erro ao enviar. Tente novamente.", false); });
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    applyBarWidths();
    initVoting();
    initSubmit();
  });
})();
