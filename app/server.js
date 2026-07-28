'use strict';

const express = require('express');
const path = require('path');
const os = require('os');

const app = express();

const PORT = Number(process.env.PORT) || 3000;
const HOST = process.env.HOST || '0.0.0.0';
const APP_MESSAGE = process.env.APP_MESSAGE || 'Hello World';
const APP_ENV = process.env.APP_ENV || 'local';
const APP_VERSION = process.env.APP_VERSION || require('./package.json').version;

app.disable('x-powered-by');

// Static front end
app.use(
  express.static(path.join(__dirname, 'public'), {
    index: 'index.html',
    maxAge: '1h',
  })
);

// Data the front end renders
app.get('/api/hello', (req, res) => {
  res.json({
    message: APP_MESSAGE,
    environment: APP_ENV,
    version: APP_VERSION,
    hostname: os.hostname(),
    timestamp: new Date().toISOString(),
  });
});

// Kubernetes liveness probe
app.get('/healthz', (req, res) => {
  res.status(200).json({ status: 'ok' });
});

// Kubernetes readiness probe
app.get('/readyz', (req, res) => {
  res.status(200).json({ status: 'ready' });
});

app.use((req, res) => {
  res.status(404).json({ error: 'Not Found', path: req.path });
});

if (require.main === module) {
  const server = app.listen(PORT, HOST, () => {
    console.log(`hello-world-frontend listening on http://${HOST}:${PORT} (env=${APP_ENV})`);
  });

  // Let Kubernetes terminate the pod cleanly instead of killing in-flight requests.
  const shutdown = (signal) => {
    console.log(`${signal} received, closing server`);
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(1), 10_000).unref();
  };
  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
}

module.exports = app;
