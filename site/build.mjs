// Builds the app's small website (home, privacy policy, support) into public/, one folder per language,
// from content/<language>.json. No scripts, cookies or outside requests in the pages: node build.mjs
// Cloudflare Workers Builds runs this, then `npx cf deploy`, on every push to main that changes site/.
import { cpSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
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

const STAR = `<svg width="30" height="30" viewBox="0 0 30 30" aria-hidden="true"><g fill="none" stroke="#C9A45C" stroke-width="1.5">
<rect x="7.5" y="7.5" width="15" height="15"/><rect x="7.5" y="7.5" width="15" height="15" transform="rotate(45 15 15)"/></g></svg>`;

const STYLE = `
:root { color-scheme: dark; --bg: #0E1613; --card: #16221D; --ink: #EFE7D6; --muted: #A8A08C; --gold: #C9A45C; --line: rgba(201, 164, 92, .22); }
* { box-sizing: border-box; }
html { -webkit-text-size-adjust: 100%; }
body { margin: 0; background: var(--bg); color: var(--ink);
  font: 1.0625rem/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Noto Sans", "Noto Sans Arabic", Tahoma, sans-serif; }
.wrap { max-width: 680px; margin: 0 auto; padding: 28px 18px 40px; }
header a { display: inline-flex; align-items: center; gap: 12px; color: var(--ink); text-decoration: none; font-weight: 600; }
nav { display: flex; flex-wrap: wrap; gap: 6px 20px; margin: 14px 0 28px; padding-bottom: 12px; border-bottom: 1px solid var(--line); }
nav a { color: var(--gold); text-decoration: none; }
nav a[aria-current="page"] { color: var(--ink); }
h1, h2 { font-family: ui-serif, "New York", Georgia, "Times New Roman", serif; font-weight: 600; }
h1 { font-size: 2rem; line-height: 1.2; margin: .2em 0 .4em; }
h2 { font-size: 1.2rem; color: var(--gold); margin: 1.8em 0 .4em; }
p { margin: .6em 0; }
a { color: var(--gold); text-underline-offset: 2px; }
.muted { color: var(--muted); }
.summary { background: var(--card); border: 1px solid var(--line); border-radius: 14px; padding: 14px 18px; margin: 1.2em 0; }
ul { padding-inline-start: 1.2em; }
li { margin: .4em 0; }
details { border-bottom: 1px solid var(--line); padding: 12px 0; }
summary { cursor: pointer; font-weight: 600; }
details p { color: var(--ink); margin: .6em 0 .2em; }
footer { margin-top: 48px; padding-top: 16px; border-top: 1px solid var(--line); font-size: .92rem; }
.languages { display: flex; flex-wrap: wrap; gap: 6px 16px; margin-bottom: 10px; }
.languages a[aria-current="page"] { color: var(--ink); text-decoration: none; }
.badge { margin: 1.4em 0; }
.badge a { display: inline-block; padding: 0; }
.badge img { display: block; height: 48px; width: auto; }
`;

function page(lang, kind, title, body) {
  const alternates = languages.map((l) => `<link rel="alternate" hreflang="${l.code}" href="${url(l.code, kind)}">`).join('\n');
  const nav = Object.keys(PAGES).map((p) => `<a href="${url(lang.code, p)}"${p === kind ? ' aria-current="page"' : ''}>${escape(lang.nav[p])}</a>`).join('\n');
  const switcher = languages.map((l) => `<a href="${url(l.code, kind)}" lang="${l.code}"${l.code === lang.code ? ' aria-current="page"' : ''}>${escape(l.language)}</a>`).join('\n');
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
<style>${STYLE}</style>
</head>
<body>
<div class="wrap">
<header><a href="${url(lang.code, 'home')}">${STAR}<span>${escape(lang.appName)}</span></a></header>
<nav aria-label="${escape(lang.appName)}">
${nav}
</nav>
<main>
${body}
</main>
<footer>
<div class="languages">
${switcher}
</div>
<div class="muted">${escape(lang.footer)}</div>
</footer>
</div>
</body>
</html>
`;
}

function home(lang) {
  const h = lang.home;
  return page(lang, 'home', lang.appName, `<h1>${escape(lang.appName)}</h1>
<p class="muted">${escape(lang.tagline)}</p>
<p>${escape(h.intro)}</p>
${badge(lang)}
<ul>
${h.points.map((point) => `<li>${linked(point)}</li>`).join('\n')}
</ul>
<p>${['privacy', 'accessibility', 'releases', 'support'].map((p) => `<a href="${url(lang.code, p)}">${escape(lang.nav[p])}</a>`).join(' · ')}</p>`);
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
${s.faq.map((item) => `<details>\n<summary>${escape(item.q)}</summary>\n<p>${linked(item.a)}</p>\n</details>`).join('\n')}
<p><a href="${url(lang.code, 'privacy')}">${escape(lang.nav.privacy)}</a></p>`);
}

for (const lang of languages) {
  const folder = join(here, 'public', lang.code === 'en' ? '' : lang.code);
  mkdirSync(folder, { recursive: true });
  writeFileSync(join(folder, 'index.html'), home(lang));
  writeFileSync(join(folder, 'privacy.html'), privacy(lang));
  writeFileSync(join(folder, 'support.html'), support(lang));
  writeFileSync(join(folder, 'accessibility.html'), accessibility(lang));
  writeFileSync(join(folder, 'releases.html'), releases(lang));
}
// Icons: favicon.svg is drawn by hand; favicon.ico and apple-touch-icon.png are rendered from it and the app icon.
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
