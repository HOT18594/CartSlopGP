/* Cart Slop GP — site behaviour. No dependencies, no network calls.
   Everything degrades gracefully: without JS the page is fully readable (the
   reveal animation class is only applied once this file runs). */
(function () {
  'use strict';

  document.documentElement.classList.add('js');

  // --- Mobile navigation ---------------------------------------------------
  var toggle = document.getElementById('navToggle');
  var nav = document.getElementById('site-nav');

  function setNav(open) {
    if (!toggle || !nav) { return; }
    toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    nav.classList.toggle('is-open', open);
  }

  if (toggle && nav) {
    toggle.addEventListener('click', function () {
      setNav(toggle.getAttribute('aria-expanded') !== 'true');
    });
    nav.addEventListener('click', function (event) {
      if (event.target instanceof Element && event.target.closest('a')) {
        setNav(false);
      }
    });
    document.addEventListener('keydown', function (event) {
      if (event.key === 'Escape') { setNav(false); }
    });
    // A resize past the mobile breakpoint must not leave a closed menu shown
    // as the desktop nav (display rules handle it, this keeps ARIA honest).
    window.addEventListener('resize', function () {
      if (window.innerWidth > 820) { setNav(false); }
    });
  }

  // --- Scroll reveal -------------------------------------------------------
  var revealItems = Array.prototype.slice.call(
    document.querySelectorAll('.reveal'));
  var reduceMotion = window.matchMedia
    ? window.matchMedia('(prefers-reduced-motion: reduce)')
    : { matches: false };

  if (!('IntersectionObserver' in window) || reduceMotion.matches) {
    revealItems.forEach(function (item) { item.classList.add('is-visible'); });
  } else {
    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible');
          observer.unobserve(entry.target);
        }
      });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.12 });
    revealItems.forEach(function (item) { observer.observe(item); });
  }

  // --- Small dynamic bits --------------------------------------------------
  var year = document.getElementById('year');
  if (year) {
    year.textContent = String(new Date().getFullYear());
  }
}());
