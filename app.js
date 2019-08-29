'use strict';

const express = require('express');

const app = express();

const scopesMapping = new Map([
  ['admin', 'read write'],
  ['user', 'read'],
  ['anonymous', '']
])

app.use(express.json())

app.post('/', (req, res) => {
  let body = req.body;
  console.log(`body received: ${JSON.stringify(body, null, 4)}`);

  const group = req.header('X-group');

  if (scopesMapping.has(group)) {
    const scopes = scopesMapping.get(group)

    body.extra = {
      scopes: scopes
    }
  }

  res.json(body);
  console.log(`body sent: ${JSON.stringify(body, null, 4)}`);
});

app.listen(8080);
console.log(`Running...`);