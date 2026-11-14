# Pygmalion platform in crystalcog

crystalcog runs the three parts of the Pygmalion platform itself:

```
client ──Connect JSON──▶ Galatea server ──REST──▶ Paphos backend
 (galatea.v1, /api/auth)    │                    (/api/v1: users, characters,
                            │                     chats, messages)
                            └──PygmalionAgent──▶ Aphrodite engine
                                                 (OpenAI-compatible inference)
```

| Component | Code | Contract it implements |
|---|---|---|
| Galatea frontend server | `src/integrations/platform/galatea_server.cr` | `galatea.v1` `AuthService`, `BotService` and `ChatService` from [9cog/galatea-frontend](https://github.com/9cog/galatea-frontend) `shared/galatea/v1/*.proto`, over the Connect JSON protocol. Also the web app's `/api/auth/{signup,login,status,logout}` routes, `/api/health`, and static serving of `web/dist` with an SPA fallback. |
| Paphos backend | `src/integrations/platform/paphos_server.cr`, `paphos_client.cr` | The `/api/v1` REST API of [9cog/paphos-backend](https://github.com/9cog/paphos-backend): Lucky-style `{"user": {...}}` bodies, HS256 JWT bearer auth, `{message,param,details}` errors, characters and chats. Adds `GET`/`POST /chats/:id/messages` and a per-user snapshot store (`GET /snapshots`, `GET`/`PUT`/`DELETE /snapshots/:key`), which upstream lacks. |
| Aphrodite engine | `src/integrations/platform/aphrodite_engine.cr` | Launches and supervises an OpenAI-compatible inference server and gives `PygmalionAgent` its endpoint. |
| aphrodite_jax_server | `src/integrations/platform/aphrodite_jax_server.cr`, `aphrodite_jax/*.cr`, `src/bin/aphrodite_jax_server.cr` | Native Crystal port of [aphrodite-jax](https://github.com/aphrodite-engine/aphrodite-jax)'s small-model engine (Qwen3), with no Python. It has a safetensors loader, a byte-level BPE tokenizer, the Qwen3 forward pass with a KV cache, a sampler, and an OpenAI-compatible HTTP server. |
| Stack | `src/integrations/platform/stack.cr`, `crystalcog platform` | Starts all three and wires them together. |

When an AtomSpace is attached, which the stack does, conversations are written into it as `pygmalion:said` and `pygmalion:mentions` EvaluationLinks.

## Engine backends

| `APHRODITE_BACKEND` | Launches | When to use |
|---|---|---|
| `aphrodite` | `aphrodite run <model>` | PygmalionAI's aphrodite-engine; needs a GPU |
| `llama_cpp` | `python -m llama_cpp.server` (external, Python) | GGUF models on CPU. Pygmalion models get the Metharme (`pygmalion`) chat format automatically. |
| `aphrodite_jax` (default) | `aphrodite_jax_server` (native Crystal) | Small Qwen3 models (e.g. `Qwen/Qwen3-0.6B`) on CPU, in pure Crystal |
| `external` | nothing | Use a server that is already running (`APHRODITE_URL`) |

### aphrodite_jax_server (native Crystal)

aphrodite-jax is a Python/JAX library. It supports Qwen3 only, needs cuDNN or Triton on its main path, and ships no HTTP server. crystalcog therefore implements the same small-model engine natively:

| File | What it does |
|---|---|
| `aphrodite_jax/safetensors.cr` | Reads BF16/F16/F32 safetensors, including sharded models. Weights stay in BF16. |
| `aphrodite_jax/tokenizer.cr` | Byte-level BPE from `tokenizer.json`: NFC normalisation, added and special tokens, the split regex, ranked merges. Its output matches Hugging Face `tokenizers` token for token. |
| `aphrodite_jax/qwen3.cr`, `kernels.cr` | The Qwen3 forward pass: RMSNorm, rotate-half RoPE, GQA with per-head q/k norm, SwiGLU, tied embeddings, KV cache. Matrix rows run in parallel with `-Dpreview_mt`. |
| `aphrodite_jax/generator.cr` | Generation: prompt-prefix KV reuse; temperature, top-k, top-p, min-p, repetition penalty and seed; EOS and stop strings; UTF-8-safe streaming; the ChatML chat format. |
| `aphrodite_jax_server.cr` | The OpenAI-compatible HTTP server: `/v1/models`, `/health`, `/version`, `/v1/chat/completions` (per-token SSE streaming), `/v1/completions`, `/v1/tokenize`, `/v1/detokenize`. |

Build and run it:

```bash
shards build aphrodite_jax_server --release -Dpreview_mt
CRYSTAL_WORKERS=4 bin/aphrodite_jax_server --model Qwen/Qwen3-0.6B --port 2242
```

`--model` takes a local snapshot directory (`config.json`, `tokenizer.json`, `*.safetensors`) or a repo id that is already in the Hugging Face cache.

Measured on 4 CPU cores with Qwen3-0.6B:

| | Crystal engine | aphrodite-jax (CPU, pure-JAX path) |
|---|---|---|
| Load time | 1.7 s | 28 s |
| Generation speed | about 5 tokens/s | about 1 token/s |

The logits match an independent NumPy implementation of Qwen3 (top-5 token ids identical, values equal to 3 decimals). Run that check with `QWEN3_MODEL_DIR=<snapshot> crystal spec spec/integrations/platform/aphrodite_jax_spec.cr`.

## Running it

```bash
# Pygmalion-2-7B on CPU through llama.cpp
pip install "llama-cpp-python[server]"
APHRODITE_BACKEND=llama_cpp \
APHRODITE_MODEL=/models/pygmalion-2-7b.Q4_K_M.gguf APHRODITE_SERVED_NAME=pygmalion-2-7b \
PAPHOS_DATA_FILE=paphos.json \
  crystalcog platform

# Small model on the native Crystal engine (no Python)
shards build aphrodite_jax_server --release -Dpreview_mt
APHRODITE_BACKEND=aphrodite_jax APHRODITE_MODEL=Qwen/Qwen3-0.6B CRYSTAL_WORKERS=4 \
  crystalcog platform
```

Other settings:
- Ports: `PAPHOS_PORT` (3000) and `GALATEA_PORT` (8080).
- Bind address: `PLATFORM_HOST` (127.0.0.1).
- Reply length: `PLATFORM_MAX_TOKENS` (160).
- Built web app to serve: `GALATEA_STATIC_DIR`.
- Engine port: `APHRODITE_PORT` (2242).
- Python for the llama.cpp backend: `APHRODITE_PYTHON`.
- Path to the native server binary: `APHRODITE_JAX_SERVER` (default: next to `crystalcog`, then `bin/`, then `PATH`).
- Signing secrets: `SECRET_KEY_BASE` (Paphos) and `JWT_SECRET` (Galatea).

Without `APHRODITE_MODEL`, the stack attaches to whatever already serves the engine port.

## Talking to it

```bash
G=http://127.0.0.1:8080
rpc() { curl -s -H 'Content-Type: application/json' ${TOKEN:+-H "Authorization: Bearer $TOKEN"} \
          -X POST "$G/galatea.v1.$1" -d "$2"; }
rpc AuthService/SignUp '{"email":"ada@example.com","password":"secret123"}'
TOKEN=$(rpc AuthService/SignIn '{"email":"ada@example.com","password":"secret123"}' | jq -r .accessToken)
rpc BotService/BotCreate '{"bot":{"name":"Galatea","description":"A marble sculpture brought to life",
                                  "personality":"warm, curious and gentle"}}'
CHAT=$(rpc ChatService/ChatCreate '{"botId":"galatea"}' | jq -r .chat.id)
rpc ChatService/ChatSendMessage "{\"chatId\":\"$CHAT\",\"message\":\"How do you feel?\"}"
```

`Bot` carries only `name`, `description` and `avatarUrl` in the proto. `BotCreate` and `BotUpdate` also accept `personality`, `greeting` and `scenario`, which feed the character prompt.

`ChatSubscribe` (server streaming) and `AuthService/Verify` return `unimplemented`.

Chat messages that start with `/` are crystalcog commands, such as `/inherit cat animal`, `/reason 3` or `/query cat`. They run against the platform's AtomSpace without calling the model. With `PLATFORM_TOOLS=1`, which is the default for the `aphrodite_jax` backend, the model can also call crystalcog's tools while it replies. See [COGCHAT.md](COGCHAT.md), which also covers the `crystalcog chat`, `generate`, `tokenize`, `cog`, `tool` and `engine` commands.

## Persistence

`PaphosBackend::Connector` (`src/integrations/paphos_connector.cr`) stores cognitive state through the snapshot store:
- `store_snapshot(id)` / `load_snapshot(id)` save and restore the coordinator's state.
- `persistence.store_atomspace_data` / `load_atomspace_data` save and restore a whole AtomSpace, links and truth values included.
- With `batch_operations`, or while offline, writes wait in a queue until `flush_batch`.

## Events and service functions

The Paphos backend also has an event stream and named service functions, which upstream lacks.

| Endpoint | Purpose |
|---|---|
| `POST /events` | Publish `{"event": {"type", "source"?, "data"?}}`. `data` is an object of strings. |
| `GET /events?after=&types=&limit=&wait=` | The caller's events with an id above `after`, oldest first. `wait` (seconds, at most 25) holds the request until one arrives. |
| `GET /events/stream?after=&types=` | The same events as server-sent events: those above `after` first, then each new one as it is published. |
| `GET /actions` | The service functions: name and description. |
| `POST /actions/:name` | Run one with `{"action": {"args": {...}}}`. A refusal is a 422, an unknown name a 404. |

- Events belong to the user who published them. The server keeps the last 1,000; with a data file they survive a restart and ids go on counting, so a client's `after` stays valid.
- Events are stored in a journal beside the data file, `<data file>.events`, one JSON line each. Publishing adds a line and leaves the data file alone. The journal is cut back to the kept events when it reaches 2,000 lines. A data file from before the journal is read and its events moved over.
- A stream sends `id:`, `event:` (the type) and `data:` (the event as JSON) for each event, and a comment line every 15 seconds when nothing happens. A client that reconnects with a `Last-Event-ID` header continues after that id. The stream ends when the client closes it or the server stops.
- Built-in functions are `echo`, `stats`, `snapshot.copy` and `events.clear`. A host program adds its own with `server.register_action(name, description) { |args, user_id| ... }` and refuses a call by raising `PaphosBackend::Server::ActionError`.
- Every call records an `action_executed` event.

`PaphosBackend::Connector` uses these once it is connected:

- `send_command(name, params)` runs the function of that name. The reply has `status` (`success`, `error`, or `local` when there is no backend), the result as JSON in `result`, and each result field as `result.<field>`.
- `execute_service_function(name, args)` returns the result as JSON and raises on a refusal.
- `event_stream.publish_event` sends to the backend and `receive_events(wait)` returns what arrived since the last call, from any client of the account. Events published while the backend is unreachable stay queued and go out on the next `connect` or publish.
- `event_stream.follow_events { |event| ... }` opens the stream and calls the block with each event of the subscribed types as it is published, starting after the last one consumed. `stop_following` or `disconnect` closes it. `PaphosBackend::Client#follow_events(after, types) { |event| ... }` is the same without the connector and returns a follow to `close`.

## Verification

- **Specs:** `crystal spec spec/integrations/platform/` covers:
  - Paphos: auth, ownership, validation, chats, messages, JSON persistence.
  - Galatea: Connect auth, bots, chats, errors, empty-reply retries, `/api/auth` cookies, static files.
  - The engine supervisor.
  - The native engine: safetensors, tokenizer, KV-cache consistency, sampling, stops, streaming, and the HTTP API, run on a tiny generated Qwen3.
- **Live, `llama_cpp` backend:**
  - `crystalcog platform` launched PygmalionAI's Pygmalion-2-7B (Q4_K_M GGUF) with the Metharme format.
  - SignUp → SignIn → BotCreate → ChatCreate → ChatSendMessage over `galatea.v1` returned in-character replies, e.g. *"\*Galatea's eyes widen with wonder.\* I want to see the sunrise!"*.
  - The chat was stored in Paphos and survived a restart.
- **Live, `aphrodite_jax` backend (native Crystal):**
  - `crystalcog platform` launched `aphrodite_jax_server` with Qwen3-0.6B. It was ready in 2 s and no Python process ran.
  - Galatea chats returned in-character replies in about 17 s per 64 tokens, e.g. *"\*Galatea looks around the workshop, her marble skin glowing with curiosity.\* I want to see the world... and I want to see the people."*
