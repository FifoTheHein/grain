// Line-icon sprite for the mockups. Injected as a hidden <svg> so each page can
// reach a glyph with <svg class="i"><use href="#ic-name"/></svg>.
document.addEventListener('DOMContentLoaded', function () {
  var d = document.createElement('div');
  d.style.cssText = 'position:absolute;width:0;height:0;overflow:hidden';
  d.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg"><defs>
<symbol id="ic-recent" viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="16" rx="2"/><path d="M7 9h4M7 13h4M15 9h2M15 13h2"/></symbol>
<symbol id="ic-plus" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M12 8v8M8 12h8"/></symbol>
<symbol id="ic-insights" viewBox="0 0 24 24"><path d="M4 15l4.5-5 3.5 3.5L20 6"/><circle cx="20" cy="6" r="1.6" fill="currentColor" stroke="none"/><circle cx="8.5" cy="10" r="1.6" fill="currentColor" stroke="none"/></symbol>
<symbol id="ic-settings" viewBox="0 0 24 24"><circle cx="12" cy="12" r="3"/><path d="M19.4 13.6a7.6 7.6 0 0 0 0-3.2l2-1.5-2-3.4-2.3.9a7.6 7.6 0 0 0-2.8-1.6L14 2h-4l-.3 2.8a7.6 7.6 0 0 0-2.8 1.6l-2.3-.9-2 3.4 2 1.5a7.6 7.6 0 0 0 0 3.2l-2 1.5 2 3.4 2.3-.9a7.6 7.6 0 0 0 2.8 1.6L10 22h4l.3-2.8a7.6 7.6 0 0 0 2.8-1.6l2.3.9 2-3.4z"/></symbol>
<symbol id="ic-left" viewBox="0 0 24 24"><path d="M14.5 5.5L8 12l6.5 6.5"/></symbol>
<symbol id="ic-right" viewBox="0 0 24 24"><path d="M9.5 5.5L16 12l-6.5 6.5"/></symbol>
<symbol id="ic-pencil" viewBox="0 0 24 24"><path d="M4 20l4.2-1 10-10-3.2-3.2-10 10z"/><path d="M14.2 6.4l3.2 3.2"/></symbol>
<symbol id="ic-trash" viewBox="0 0 24 24"><path d="M4.5 6.5h15M9.5 6.5V4.5h5v2M6.5 6.5l1 13h9l1-13"/></symbol>
<symbol id="ic-play" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M10 8.5l6 3.5-6 3.5z" fill="currentColor" stroke="none"/></symbol>
<symbol id="ic-stop" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><rect x="9" y="9" width="6" height="6" rx="1" fill="currentColor" stroke="none"/></symbol>
<symbol id="ic-play-solid" viewBox="0 0 24 24"><path d="M8 5l12 7-12 7z" fill="currentColor" stroke="none"/></symbol>
<symbol id="ic-stop-solid" viewBox="0 0 24 24"><rect x="6" y="6" width="12" height="12" rx="1.5" fill="currentColor" stroke="none"/></symbol>
<symbol id="ic-search" viewBox="0 0 24 24"><circle cx="11" cy="11" r="6"/><path d="M15.5 15.5L20 20"/></symbol>
<symbol id="ic-hash" viewBox="0 0 24 24"><path d="M9 4L7 20M17 4l-2 16M4 9h16M3 15h16"/></symbol>
<symbol id="ic-calendar" viewBox="0 0 24 24"><rect x="4" y="5" width="16" height="15" rx="2"/><path d="M4 10h16M9 3v4M15 3v4"/></symbol>
<symbol id="ic-check" viewBox="0 0 24 24"><path d="M5 12.5l4.5 4.5L19 7"/></symbol>
<symbol id="ic-caret" viewBox="0 0 24 24"><path d="M7 10l5 5 5-5" fill="none"/></symbol>
<symbol id="ic-refresh" viewBox="0 0 24 24"><path d="M20 12a8 8 0 1 1-2.6-5.9"/><path d="M20 4v5h-5"/></symbol>
<symbol id="ic-external" viewBox="0 0 24 24"><path d="M14 5h5v5M19 5l-7.5 7.5"/><path d="M18 14v4.5a1.5 1.5 0 0 1-1.5 1.5h-11A1.5 1.5 0 0 1 4 18.5v-11A1.5 1.5 0 0 1 5.5 6H10"/></symbol>
<symbol id="ic-drag" viewBox="0 0 24 24"><circle cx="9" cy="6" r="1.4" fill="currentColor" stroke="none"/><circle cx="15" cy="6" r="1.4" fill="currentColor" stroke="none"/><circle cx="9" cy="12" r="1.4" fill="currentColor" stroke="none"/><circle cx="15" cy="12" r="1.4" fill="currentColor" stroke="none"/><circle cx="9" cy="18" r="1.4" fill="currentColor" stroke="none"/><circle cx="15" cy="18" r="1.4" fill="currentColor" stroke="none"/></symbol>
<symbol id="ic-link" viewBox="0 0 24 24"><path d="M10.5 13.5a4 4 0 0 0 5.7 0l2.3-2.3a4 4 0 0 0-5.7-5.7l-1.3 1.3"/><path d="M13.5 10.5a4 4 0 0 0-5.7 0l-2.3 2.3a4 4 0 0 0 5.7 5.7l1.3-1.3"/></symbol>
<symbol id="ic-clock" viewBox="0 0 24 24"><circle cx="12" cy="12" r="8.5"/><path d="M12 7v5.2l3.2 2"/></symbol>
<symbol id="ic-sparkle" viewBox="0 0 24 24"><path d="M12 3.5l1.8 4.7 4.7 1.8-4.7 1.8L12 16.5l-1.8-4.7L5.5 10l4.7-1.8z" fill="currentColor" stroke="none"/><path d="M18.5 15l.9 2.1 2.1.9-2.1.9-.9 2.1-.9-2.1-2.1-.9 2.1-.9z" fill="currentColor" stroke="none"/></symbol>
<symbol id="ic-close" viewBox="0 0 24 24"><path d="M6 6l12 12M18 6L6 18"/></symbol>
<symbol id="ic-eye" viewBox="0 0 24 24"><path d="M2.5 12S6 6.5 12 6.5 21.5 12 21.5 12 18 17.5 12 17.5 2.5 12 2.5 12z"/><circle cx="12" cy="12" r="2.8"/></symbol>
<symbol id="ic-back" viewBox="0 0 24 24"><path d="M20 12H4.5M11 5l-6.5 7 6.5 7"/></symbol>
<symbol id="ic-list" viewBox="0 0 24 24"><path d="M4 7h16M4 12h16M4 17h16"/></symbol>
<symbol id="ic-tree" viewBox="0 0 24 24"><path d="M4 6h16M9 12h11M9 18h11M6 6v12"/></symbol>
<symbol id="ic-image" viewBox="0 0 24 24"><rect x="3.5" y="5" width="17" height="14" rx="2"/><path d="M3.5 16l4.5-4 3.5 3 3-2.5 6 5.5"/></symbol>
<symbol id="ic-history" viewBox="0 0 24 24"><path d="M4 12a8 8 0 1 0 2.6-5.9"/><path d="M4 4v5h5"/><path d="M12 7.5V12l3 1.8"/></symbol>
<symbol id="ic-sun" viewBox="0 0 24 24"><circle cx="12" cy="12" r="4"/><path d="M12 2.5v2.2M12 19.3v2.2M21.5 12h-2.2M4.7 12H2.5M18.7 5.3l-1.6 1.6M6.9 17.1l-1.6 1.6M18.7 18.7l-1.6-1.6M6.9 6.9L5.3 5.3"/></symbol>
<symbol id="ic-auto" viewBox="0 0 24 24"><circle cx="12" cy="12" r="8.5"/><path d="M12 3.5v17" fill="none"/><path d="M12 3.5a8.5 8.5 0 0 1 0 17z" fill="currentColor" stroke="none"/></symbol>
<symbol id="ic-moon" viewBox="0 0 24 24"><path d="M20 14.5A8.5 8.5 0 0 1 9.5 4a8.5 8.5 0 1 0 10.5 10.5z"/></symbol>
</defs></svg>`;
  document.body.appendChild(d);
});
