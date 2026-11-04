/* Run with NODE_PATH pointing to an installed Playwright package.
   Uses SSH to read credentials in memory; never writes them to artifacts. */
const { chromium } = require('playwright');
const { execFileSync } = require('node:child_process');
const assert = require('node:assert/strict');
(async () => {
  const raw = execFileSync('ssh', ['ubuntu@eletim.jp', 'cat ~/notify-server/.auth.env' + (process.env.NOTIFY_TEST_LOGIN_FILE ? ' ' + process.env.NOTIFY_TEST_LOGIN_FILE : '')], {encoding:'utf8'});
  const env = Object.fromEntries(raw.trim().split('\n').map(line => { const i=line.indexOf('=');return [line.slice(0,i),line.slice(i+1)]; }));
  const browser = await chromium.launch({headless:true});
  try {
    const context = await browser.newContext({locale:'en-US'});
    const page = await context.newPage();
    const failures = [];
    const errors = [];
    const sockets = [];
    page.on('websocket', socket => sockets.push(new URL(socket.url()).pathname));
    page.on('response', response => { if (response.status() === 404) failures.push(new URL(response.url()).pathname); });
    page.on('pageerror', error => errors.push(error.message));
    await page.goto('https://eletim.jp/ntfy/login');
    await page.locator('#username').fill(env.NTFY_ADMIN_USER);
    await page.locator('#password').fill(env.NTFY_ADMIN_PASSWORD);
    await page.getByRole('button', {name:'Sign in', exact:true}).click();
    await page.waitForURL('https://eletim.jp/ntfy/');
    await page.getByRole('button', {name:'Subscribe to topic', exact:true}).click();
    await page.getByRole('textbox', {name:'Topic name, e.g. phil_alerts'}).fill('agents');
    const subscribe = page.getByRole('button', {name:'Subscribe', exact:true});
    if (await subscribe.isDisabled()) {
      await page.getByRole('button', {name:'Cancel', exact:true}).click();
      await page.getByRole('button', {name:/^agents( \(connecting\))?$/}).click();
    } else {
      await subscribe.click();
    }
    await page.waitForURL('https://eletim.jp/ntfy/agents');
    await page.waitForTimeout(1500);
    const marker = `browser-subpath-${Date.now()}`;
    const sent = await context.request.post('https://eletim.jp/ntfy/agents', {
      headers: {'Authorization':`Bearer ${env.NOTIFY_TOKEN}`, 'Title':'Browser deployment check', 'Click':'https://eletim.jp/ntfy/agents'}, data:marker
    });
    assert.equal(sent.status(), 200);
    await page.getByText(marker, {exact:true}).waitFor({timeout:20000});
    const registrations = await page.evaluate(async () => (await navigator.serviceWorker.getRegistrations()).map(r => ({scope:r.scope,script:r.active?.scriptURL})));
    assert(registrations.some(r => r.scope === 'https://eletim.jp/ntfy/' && r.script === 'https://eletim.jp/ntfy/sw.js'));
    assert(sockets.includes('/ntfy/agents/ws'), 'Topic WebSocket did not use the public prefix');
    assert.deepEqual(failures, []);
    assert.deepEqual(errors, []);
    await page.reload();
    await page.getByText(marker, {exact:true}).waitFor();
    await page.goto('https://eletim.jp/ntfy/settings');
    await page.getByText('Notifications', {exact:true}).first().waitFor();
    assert(page.url().startsWith('https://eletim.jp/ntfy/'));
    console.log('PASS: browser login/redirect, topic subscription, live notification receipt, reload, settings, scoped Service Worker, no 404/page errors');
  } finally { await browser.close(); }
})().catch(error => { console.error(error.message); process.exitCode=1; });
