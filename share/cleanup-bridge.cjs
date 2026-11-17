'use strict';
// Loopback bridge between Handy's "Custom" post-processing provider and OpenRouter.
// Why a bridge instead of pasting the key into Handy:
//   - the API key stays in the OS keyring (secret-tool), never in a settings file
//   - requests are limited to zero-data-retention endpoints, temperature 0
//   - your dictionary is sent along as spelling hints (see dictionaryHint below)
//   - the bar widget learns when cleanup starts and finishes
// If cleanup fails for any reason, Handy pastes the raw transcript instead.
const http = require('node:http');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const MODEL = process.env.HANDY_CLEANUP_MODEL || 'anthropic/claude-haiku-5.5';
const PORT = Number(process.env.HANDY_CLEANUP_PORT || 18784);
const SETTINGS = path.join(os.homedir(), '.local/share/com.pais.handy/settings_store.json');
const DICTIONARY = process.env.HANDY_DICTIONARY || path.join(os.homedir(), '.config/handy-omarchy/dictionary.txt');

// The dictionary lives in its own file, not in Handy's custom words. Parakeet cannot take a
// vocabulary, so Handy fuzzy-matches every phrase against its custom words and swaps in
// anything close enough, so a business name that sounds like an everyday phrase replaces
// that phrase whenever you say it. The installer
// moves Handy's list here and empties it. Words added in Handy later are still sent as hints,
// but they also turn Handy's swapping back on, so add new words to this file instead.
function readDictionary() {
  const words = [];
  try {
    for (const line of fs.readFileSync(DICTIONARY, 'utf8').split('\n')) {
      const word = line.trim();
      if (word && !word.startsWith('#')) words.push(word);
    }
  } catch { /* No dictionary file. */ }
  try {
    words.push(...(JSON.parse(fs.readFileSync(SETTINGS, 'utf8')).settings.custom_words || []));
  } catch { /* No Handy settings yet. */ }
  return [...new Set(words)];
}
function dictionaryHint(words) {
  if (!words.length) return null;
  return { role: 'system', content: 'Custom words and phrases, for spelling hints only. Use an entry only when the speaker clearly said that name or term. Never replace ordinary words or a different intelligible name with one of these entries:\n' + JSON.stringify(words) };
}

function reportStage(stage) {
  try {
    const target = process.env.XDG_RUNTIME_DIR + '/handy-cleanup-stage.json';
    fs.writeFileSync(target + '.tmp', JSON.stringify({ stage, at: Date.now() / 1000 }), { mode: 0o600 });
    fs.renameSync(target + '.tmp', target);
  } catch { /* Status reporting must never interrupt dictation. */ }
}
let cachedKey = null;
function credential() {
  if (cachedKey) return cachedKey;
  const key = execFileSync('/usr/bin/secret-tool', ['lookup', 'service', 'handy-omarchy', 'account', 'openrouter'],
    { encoding: 'utf8', timeout: 5000 }).trim();
  if (!key) throw new Error('No OpenRouter key in the keyring');
  cachedKey = key;
  return key;
}
function send(res, code, data) {
  res.writeHead(code, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(data));
}
const server = http.createServer(async (req, res) => {
  if (req.method === 'GET' && req.url === '/v1/models') {
    return send(res, 200, { object: 'list', data: [{ id: MODEL, object: 'model', owned_by: 'openrouter' }] });
  }
  if (req.method !== 'POST' || req.url !== '/v1/chat/completions') return send(res, 404, { error: 'Unknown endpoint' });
  try {
    const chunks = []; let size = 0;
    for await (const chunk of req) {
      size += chunk.length;
      if (size > 512 * 1024) return send(res, 413, { error: 'Request too large' });
      chunks.push(chunk);
    }
    const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    if (body.model !== MODEL || !Array.isArray(body.messages) || body.stream) return send(res, 400, { error: 'Unsupported request' });
    const messages = [...body.messages];
    const hint = dictionaryHint(readDictionary());
    if (hint) messages.unshift(hint);
    reportStage('cleanup');
    const upstream = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST', redirect: 'error', signal: AbortSignal.timeout(25000),
      headers: { Authorization: 'Bearer ' + credential(), 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: MODEL, messages, temperature: 0, max_tokens: 8192,
        provider: { zdr: true, sort: 'latency' }, reasoning: { enabled: false } }),
    });
    if (upstream.status === 401) cachedKey = null;
    if (!upstream.ok) return send(res, 502, { error: 'Cleanup provider returned HTTP ' + upstream.status });
    const result = await upstream.json();
    const text = result.choices?.[0]?.message?.content;
    if (typeof text !== 'string' || result.choices[0].finish_reason === 'length') return send(res, 502, { error: 'Cleanup response was incomplete' });
    // An empty cleanup result would paste nothing. Fail instead so Handy keeps the raw transcript.
    if (!text.trim()) return send(res, 502, { error: 'Cleanup response was empty' });
    reportStage('pasting');
    send(res, 200, result);
  } catch {
    reportStage('pasting');
    send(res, 502, { error: 'Cleanup unavailable; preserve the original transcript' });
  }
});
server.requestTimeout = 30000;
if (require.main === module) {
  server.listen(PORT, '127.0.0.1', () => console.log('Handy cleanup bridge ready on 127.0.0.1:' + PORT + ' using ' + MODEL));
}
module.exports = { readDictionary, dictionaryHint };
