// Builds the app's small website (home, privacy policy, support) into public/, one folder per language,
// from content/<language>.json. No scripts, cookies or outside requests in the pages: node build.mjs
// Cloudflare Workers Builds runs this, then `npx cf deploy`, on every push to main that changes site/.
import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const ORDER = ['en', 'nl', 'de', 'fr', 'tr', 'ar'];
const languages = ORDER.filter((code) => readdirSync(join(here, 'content')).includes(`${code}.json`))
  .map((code) => ({ code, ...JSON.parse(readFileSync(join(here, 'content', `${code}.json`), 'utf8')) }));

const escape = (text) => text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
// The email address and Apple's policy become links; everything else is plain text.
const linked = (text) => escape(text)
  .replace(/support@qibla\.dev/g, '<a href="mailto:support@qibla.dev">support@qibla.dev</a>')
  .replace(/apple\.com\/legal\/privacy/g, '<a href="https://www.apple.com/legal/privacy/">apple.com/legal/privacy</a>');

// The app on the App Store; this link opens the store in the visitor's own country.
const APP_ID = '6833713106';
const APP_STORE = `https://apps.apple.com/app/id${APP_ID}`;
// Apple's official "Download on the App Store" badge for a language (static/app-store-<code>.svg, unchanged, as
// Apple's guidelines ask), 48 px high: above Apple's 40 px minimum.
const badge = (lang) => {
  const file = `app-store-${lang.code}.svg`;
  const [, w, h] = readFileSync(join(here, 'static', file), 'utf8').match(/viewBox="0 0 ([\d.]+) ([\d.]+)"/);
  return `<p class="badge"><a href="${APP_STORE}"><img src="/${file}" alt="${escape(lang.home.badge)}" width="${Math.round(48 * w / h)}" height="48"></a></p>`;
};

const prefix = (code) => (code === 'en' ? '/' : `/${code}/`);
// In menu order.
const PAGES = { home: '', privacy: 'privacy', accessibility: 'accessibility', releases: 'releases', support: 'support' };
const url = (code, page) => prefix(code) + PAGES[page];
// While the new site is being made, the home page and "What's new" show one short maintenance page. Privacy,
// accessibility and support stay (Apple and the app link to them), as do live.json and security.txt. false brings
// the full site back.
const MAINTENANCE = true;
const MENU = ['privacy', 'accessibility', ...(MAINTENANCE ? [] : ['releases']), 'support'];

const STAR = (size) => `<svg width="${size}" height="${size}" viewBox="0 0 30 30" aria-hidden="true"><g fill="none" stroke="#C9A45C" stroke-width="1.5">
<rect x="7.5" y="7.5" width="15" height="15"/><rect x="7.5" y="7.5" width="15" height="15" transform="rotate(45 15 15)"/></g></svg>`;

// The app's own colours (Theme.swift) and faces: New York for display on Apple devices, the system face for text.
// Five sizes; one radius; the gold only on the h1, a chosen option and the closing field.
const STYLE = `
:root { color-scheme: dark; --bg: #0E1613; --surface: #16221D; --raised: #1F2D27; --ink: #EFE7D6; --muted: #A8A08C;
  --gold: #C9A45C; --on-gold: #0E1613;
  --serif: ui-serif, "New York", Georgia, "Times New Roman", serif;
  --sans: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Noto Sans", "Noto Sans Arabic", Tahoma, sans-serif;
  --display: clamp(2.6rem, 4.6vw, 4.75rem); --heading: clamp(1.75rem, 2.5vw, 2.5rem); --large: clamp(1.2rem, 1.5vw, 1.5rem);
  --text: 1.125rem; --small: .9375rem;
  --margin: clamp(12px, 1.6vw, 24px); --inset: clamp(20px, 4vw, 56px); --radius: 20px; --gap: clamp(96px, 14vw, 200px); }
* { box-sizing: border-box; }
html { -webkit-text-size-adjust: 100%; }
body { margin: 0; background: var(--bg); color: var(--ink); font: 400 var(--text)/1.55 var(--sans); }
h1, h2, h3 { font-family: var(--serif); font-weight: 500; letter-spacing: -.02em; margin: 0; text-wrap: balance; }
h1 { font-size: var(--display); line-height: 1.02; }
h2 { font-size: var(--heading); line-height: 1.08; }
h3 { font-size: var(--large); line-height: 1.2; }
p { margin: 0; }
a { color: var(--ink); text-underline-offset: 3px; text-decoration-thickness: 1px; }
a:hover { color: var(--gold); }
a:focus-visible, input:focus-visible + label { outline: 2px solid var(--gold); outline-offset: 3px; border-radius: 4px; }
img { max-width: 100%; display: block; }
.badge a { display: inline-block; transition: transform .2s; }
.badge a:hover { transform: translateY(-2px); }
.badge a:active { transform: scale(.97); }
.badge img { height: 48px; width: auto; }
.muted { color: var(--muted); }
.visually-hidden { position: absolute; width: 1px; height: 1px; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }

/* Reading pages: privacy, accessibility, releases, support. */
.page { max-width: 760px; margin: 0 auto; padding: var(--margin) var(--margin) 0; }
.page > header { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 10px 24px; padding: 12px 0 56px; }
.mark { display: inline-flex; align-items: center; gap: 12px; text-decoration: none; font: 600 var(--text)/1 var(--sans); }
.page nav { display: flex; flex-wrap: wrap; gap: 6px 20px; font-size: var(--small); }
.page nav a { text-decoration: none; color: var(--muted); }
.page nav a[aria-current="page"], .page nav a:hover { color: var(--ink); }
.page main { max-width: 64ch; }
.page main h1 { font-size: var(--heading); margin-bottom: 16px; }
.page main h2 { font-size: var(--large); margin: 2.2em 0 .5em; color: var(--gold); }
.page main p { margin: .7em 0; }
.page main ul { padding-inline-start: 1.2em; }
.page main li { margin: .45em 0; }
.summary { background: var(--surface); border-radius: var(--radius); padding: 18px 22px; margin: 1.4em 0; }
details { background: var(--surface); border-radius: var(--radius); padding: 16px 22px; margin: 10px 0; }
summary { cursor: pointer; font-weight: 600; }
details p { margin: .7em 0 .2em; }

/* The maintenance page: one calm statement until the new site is here. */
.maintenance .page > header nav { display: none; }
.maintenance .page main { min-height: 56svh; display: grid; align-content: center; justify-items: start; gap: 24px; }
.maintenance .page main h1 { font-size: var(--display); color: var(--gold); max-width: 14ch; margin: 0; }
.maintenance .page main p { margin: 0; max-width: 40ch; }

/* Home: the split stage. The compass on the fixed half never moves, as the Qibla doesn't. */
.split { display: grid; grid-template-columns: 1fr 1fr; gap: var(--margin); padding: var(--margin); align-items: start; }
.reading { display: grid; gap: var(--gap); padding-bottom: var(--gap); min-width: 0; }
.sheet { background: var(--surface); border-radius: var(--radius); min-height: calc(100svh - 2 * var(--margin));
  display: grid; grid-template-rows: auto 1fr; padding: 22px var(--inset) 0; text-align: center; }
.top { display: grid; grid-template-columns: 1fr auto 1fr; align-items: center; gap: 12px; font-size: var(--small); }
.top a { text-decoration: none; color: var(--muted); }
.top a:hover { color: var(--ink); }
.top a:first-child { justify-self: start; } .top a:last-child { justify-self: end; }
.top .mark { color: var(--ink); font-size: var(--large); font-family: var(--serif); font-weight: 500; }
.hero-text { align-self: start; margin-top: 26svh; display: grid; justify-items: center; gap: 28px; padding-bottom: 12svh; }
.hero-text h1 { color: var(--gold); max-width: 15ch; }
.hero-text .lede { max-width: 40ch; color: var(--ink); }
.block { padding: 0 var(--inset); max-width: 46rem; }
.block h2 { margin-bottom: 20px; max-width: 18ch; }
.block > p { max-width: 46ch; }
.statement h2 { color: var(--ink); }
.statement p + p { margin-top: 20px; }
.still { position: sticky; top: var(--margin); height: calc(100svh - 2 * var(--margin)); border-radius: var(--radius);
  overflow: hidden; background: var(--bg); }
.frames { position: absolute; inset: 0 0 56px; }
.frames img { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; object-position: center 42%; opacity: 0; }
.frames img:first-child { opacity: 1; }
.bar { position: absolute; inset: auto 0 0; height: 56px; background: var(--surface); display: flex; align-items: center;
  justify-content: space-between; gap: 16px; padding: 0 var(--inset); font-size: var(--small); color: var(--muted); }

/* Choices made with radio buttons and CSS alone (the site runs no scripts). */
.choice { border: 0; margin: 28px 0 0; padding: 0; min-width: 0; }
.choice legend { padding: 0; margin-bottom: 12px; font-size: var(--small); color: var(--muted); }
.options { display: flex; flex-wrap: wrap; gap: 8px; }
.choice input { position: absolute; opacity: 0; width: 1px; height: 1px; margin: 0; }
.choice label { display: inline-flex; align-items: center; min-height: 44px; padding: 0 18px; border-radius: 999px;
  background: var(--surface); cursor: pointer; transition: background .2s, color .2s, transform .15s; font-size: var(--small); }
.choice label:hover { background: var(--raised); }
.choice label:active { transform: scale(.97); }
.choice input:checked + label { background: var(--gold); color: var(--on-gold); }
.screens { display: grid; margin-top: 28px; width: min(340px, 100%); }
.screens img { grid-area: 1 / 1; width: 100%; height: auto; border-radius: var(--radius); visibility: hidden; opacity: 0;
  transition: opacity .2s, visibility 0s .2s; }
.screens img:first-child { visibility: visible; opacity: 1; }

/* Around the prayers: the names on one side, the chosen screen on the other, cropped by the stage. */
.index { display: grid; grid-template-columns: 5fr 1fr 6fr; padding: 0 var(--margin); margin-top: var(--gap); }
.index-list { grid-column: 1; padding-inline-start: var(--inset); }
.index-list h2 { margin-bottom: 36px; }
.names-set { border: 0; margin: 0; padding: 0; min-width: 0; }
.names { display: grid; gap: 4px; }
.names label { font: 500 clamp(2rem, 3.6vw, 3.6rem)/1.1 var(--serif); letter-spacing: -.02em; color: var(--muted);
  cursor: pointer; transition: color .2s; display: inline-block; }
.names label:hover, .names input:checked + label { color: var(--ink); }
.names input { position: absolute; opacity: 0; width: 1px; height: 1px; margin: 0; }
.names input:focus-visible + label { outline: 2px solid var(--gold); outline-offset: 4px; border-radius: 4px; }
.notes { display: grid; margin-top: 28px; max-width: 34ch; }
.notes p { grid-area: 1 / 1; visibility: hidden; }
.notes p:first-child { visibility: visible; }
.stage { grid-column: 3; background: var(--surface); border-radius: var(--radius); height: 88svh; overflow: hidden;
  position: relative; display: grid; }
.stage img { grid-area: 1 / 1; width: min(400px, 78%); margin: 72px auto 0; border-radius: var(--radius); visibility: hidden;
  opacity: 0; transition: opacity .2s, visibility 0s .2s; }
.stage img:first-child { visibility: visible; opacity: 1; }

/* Questions, as reading text. */
.faq { display: grid; grid-template-columns: 3fr 1fr 8fr; padding: 0 calc(var(--margin) + var(--inset)); margin-top: var(--gap); }
.faq h2 { grid-column: 1; }
.answers { grid-column: 3; columns: 2 34ch; column-gap: 56px; }
.answers p { break-inside: avoid; margin: 0 0 20px; }
.answers strong { font-weight: 600; }

/* The close: the app's first screen, already open, on a field of gold. */
.close { margin: var(--gap) var(--margin) 0; background: var(--gold); color: var(--on-gold); border-radius: var(--radius);
  min-height: 90svh; display: grid; grid-template-columns: 6fr 5fr; align-items: end; gap: 24px; overflow: hidden;
  padding: 40px var(--inset) 0; }
.close-text { padding-bottom: 48px; display: grid; gap: 22px; }
.close h2 { font-size: clamp(3.2rem, 7vw, 7rem); line-height: .92; max-width: 9ch; }
.close p { max-width: 40ch; }
.close a { color: var(--on-gold); }
.close img { width: min(400px, 100%); justify-self: center; border-radius: var(--radius) var(--radius) 0 0; }

/* A single quiet line. */
.line { display: grid; grid-template-columns: 1fr auto 1fr; gap: 12px 24px; align-items: baseline; font-size: var(--small);
  color: var(--muted); padding: 30svh calc(var(--margin) + var(--inset)) 30px; }
.page + .line, .page .line { padding-top: 96px; }
.line nav { display: flex; flex-wrap: wrap; gap: 6px 24px; justify-content: center; }
.line .languages { justify-content: flex-end; }
.line a { text-decoration: none; }
.line a[aria-current="page"] { color: var(--gold); }

/* Motion: the compass slowly turns to the Qibla; parts of each section rise into place. Transform and opacity only. */
@media (prefers-reduced-motion: no-preference) {
  /* Each frame 6 s, fading over 1.6 s; the first already in view when the page opens. */
  .frames img { animation: frame 24s -1.6s infinite; }
  .frames img:nth-child(2) { animation-delay: 4.4s; } .frames img:nth-child(3) { animation-delay: 10.4s; }
  .frames img:nth-child(4) { animation-delay: 16.4s; }
  .frames { animation: drift 24s ease-in-out infinite alternate; }
  .hero-text > * { animation: rise .9s cubic-bezier(.2, .7, .2, 1) both; }
  .hero-text > :nth-child(2) { animation-delay: .08s; } .hero-text > :nth-child(3) { animation-delay: .16s; }
  @supports (animation-timeline: view()) {
    .rise { animation: rise linear both; animation-timeline: view(); animation-range: entry 5% entry 55%; }
    .rise.later { animation-range: entry 15% entry 65%; } .rise.last { animation-range: entry 25% entry 75%; }
  }
}
@media (prefers-reduced-motion: reduce) {
  .frames img, .frames img:first-child { opacity: 0; } .frames img:last-child { opacity: 1; }
}
@keyframes frame { 0% { opacity: 0; } 6.7% { opacity: 1; } 25% { opacity: 1; } 31.7% { opacity: 0; } 100% { opacity: 0; } }
@keyframes drift { from { transform: scale(1); } to { transform: scale(1.04); } }
@keyframes rise { from { opacity: 0; transform: translateY(24px); } to { opacity: 1; transform: none; } }

/* A phone: the compass first, the sheet sliding up over it. */
@media (max-width: 900px) {
  :root { --inset: 8px; }
  .split { display: flex; flex-direction: column; align-items: stretch; }
  .still { order: -1; height: 56svh; z-index: 0; }
  .reading { position: relative; z-index: 1; margin-top: -10svh; gap: 96px; padding-bottom: 96px; background: var(--bg);
    border-radius: var(--radius) var(--radius) 0 0; }
  .sheet { min-height: 0; padding-bottom: 48px; }
  .hero-text { margin-top: 48px; padding-bottom: 0; gap: 22px; }
  .block, .statement { padding: 0 8px; margin-inline: auto; width: 100%; max-width: 38rem; }
  .index { display: block; padding: 0 var(--margin); }
  .index-list { padding: 0 8px; max-width: 38rem; margin-inline: auto; }
  .names { display: flex; overflow-x: auto; gap: 18px; scroll-snap-type: x mandatory; padding-bottom: 8px; }
  .names label { font-size: 1.5rem; white-space: nowrap; scroll-snap-align: start; }
  .stage { height: 70svh; margin: 24px auto 0; max-width: 38rem; }
  .stage img { width: min(340px, 82%); margin: 24px auto 0; }
  .faq { display: block; padding: 0 calc(var(--margin) + 8px); max-width: calc(38rem + 2 * var(--margin)); margin-inline: auto; }
  .faq h2 { margin-bottom: 20px; }
  .answers { columns: 1; }
  .close { grid-template-columns: 1fr; align-items: start; min-height: 84svh; padding: 32px var(--inset) 0; }
  .close-text { padding-bottom: 8px; width: 100%; max-width: 38rem; margin-inline: auto; }
  .close h2 { font-size: 13vw; }
  .line { grid-template-columns: 1fr; padding: 20svh calc(var(--margin) + 8px) 24px; gap: 8px;
    max-width: calc(38rem + 2 * var(--margin) + 16px); margin-inline: auto; }
  .line nav, .line .languages { justify-content: flex-start; }
  .page { padding-inline: calc(var(--margin) + 8px); }
  .page > header { padding-bottom: 36px; }
}
`;

function document(lang, kind, title, body, bodyClass, css = '') {
  const alternates = languages.map((l) => `<link rel="alternate" hreflang="${l.code}" href="${url(l.code, kind)}">`).join('\n');
  return `<!doctype html>
<html lang="${lang.code}" dir="${lang.dir}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>${escape(title)}</title>
<meta name="description" content="${escape(lang.tagline)}">
<meta name="theme-color" content="#0E1613">
<meta name="apple-itunes-app" content="app-id=${APP_ID}">
<link rel="icon" href="/favicon.ico" sizes="32x32">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
${alternates}
<style>${STYLE}${css}</style>
</head>
<body class="${bodyClass}">
${body}
</body>
</html>
`;
}

// The quiet line that closes every page: what this is, the pages, the languages.
function footer(lang, kind) {
  const pages = MENU
    .map((p) => `<a href="${url(lang.code, p)}"${p === kind ? ' aria-current="page"' : ''}>${escape(lang.nav[p])}</a>`).join('\n');
  const switcher = languages
    .map((l) => `<a href="${url(l.code, kind)}" lang="${l.code}"${l.code === lang.code ? ' aria-current="page"' : ''}>${escape(l.language)}</a>`).join('\n');
  return `<footer class="line">
<span>${escape(lang.home.footerLine)} · ${new Date().getFullYear()}</span>
<nav aria-label="${escape(lang.appName)}">
${pages}
</nav>
<nav class="languages" aria-label="${escape(lang.language)}">
${switcher}
</nav>
</footer>`;
}

function page(lang, kind, title, body, bodyClass = 'reading-page') {
  const nav = MENU
    .map((p) => `<a href="${url(lang.code, p)}"${p === kind ? ' aria-current="page"' : ''}>${escape(lang.nav[p])}</a>`).join('\n');
  return document(lang, kind, title, `<div class="page">
<header><a class="mark" href="${url(lang.code, 'home')}">${STAR(30)}<span>${escape(lang.appName)}</span></a>
<nav aria-label="${escape(lang.appName)}">
${nav}
</nav></header>
<main>
${body}
</main>
</div>
${footer(lang, kind)}`, bodyClass);
}

// A group of radio buttons that shows one of several pictures, with CSS alone: the page runs no scripts.
function choice(id, legend, options, checked) {
  return `<fieldset class="choice">
<legend>${escape(legend)}</legend>
<div class="options">
${options.map((o) => `<input type="radio" name="${id}" id="${id}-${o.key}" value="${o.key}"${o.key === checked ? ' checked' : ''}><label for="${id}-${o.key}"${o.lang ? ` lang="${o.lang}"` : ''}>${escape(o.label)}</label>`).join('\n')}
</div>
</fieldset>`;
}

// Shows the picture whose radio button is chosen; the first picture is the one checked by default (so it shows
// where :has() isn't supported).
function chooser(scope, id, keys, container) {
  const shown = keys.map((k) => `${scope}:has(#${id}-${k}:checked) ${container} .${id}-${k}`).join(',\n');
  const hidden = `${scope}:has(.options input:checked) ${container} > *`;
  return `@supports selector(:has(a)) {
${hidden} { visibility: hidden; opacity: 0; }
${shown} { visibility: visible; opacity: 1; transition: opacity .2s; }
}`;
}

// The compass at a heading, in the page's language (English until CI has made that language's).
const frame = (lang, heading) => [lang.code, 'en'].map((code) => `qibla-${code}-${heading}.webp`)
  .find((file) => existsSync(join(here, 'static', 'screens', file)));

function home(lang) {
  const h = lang.home;
  // The Prayer times screen in each language, the page's own first.
  const order = [lang, ...languages.filter((l) => l.code !== lang.code)];
  const times = order.map((l) => ({ key: l.code, label: l.language, lang: l.code }));
  const timeShots = order.map((l, i) => `<img class="times-${l.code}" src="/screens/times-${l.code}.webp" width="720" height="1565"${i ? ' loading="lazy"' : ''} alt="${escape(h.times.alt)} · ${escape(l.language)}">`).join('\n');
  const looks = [{ key: 'night', label: h.quran.night }, { key: 'paper', label: h.quran.paper }];
  const shots = ['tasbih', 'tracker', 'map', 'lock-screen'];
  const names = h.more.items.map((item, i) => `<input type="radio" name="more" id="more-${shots[i]}" value="${shots[i]}"${i === 0 ? ' checked' : ''}><label for="more-${shots[i]}">${escape(item.title)}</label>`).join('\n');
  const notes = h.more.items.map((item, i) => `<p class="more-${shots[i]}">${escape(item.text)}</p>`).join('\n');
  const stage = h.more.items.map((item, i) => `<img class="more-${shots[i]}" src="/screens/${shots[i]}.webp" width="720" height="1565"${i ? ' loading="lazy"' : ''} alt="${escape(item.alt)}">`).join('\n');
  const faq = [...h.faq.items, ...[0, 2, 3].map((i) => lang.support.faq[i])]
    .map((item) => `<p><strong>${escape(item.q)}</strong> ${linked(item.a)}</p>`).join('\n');
  const css = [
    chooser('#times', 'times', order.map((l) => l.code), '.screens'),
    chooser('#quran', 'look', ['night', 'paper'], '.screens'),
    `@supports selector(:has(a)) {
#more:has(.names input:checked) .stage > *, #more:has(.names input:checked) .notes > * { visibility: hidden; opacity: 0; }
${shots.map((s) => `#more:has(#more-${s}:checked) .more-${s}`).join(',\n')} { visibility: visible; opacity: 1; transition: opacity .2s; }
}`,
  ].join('\n');
  return document(lang, 'home', lang.appName, `<main>
<div class="split">
<div class="reading">
<header class="sheet">
<nav class="top" aria-label="${escape(lang.appName)}">
<a href="${url(lang.code, 'support')}">${escape(lang.nav.support)}</a>
<a class="mark" href="${url(lang.code, 'home')}" aria-current="page">${STAR(34)}<span>Wajh</span></a>
<a href="${url(lang.code, 'releases')}">${escape(lang.nav.releases)}</a>
</nav>
<div class="hero-text">
<h1>${escape(h.headline)}</h1>
<p class="lede">${escape(h.sentence)}</p>
${badge(lang)}
</div>
</header>
<section class="block" id="times">
<h2 class="rise">${escape(h.times.heading)}</h2>
<p class="rise later">${escape(h.times.text)}</p>
${choice('times', h.times.legend, times, lang.code)}
<div class="screens rise last">
${timeShots}
</div>
</section>
<section class="block" id="quran">
<h2 class="rise">${escape(h.quran.heading)}</h2>
<p class="rise later">${escape(h.quran.text)}</p>
${choice('look', h.quran.legend, looks, 'night')}
<div class="screens rise last">
<img class="look-night" src="/screens/quran-night.webp" width="720" height="1565" alt="${escape(h.quran.altNight)}">
<img class="look-paper" src="/screens/quran-paper.webp" width="720" height="1565" loading="lazy" alt="${escape(h.quran.altPaper)}">
</div>
</section>
<section class="block statement" id="private">
<h2 class="rise">${escape(h.private.heading)}</h2>
<p class="rise later">${escape(h.private.text)}</p>
<p class="rise last"><a href="${url(lang.code, 'privacy')}">${escape(lang.nav.privacy)}</a></p>
</section>
</div>
<aside class="still" aria-label="${escape(lang.appName)}">
<div class="frames">
${[30, 75, 105, 126].map((d) => `<img src="/screens/${frame(lang, d)}" width="1100" height="1293" alt="">`).join('\n')}
</div>
<p class="bar"><span>${escape(h.barStart)}</span><span>${escape(h.barEnd)}</span></p>
</aside>
</div>
<section class="index" id="more">
<div class="index-list">
<h2 class="rise">${escape(h.more.heading)}</h2>
<fieldset class="names-set">
<legend class="visually-hidden">${escape(h.more.heading)}</legend>
<div class="names options">
${names}
</div>
</fieldset>
<div class="notes">
${notes}
</div>
</div>
<div class="stage">
${stage}
</div>
</section>
<section class="faq" id="faq">
<h2 class="rise">${escape(h.faq.heading)}</h2>
<div class="answers rise later">
${faq}
</div>
</section>
<section class="close" id="get">
<div class="close-text">
<h2>${escape(h.close.line)}</h2>
<p>${escape(h.close.text)}</p>
${badge(lang)}
</div>
<img src="/screens/welcome.webp" width="720" height="1565" loading="lazy" alt="${escape(h.close.alt)}">
</section>
</main>
${footer(lang, 'home')}`, 'home', css);
}

// What each version brought, newest first, in plain words.
function releases(lang) {
  const r = lang.releases;
  return page(lang, 'releases', `${r.title} · ${lang.appName}`, `<h1>${escape(r.title)}</h1>
<p>${escape(r.intro)}</p>
${r.versions.map((v) => `<h2>${escape(v.name)}</h2>\n<p class="muted">${escape(v.when)}</p>\n<ul>\n${v.items.map((item) => `<li>${escape(item)}</li>`).join('\n')}\n</ul>`).join('\n')}`);
}

function privacy(lang) {
  const p = lang.privacy;
  return page(lang, 'privacy', `${p.title} · ${lang.appName}`, `<h1>${escape(p.title)}</h1>
<p class="muted">${escape(p.updated)}</p>
<p>${linked(p.intro)}</p>
<p class="summary">${linked(p.summary)}</p>
${p.sections.map((s) => `<h2>${escape(s.heading)}</h2>\n${s.paragraphs.map((para) => `<p>${linked(para)}</p>`).join('\n')}`).join('\n')}`);
}

function accessibility(lang) {
  const a = lang.accessibility;
  return page(lang, 'accessibility', `${a.title} · ${lang.appName}`, `<h1>${escape(a.title)}</h1>
<p class="muted">${escape(a.updated)}</p>
<p>${linked(a.intro)}</p>
${a.sections.map((s) => `<h2>${escape(s.heading)}</h2>\n${s.paragraphs.map((para) => `<p>${linked(para)}</p>`).join('\n')}`).join('\n')}`);
}

function support(lang) {
  const s = lang.support;
  return page(lang, 'support', `${s.title} · ${lang.appName}`, `<h1>${escape(s.title)}</h1>
<p class="summary">${linked(s.intro)}</p>
<h2>${escape(s.faqHeading)}</h2>
${s.faq.map((item) => `<details>\n<summary>${escape(item.q)}</summary>\n<p>${linked(item.a)}</p>\n</details>`).join('\n')}`);
}

// Shown at the home page and "What's new" while MAINTENANCE is on.
function maintenance(lang, kind) {
  const m = lang.maintenance;
  return page(lang, kind, lang.appName, `<h1>${escape(m.headline)}</h1>
<p>${escape(m.text)}</p>
${badge(lang)}`, 'reading-page maintenance');
}

for (const lang of languages) {
  const folder = join(here, 'public', lang.code === 'en' ? '' : lang.code);
  mkdirSync(folder, { recursive: true });
  writeFileSync(join(folder, 'index.html'), MAINTENANCE ? maintenance(lang, 'home') : home(lang));
  writeFileSync(join(folder, 'privacy.html'), privacy(lang));
  writeFileSync(join(folder, 'support.html'), support(lang));
  writeFileSync(join(folder, 'accessibility.html'), accessibility(lang));
  writeFileSync(join(folder, 'releases.html'), MAINTENANCE ? maintenance(lang, 'releases') : releases(lang));
}
// Icons: favicon.svg is drawn by hand; favicon.ico and apple-touch-icon.png are rendered from it and the app icon.
// screens/ holds the app's own screenshots (from CI), as WebP.
cpSync(join(here, 'static'), join(here, 'public'), { recursive: true });
// Security headers for every response (served by Cloudflare from _headers): no scripts, frames, referrers or sensors.
writeFileSync(join(here, 'public', '_headers'), `/*
  Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; img-src 'self' data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'
  Referrer-Policy: no-referrer
  X-Frame-Options: DENY
  X-Content-Type-Options: nosniff
  Permissions-Policy: accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()
  Cross-Origin-Opener-Policy: same-origin
  Cross-Origin-Resource-Policy: same-origin
  X-Robots-Tag: noindex, nofollow, noarchive, nosnippet, noimageindex
`);

// Reached from the app, not through search engines or AI tools: search engines may read the pages only to see
// their noindex (blocking them here would hide it); AI crawlers, AI search and AI assistants are kept out.
writeFileSync(join(here, 'public', 'robots.txt'), `# qibla.dev holds the privacy, accessibility, release and support pages of the Qibla & Prayer app.
# They are meant to be opened from the app, not found through search engines or AI tools.

User-agent: *
Content-Signal: search=no, ai-input=no, ai-train=no
Allow: /

User-agent: GPTBot
User-agent: OAI-SearchBot
User-agent: ChatGPT-User
User-agent: ClaudeBot
User-agent: Claude-SearchBot
User-agent: Claude-User
User-agent: anthropic-ai
User-agent: PerplexityBot
User-agent: Perplexity-User
User-agent: Google-Extended
User-agent: Applebot-Extended
User-agent: Amazonbot
User-agent: Bytespider
User-agent: CCBot
User-agent: Diffbot
User-agent: meta-externalagent
User-agent: FacebookBot
User-agent: cohere-ai
User-agent: DuckAssistBot
User-agent: YouBot
User-agent: omgili
Disallow: /
`);

// RFC 9116: where to report a security problem. Expires must stay within a year: rebuild before 11 November 2027.
mkdirSync(join(here, 'public', '.well-known'), { recursive: true });
writeFileSync(join(here, 'public', '.well-known', 'security.txt'), `Contact: mailto:support@qibla.dev
Expires: 2027-11-11T23:00:00Z
Preferred-Languages: en
Canonical: https://qibla.dev/.well-known/security.txt
`);

console.log(`built ${languages.length} languages: ${languages.map((l) => l.code).join(', ')}`);
