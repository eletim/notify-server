"""Public HTTPS auth, publish and receive check; credentials only via environment."""
import base64
import json
import os
import threading
import time
import urllib.request
import urllib.error

base = os.environ['NOTIFY_SERVER'].rstrip('/')
topic = os.environ.get('NOTIFY_TOPIC', 'agents')
auth = 'Basic ' + base64.b64encode((os.environ['NTFY_ADMIN_USER'] + ':' + os.environ['NTFY_ADMIN_PASSWORD']).encode()).decode()
def request(path, authorization=None, data=None, headers=None):
    h = headers or {}
    if authorization:
        h['Authorization'] = authorization
    return urllib.request.urlopen(urllib.request.Request(base + path, data=data, headers=h), timeout=20)

for path in ['/', '/login', '/agents', '/config.js', '/static/images/ntfy.png', '/static/langs/en.json', '/sw.js', '/manifest.webmanifest', '/v1/health']:
    with request(path) as r:
        assert r.status == 200, path
with request('/manifest.webmanifest') as r:
    manifest = json.load(r)
    assert manifest['scope'] == '/ntfy/' and manifest['start_url'] == '/ntfy/'
with request('/v1/account', auth) as r:
    assert json.load(r)['username'] == os.environ['NTFY_ADMIN_USER']
try:
    request('/' + topic, data=b'anonymous must fail')
    raise AssertionError('Anonymous publish was accepted')
except urllib.error.HTTPError as e:
    assert e.code in (401, 403)
received = []
ready = threading.Event()
marker = 'subpath-smoke-' + str(time.time_ns())
def subscribe():
    with request('/' + topic + '/json', auth) as r:
        for line in r:
            event = json.loads(line)
            if event['event'] == 'open':
                ready.set()
            if event.get('message') == marker:
                received.append(event)
                return
thread = threading.Thread(target=subscribe, daemon=True)
thread.start()
assert ready.wait(15), 'Subscription did not open'
with request('/' + topic, 'Bearer ' + os.environ['NOTIFY_TOKEN'], marker.encode(), {'Title': 'Subpath deployment check', 'Click': base + '/' + topic}) as r:
    sent = json.load(r)
thread.join(15)
assert received and received[0]['id'] == sent['id'], 'Live receive failed'
assert received[0]['click'] == base + '/' + topic
print('PASS: pages, static assets, manifest scope, login API, anonymous denial, live authenticated publish/receive and click URL')
