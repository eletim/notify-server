"""Patch the pinned ntfy source. Caddy strips the public prefix before proxying."""
import os
import re
from pathlib import Path

base = os.environ.get('NTFY_BASE_PATH', '/ntfy/').rstrip('/') + '/'
if not re.fullmatch(r'/(?:[A-Za-z0-9_-]+/)*', base):
    raise SystemExit('NTFY_BASE_PATH must be / or slash-separated path segments')
prefix = base.rstrip('/')
def edit(name, old, new):
    p = Path(name)
    s = p.read_text()
    if old not in s:
        raise SystemExit(f'Upstream changed: {name}: {old!r}')
    p.write_text(s.replace(old, new))

# Public URLs may contain the prefix; request routing remains internal at /.
edit('cmd/serve.go', '} else if u.Path != "" {', '} else if u.RawQuery != "" || u.Fragment != "" {')
edit('server/server_web.go', '"net/http"', '"net/http"\n "net/url"\n "strings"')
edit('server/server_web.go', 'response := &webManifestResponse{', 'publicURL, _ := url.Parse(s.config.BaseURL)\n basePath := strings.TrimRight(publicURL.Path, "/")\n response := &webManifestResponse{')
edit('server/server_web.go', 'Scope:           "/",', 'Scope:           basePath + "/",')
edit('server/server_web.go', 'StartURL:        s.config.WebRoot,', 'StartURL:        basePath + s.config.WebRoot,')
edit('server/server_web.go', 'SRC: "/static/', 'SRC: basePath + "/static/')
edit('server/server_web.go', 'BaseURL:             "", // Will translate to window.location.origin', 'BaseURL:             s.config.BaseURL,')
edit('web/vite.config.js', '  build: {', f'  base: "{base}",\n  build: {{')
edit('web/src/components/App.jsx', '<BrowserRouter>', f'<BrowserRouter basename="{prefix or "/"}">')
edit('web/src/app/Notifier.js', 'new URL(routes.forSubscription(subscription), window.location.origin)', f'new URL("{prefix}" + routes.forSubscription(subscription), window.location.origin)')
edit('web/public/sw.js', 'new URL(message.topic, self.location.origin)', f'new URL("{base}" + message.topic, self.location.origin)')
edit('web/public/sw.js', 'new URL(self.location.origin)', f'new URL("{base}", self.location.origin)')
edit('web/public/sw.js', '"/app.html"', f'"{base}app.html"')
edit('web/public/sw.js', '^${config.app_root}$', f'^{prefix}${{config.app_root}}$')
# Source references are literal public paths, including CSS fonts and sounds.
for p in list(Path('web/src').rglob('*')) + list(Path('web/public').rglob('*')) + [Path('web/index.html')]:
    if p.is_file() and p.suffix in {'.js', '.jsx', '.css', '.html', '.svg'}:
        s = p.read_text()
        s = re.sub(r'(["\x27(])/static/', lambda m: m[1] + base + 'static/', s)
        s = s.replace('"/config.js"', f'"{base}config.js"').replace('"/manifest.webmanifest"', f'"{base}manifest.webmanifest"')
        p.write_text(s)
# Full page auth transitions bypass React Router's basename.
for name in ['web/src/app/Session.js', 'web/src/app/transition.js']:
    edit(name, 'window.location.href = url;', f'window.location.href = url.startsWith("/") ? "{prefix}" + url : url;')
for name, route in [('web/src/components/App.jsx', 'login'), ('web/src/components/Account.jsx', 'app'), ('web/src/components/UpgradeDialog.jsx', 'signup')]:
    edit(name, f'window.location.href = routes.{route};', f'window.location.href = "{prefix}" + routes.{route};')
edit('web/src/components/App.jsx', 'window.location.pathname !== routes.login', f'window.location.pathname !== "{prefix}" + routes.login')
# Avoid probing nonexistent regional translation assets (en-US, ja-JP, ...).
import json
languages = sorted(p.stem for p in Path('web/public/static/langs').glob('*.json'))
edit('web/src/app/i18n.js', 'fallbackLng: "en",', 'fallbackLng: "en",\n      supportedLngs: ' + json.dumps(languages) + ',')
# This image does not embed MkDocs; documentation links use the official site.
edit('web/src/components/Navigation.jsx', 'openUrl("/docs")', 'openUrl("https://docs.ntfy.sh/")')
edit('web/src/components/Account.jsx', 'href="/docs/publish/#access-tokens"', 'href="https://docs.ntfy.sh/publish/#access-tokens"')
edit('cmd/serve.go', 'base-url must not have a path (%s), as hosting ntfy on a sub-path is not supported, e.g. https://ntfy.mydomain.com", u.Path', 'base-url must not have a query or fragment (%s)", baseURL')
