/* Landing page behaviour: Lua syntax colouring, tabbed examples, copy buttons.
   Everything here is an enhancement — the page reads fine without it. */
(function () {
  "use strict";

  /* ------------------------------------------------------------ highlight */

  // One alternation, matched left to right, so a keyword inside a string or a
  // comment can never be re-coloured: whichever construct opens first wins.
  var LUA = new RegExp(
    [
      "(--\\[\\[[\\s\\S]*?\\]\\]|--[^\\n]*)", // 1 comment
      "(\"(?:\\\\.|[^\"\\\\\\n])*\"|'(?:\\\\.|[^'\\\\\\n])*')", // 2 string
      "\\b(and|break|do|else|elseif|end|false|for|function|goto|if|in|local|" +
        "nil|not|or|repeat|return|then|true|until|while)\\b", // 3 keyword
      "\\b(\\d+(?:\\.\\d+)?)\\b", // 4 number
      "([A-Za-z_]\\w*)(?=\\s*\\()", // 5 called name
    ].join("|"),
    "g"
  );

  function escapeHTML(text) {
    return text
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
  }

  function highlight(pre) {
    var html = escapeHTML(pre.textContent).replace(
      LUA,
      function (match, comment, string, keyword, number, called) {
        if (comment) return '<span class="t-com">' + comment + "</span>";
        if (string) return '<span class="t-str">' + string + "</span>";
        if (keyword) return '<span class="t-key">' + keyword + "</span>";
        if (number) return '<span class="t-num">' + number + "</span>";
        if (called) return '<span class="t-fn">' + called + "</span>";
        return match;
      }
    );
    pre.innerHTML = html;
  }

  Array.prototype.forEach.call(document.querySelectorAll("pre[data-lua]"), highlight);

  /* ----------------------------------------------------------------- tabs */

  Array.prototype.forEach.call(
    document.querySelectorAll('[role="tablist"]'),
    function (list) {
      var tabs = Array.prototype.slice.call(list.querySelectorAll('[role="tab"]'));

      // Narrow screens scroll this strip. Say so, on whichever side still has
      // tabs to reveal; a strip that fits shows no fade at all.
      function markOverflow() {
        var slack = list.scrollWidth - list.clientWidth;
        var at = list.scrollLeft;
        list.classList.toggle("fade-start", slack > 1 && at > 1);
        list.classList.toggle("fade-end", slack > 1 && at < slack - 1);
      }

      list.addEventListener("scroll", markOverflow, { passive: true });
      window.addEventListener("resize", markOverflow);
      markOverflow();

      function select(tab, moveFocus) {
        tabs.forEach(function (other) {
          var chosen = other === tab;
          other.setAttribute("aria-selected", String(chosen));
          other.tabIndex = chosen ? 0 : -1;
          var panel = document.getElementById(other.getAttribute("aria-controls"));
          if (panel) panel.hidden = !chosen;
        });
        if (moveFocus) tab.focus();
        // A tab chosen with the arrow keys may be off-screen on a phone.
        if (tab.scrollIntoView) {
          tab.scrollIntoView({ block: "nearest", inline: "nearest" });
        }
        markOverflow();
      }

      tabs.forEach(function (tab, index) {
        tab.addEventListener("click", function () {
          select(tab, false);
        });

        tab.addEventListener("keydown", function (event) {
          var next = null;
          if (event.key === "ArrowRight") next = tabs[(index + 1) % tabs.length];
          else if (event.key === "ArrowLeft") next = tabs[(index - 1 + tabs.length) % tabs.length];
          else if (event.key === "Home") next = tabs[0];
          else if (event.key === "End") next = tabs[tabs.length - 1];
          if (next) {
            event.preventDefault();
            select(next, true);
          }
        });
      });
    }
  );

  /* ----------------------------------------------------------------- copy */

  Array.prototype.forEach.call(
    document.querySelectorAll("[data-copy]"),
    function (button) {
      var source = button.parentNode.querySelector("code");
      if (!source) return;

      button.addEventListener("click", function () {
        var text = source.textContent.trim();
        var done = function (label) {
          var original = "Copy";
          button.textContent = label;
          setTimeout(function () {
            button.textContent = original;
          }, 1600);
        };

        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(text).then(
            function () {
              done("Copied");
            },
            function () {
              done("Press ⌘C");
            }
          );
          return;
        }

        // Older Safari and any non-secure origin.
        var field = document.createElement("textarea");
        field.value = text;
        field.setAttribute("readonly", "");
        field.style.position = "fixed";
        field.style.opacity = "0";
        document.body.appendChild(field);
        field.select();
        try {
          done(document.execCommand("copy") ? "Copied" : "Press ⌘C");
        } catch (error) {
          done("Press ⌘C");
        }
        document.body.removeChild(field);
      });
    }
  );
})();
