'use strict';

const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const app = require('../server');

let server;
let base;

before(async () => {
  await new Promise((resolve) => {
    server = app.listen(0, '127.0.0.1', resolve);
  });
  base = `http://127.0.0.1:${server.address().port}`;
});

after(() => server.close());

test('GET /healthz returns ok', async () => {
  const res = await fetch(`${base}/healthz`);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { status: 'ok' });
});

test('GET /readyz returns ready', async () => {
  const res = await fetch(`${base}/readyz`);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { status: 'ready' });
});

test('GET /api/hello returns the greeting payload', async () => {
  const res = await fetch(`${base}/api/hello`);
  assert.equal(res.status, 200);

  const body = await res.json();
  assert.equal(body.message, 'Hello World');
  assert.ok(body.hostname, 'hostname is present');
  assert.ok(body.version, 'version is present');
  assert.ok(!Number.isNaN(Date.parse(body.timestamp)), 'timestamp is a valid date');
});

test('GET / serves the front end', async () => {
  const res = await fetch(`${base}/`);
  assert.equal(res.status, 200);
  assert.match(res.headers.get('content-type'), /text\/html/);
  assert.match(await res.text(), /Hello World/);
});

test('unknown routes return 404 JSON', async () => {
  const res = await fetch(`${base}/nope`);
  assert.equal(res.status, 404);
  assert.equal((await res.json()).error, 'Not Found');
});
