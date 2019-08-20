'use strict';

const express = require('express');

const app = express();

app.use(express.json())

app.post('/', (req, res) => {
  let body = req.body
  console.log(`body received: ${JSON.stringify(body, null, 4)}`)

  body.extra = {
    foo: 7,
    boo: {
      bar: "hello"
    }
  }

  res.json(body)
  console.log(`body sent: ${JSON.stringify(body, null, 4)}`)
});

app.listen(8080);
console.log(`Running...`);