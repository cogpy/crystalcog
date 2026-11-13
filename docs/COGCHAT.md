# The native engine on the command line and in chat

The native Crystal engine (`aphrodite_jax`, Qwen3) is part of the `crystalcog` binary. You can run it on its own, or with crystalcog's components (AtomSpace, PLN, URE, NLP) as tools.

```
                ┌──────── crystalcog chat (REPL / -e) ────────┐
 you ──text──▶  │ CogChat::Session ──▶ Engine ──▶ Qwen3        │  model reply
                │      │  ▲              (in-process or HTTP)  │
                │      │  └── tool results ◀─┐                 │
                │      └── tool calls ──▶ CogTools ──▶ CogShell ──▶ AtomSpace / PLN / URE / NLP
 you ──/cmd──▶  └──────────────────────────▲───────────────────┘
                                           │
 Galatea ChatSendMessage ("/cmd" or model tool calls) ───┘
```

| File | Role |
|---|---|
| `src/integrations/platform/aphrodite_jax/chat_format.cr` | Writes Qwen3's chat format with function calling: tools in `<tools>`, calls in `<tool_call>`, results in `<tool_response>`. Its output is byte-identical to the model's Jinja chat template, which a spec checks. It also parses `<tool_call>` blocks out of generated text. |
| `src/integrations/platform/aphrodite_jax_server.cr` | `/v1/chat/completions` accepts OpenAI `tools` and returns `tool_calls` with `finish_reason: "tool_calls"`. |
| `src/tools/cog_tools.cr` | `CogTools`: crystalcog components as named tools with JSON schemas. Each tool runs a CogShell command against one AtomSpace. |
| `src/tools/cog_chat.cr` | `CogChat`: engines (`LocalEngine` runs the model in-process, `RemoteEngine` talks to an OpenAI-compatible server), the slash commands, and `Session`, the tool-calling loop. |
| `src/tools/engine_cli.cr` | The `crystalcog` subcommands below. |

## Tools

| Tool | Arguments | Runs |
|---|---|---|
| `add_inheritance` | `child`, `parent`, optional `strength`, `confidence` | `inherit` (InheritanceLink) |
| `add_evaluation` | `predicate`, `arguments[]` | `eval` (EvaluationLink) |
| `add_implication` | `antecedent`, `consequent` | `imply` (ImplicationLink) |
| `query_atoms` | `name` | `query` |
| `list_atoms` | optional `type` | `list` |
| `pln_reason` | optional `steps` | `reason` (PLN) |
| `ure_forward_chain` | none | `ure` (URE forward chainer) |
| `nlp_process` | `text` | `nlp` |
| `parse_sentence` | `text` | `parse` (Link Grammar) |
| `see_image` | `path`, optional `scene` | `see` (vision: describes an image and adds it as a scene; see [VISION.md](VISION.md)) |
| `atomspace_stats` | none | `size` |

`crystalcog tools --json` prints the schemas exactly as the model sees them.

## Commands

Engine options are the same for every command that uses a model:
- `--model DIR|REPO_ID` loads the model in-process: a Hugging Face snapshot directory, or a repo id already in the HF cache. `CRYSTALCOG_MODEL` or `APHRODITE_MODEL` work too.
- `--url URL` uses a running OpenAI-compatible server instead. `APHRODITE_URL` works too.
- Sampling options: `--max-tokens`, `--temperature`, `--top-p`, `--top-k`, `--seed`.
- `--think` turns on Qwen3's reasoning mode. The reasoning is not shown, and tool use gets more reliable.

```bash
crystalcog chat --model Qwen/Qwen3-0.6B                 # interactive; Ctrl-D or /quit to leave
crystalcog chat --url http://127.0.0.1:2242 \
  --atomspace kb.json -e "/inherit cat mammal" -e "/inherit mammal animal" \
  -e "/reason 3" -e "Is a cat an animal?"               # one-shot, scriptable
crystalcog generate --model Qwen/Qwen3-0.6B --chat "Write a haiku about graphs"
echo "Once upon a time" | crystalcog generate --model Qwen/Qwen3-0.6B --max-tokens 40
crystalcog tokenize   --model Qwen/Qwen3-0.6B "Hello world"   # 9707 1879
crystalcog detokenize --model Qwen/Qwen3-0.6B 9707 1879       # Hello world
crystalcog cog  --atomspace kb.json inherit cat animal        # one CogShell command
crystalcog tool --atomspace kb.json pln_reason '{"steps": 2}' # one tool, JSON arguments
crystalcog tools [--json]
crystalcog engine serve --model Qwen/Qwen3-0.6B --port 2242   # same as bin/aphrodite_jax_server
crystalcog engine info  --model Qwen/Qwen3-0.6B
```

These commands print only their own output, so they can be piped. `--atomspace FILE` loads the AtomSpace from a JSON file and saves it back afterwards, so facts persist between invocations. Build with `--release -Dpreview_mt` and set `CRYSTAL_WORKERS` to use several cores.

## In chat

Messages that start with `/` are commands. The model never sees them:

| Command | Does |
|---|---|
| `/help`, `/tools` | List the commands, or the tools |
| `/tool NAME {json}` | Call a tool yourself |
| `/inherit cat animal`, `/reason 3`, `/query cat`, `/list inheritance`, `/nlp ...`, `/parse ...`, ... | Any CogShell command |
| `/engine`, `/tokenize TEXT`, `/detokenize IDS` | Engine information and the tokenizer |
| `/tools on\|off`, `/system TEXT`, `/reset` | Session settings (`crystalcog chat` only) |

Any other message goes to the model together with the tool schemas. When the model calls a tool, the session runs it against the AtomSpace, returns the result as a `tool` message, and asks the model again. It repeats this up to `max_tool_rounds` (4) times, then the model must answer in text.

Small models choose tools unreliably in Qwen3's fast (non-thinking) mode. On Qwen3-0.6B:
- "Store this fact in the knowledge base: a cat is a mammal." and "A mammal is an animal." produced `add_inheritance` calls.
- "Remember that a cat is a mammal." got a prose answer.
- With `--think` (Qwen3 reasoning, `chat_template_kwargs.enable_thinking` on the server), the model reasoned about the tools and then called `add_inheritance` for that phrasing as well. It costs a couple of hundred extra tokens per turn.
- The model sometimes writes a call as `<query_atoms name="cat"/>` instead of a `<tool_call>` block. That form is accepted for known tool names.

The Galatea server (`crystalcog platform`) works the same way:
- `/commands` sent with `ChatSendMessage` run against the platform's AtomSpace. Their output is stored as the bot's reply.
- With `PLATFORM_TOOLS=1`, which is the default for the `aphrodite_jax` backend, bot replies can call the tools through `PygmalionAgent#chat_with_tools`.

## Engine performance notes

Prompts of 8 or more tokens use a matmul kernel that widens blocks of 16 BF16 weight rows into a transposed buffer. That turns the inner loop into a vectorisable multiply-add. Attention heads run in parallel during prefill.

On 4 cores with Qwen3-0.6B, a 1,000-token prompt (system message plus the ten tool schemas) prefills in about 30 s, down from about 95 s. The KV-cache prefix is reused between turns, so later turns only process their new tokens.

Activation buffers are reused across calls, and kernel scratch memory comes from `malloc`. Allocating several megabytes per layer from the GC heap made Boehm GC spin in `GC_alloc_large` after a few requests, which hung the server.
