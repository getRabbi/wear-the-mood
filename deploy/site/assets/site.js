/* Wear The Mood — landing interactions (vanilla, no dependencies). */
(function () {
  "use strict";

  var nav = document.getElementById("nav");
  var toggle = document.getElementById("navToggle");

  /* Sticky nav: solidify on scroll. */
  function onScroll() {
    if (!nav) return;
    nav.classList.toggle("scrolled", window.scrollY > 12);
  }
  window.addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  /* Mobile menu toggle. */
  if (toggle && nav) {
    toggle.addEventListener("click", function () {
      var open = nav.classList.toggle("open");
      toggle.setAttribute("aria-expanded", open ? "true" : "false");
    });
    // Close the menu after tapping a link.
    nav.querySelectorAll(".nav-links a").forEach(function (a) {
      a.addEventListener("click", function () {
        nav.classList.remove("open");
        toggle.setAttribute("aria-expanded", "false");
      });
    });
  }

  /* Accessible FAQ accordion (one open at a time, keyboard-friendly via <button>). */
  document.querySelectorAll(".faq-item").forEach(function (item) {
    var btn = item.querySelector(".faq-q");
    var ans = item.querySelector(".faq-a");
    if (!btn || !ans) return;
    btn.addEventListener("click", function () {
      var isOpen = item.classList.contains("open");
      // close others
      document.querySelectorAll(".faq-item.open").forEach(function (other) {
        if (other !== item) {
          other.classList.remove("open");
          var q = other.querySelector(".faq-q");
          var a = other.querySelector(".faq-a");
          if (q) q.setAttribute("aria-expanded", "false");
          if (a) a.style.maxHeight = null;
        }
      });
      item.classList.toggle("open", !isOpen);
      btn.setAttribute("aria-expanded", !isOpen ? "true" : "false");
      ans.style.maxHeight = !isOpen ? ans.scrollHeight + "px" : null;
    });
  });

  /* Scroll-reveal entrance animations (respects prefers-reduced-motion via CSS). */
  var reveals = document.querySelectorAll(".reveal");
  if ("IntersectionObserver" in window && reveals.length) {
    var io = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (e) {
          if (e.isIntersecting) {
            e.target.classList.add("in");
            io.unobserve(e.target);
          }
        });
      },
      { threshold: 0.12, rootMargin: "0px 0px -40px 0px" }
    );
    reveals.forEach(function (el) {
      io.observe(el);
    });
  } else {
    reveals.forEach(function (el) {
      el.classList.add("in");
    });
  }

  /* Current year in the footer copyright (keeps it fresh without redeploys). */
  // (Static "© 2026" is kept per brand spec; uncomment to auto-update.)
})();
