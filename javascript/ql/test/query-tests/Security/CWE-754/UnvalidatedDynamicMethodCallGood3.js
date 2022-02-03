var express = require('express');
var app = express();

var actions = new Map();
actions.put("play", function play(data) {
    // ...
});
actions.put("pause", function pause(data) {
    // ...
});

app.get('/perform/:action/:payload', function(req, res) {
    let action = actions.get(req.params.action);
    // GOOD: `action` is either the `play` or the `pause` function from above
    if (typeof action === 'function') {
        res.end(action(req.params.payload));
    } else {
        res.end("Unsupported action.");
    }
});