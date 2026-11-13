# CogServer Network API Documentation

This document describes the network API provided by the Crystal CogServer implementation.

## Overview

The CogServer provides multiple network interfaces for interacting with the OpenCog AtomSpace:

- **HTTP REST API**: RESTful endpoints for AtomSpace operations (Port 18080)
- **WebSocket Protocol**: Real-time communication support (Port 18080)
- **Telnet Interface**: Command-line interface simulation (Port 17001)

## Starting the CogServer

```bash
# Start with default settings
crystal run src/cogserver/cogserver_main.cr

# Or with custom ports
crystal run src/cogserver/cogserver_main.cr -- --host 0.0.0.0 --port 17002 --ws-port 18081
```

## HTTP REST API Endpoints

### GET /status
Returns server status and statistics.

**Response:**
```json
{
  "running": true,
  "host": "localhost",
  "port": 17001,
  "ws_port": 18080,
  "active_sessions": 2,
  "atomspace_size": 42,
  "atomspace_nodes": 25,
  "atomspace_links": 17
}
```

### GET /atomspace
Returns AtomSpace information and contents.

**Response:**
```json
{
  "size": 42,
  "nodes": 25,
  "links": 17,
  "atoms": ["ConceptNode:dog", "ConceptNode:animal", "InheritanceLink(dog, animal)"]
}
```

### GET /atoms
Returns all atoms in the AtomSpace with optional type filtering.

**Query Parameters:**
- `type` (optional): Filter by atom type (e.g., `ConceptNode`, `InheritanceLink`)

**Response:**
```json
{
  "count": 3,
  "atoms": [
    {
      "type": "ConceptNode",
      "name": "dog",
      "outgoing": null,
      "truth_value": {
        "strength": 0.9,
        "confidence": 0.8
      },
      "string": "ConceptNode:dog"
    }
  ]
}
```

### POST /atoms
Create an atom. The body is the atom's content form, at the top level or under `"atom"`. A link's `outgoing` entries are nested atoms or the handles of existing atoms.

```json
{
  "type": "INHERITANCE_LINK",
  "truth_value": {"strength": 0.9, "confidence": 0.8},
  "outgoing": [
    {"type": "CONCEPT_NODE", "name": "cat"},
    {"type": "CONCEPT_NODE", "name": "animal"}
  ]
}
```

- Truth values merge with what is already stored. Send `"replace": true` to set them exactly.
- The response has status 201 and `{"success": true, "atom": {"handle", "type", "name", "string"}}`.
- A bad type or an unknown handle gets status 400, and nothing is added.

### GET /atoms/:handle
One atom: `handle`, `type`, `name`, `outgoing` (handles), `truth_value`, `string`, and `wire`, the atom's full content form with nested outgoing atoms. Status 404 when there is no such atom.

### DELETE /atoms/:handle
Remove an atom. Status 409 when other links still use it, 404 when there is no such atom.

### DELETE /atoms
Remove the atom described by the body (`{"atom": <content form>}`), for clients that know an atom's content and not the server's handle for it.

`AtomSpace::CogStorageNode` uses these endpoints to store, fetch, load and remove atoms on a remote CogServer.

### GET /sessions
Returns information about active sessions.

**Response:**
```json
{
  "active_sessions": 2,
  "sessions": [
    {
      "id": "abc123def456",
      "type": "websocket",
      "created_at": "2024-09-04T10:30:00Z",
      "duration": 45.2,
      "closed": false
    }
  ]
}
```

### GET /ping
Health check endpoint.

**Response:**
```json
{
  "status": "ok",
  "timestamp": "2024-09-04T10:30:00Z",
  "server": "CogServer 0.1.0"
}
```

### GET /version
Returns server version information.

**Response:**
```json
{
  "version": "0.1.0",
  "crystal_version": "1.10.1",
  "server_type": "CogServer",
  "api_version": "1.0"
}
```

## WebSocket Protocol

Connect to `ws://localhost:18080/`. The server completes the RFC 6455 handshake and then exchanges JSON text frames. It selects the `json` subprotocol only when the client offers it.

```javascript
const ws = new WebSocket('ws://localhost:18080/');
ws.onmessage = (e) => console.log(JSON.parse(e.data));
ws.onopen = () => {
  ws.send(JSON.stringify({action: 'subscribe', events: ['AtomAdded', 'TruthValueChanged']}));
  ws.send(JSON.stringify({action: 'command', command: 'inherit cat animal', id: 1}));
};
```

### Client messages

| Message | Reply |
|---|---|
| `{"action": "subscribe", "events": ["AtomAdded", "*"]}` | `{"type": "subscribed", "events": [...]}` with all current subscriptions |
| `{"action": "unsubscribe", "events": [...]}` | `{"type": "subscribed", "events": [...]}` |
| `{"action": "command", "command": "inherit cat animal"}` | `{"type": "result", "command": ..., "output": ...}` |
| `{"action": "stats"}` | `{"type": "stats", "data": {...}}` |
| `{"action": "ping"}` | `{"type": "pong"}` |

- An optional `"id"` is echoed in the reply.
- A frame that is not a JSON object is run as a shell command.
- A bad request gets `{"type": "error", "message": ...}`.
- On connect the server sends `{"type": "welcome", "session": ..., "version": ..., "events": [...]}`.

### Events

Subscribed events arrive as `{"type": "AtomAdded", "timestamp": "...", "data": {...}}`. Event names match without regard to case or underscores; `*` subscribes to everything.

| Event | Data |
|---|---|
| `AtomAdded`, `TruthValueChanged`, `AttentionChanged` | `handle`, `type`, `name`, `truth_value` |
| `AtomRemoved` | `handle`, `type` |
| `StorageAttached`, `StorageDetached` | `name`, `storage_type` |
| `AtomSpaceStats` | `size`, `nodes`, `links` (every 5 seconds) |
| `Heartbeat` | `active_monitors` (every 10 seconds) |

Each connection has a queue of 256 outgoing messages. When a client reads too slowly, further events are dropped for that client; replies wait for room.

## Telnet Interface

Port 17001 speaks two protocols on the same port.

### Interactive shell

A raw TCP client gets a line-based shell on the server's AtomSpace:

```bash
telnet localhost 17001
# or
printf 'inherit cat animal\nreason 2\nquit\n' | nc localhost 17001
```

It accepts the server commands below and every CogShell command (`concept`, `inherit`, `eval`, `imply`, `reason`, `ure`, `query`, `list <type>`, `size`, `tv`, `nlp`, `parse`, `see`, `clear`).

### One-shot HTTP

A client that opens with an HTTP request line gets the same commands through a query parameter:

```bash
curl "http://localhost:17001/?cmd=help"
curl "http://localhost:17001/?cmd=inherit%20cat%20animal"
```

### Available Commands

- `help` - Show available commands
- `info` - Display server information
- `atomspace` - Show AtomSpace statistics
- `list` - List atoms in AtomSpace (first 10)
- `stats` - Show session statistics
- `sessions` - Show open sessions
- `quit/exit` - Close session

### Example Session
```bash
$ curl "http://localhost:17001/?cmd=help"
Welcome to CogServer 0.1.0
Session ID: abc123def456
AtomSpace contains 42 atoms
Type 'help' for available commands
cog> 

Available commands:
help          - Show this help message
info          - Show server information  
atomspace     - Show AtomSpace statistics
list          - List atoms in AtomSpace
stats         - Show session statistics
quit, exit    - Close session
cog>
```

## Error Handling

All endpoints return consistent JSON error responses:

```json
{
  "error": "Error description"
}
```

Common HTTP status codes:
- `200` - Success
- `201` - Created (for POST requests)
- `400` - Bad Request
- `404` - Not Found
- `405` - Method Not Allowed
- `500` - Internal Server Error
- `501` - Not Implemented

## Integration Examples

### Python Client
```python
import requests
import json

# Get server status
response = requests.get('http://localhost:18080/status')
status = response.json()
print(f"Server running: {status['running']}")

# Add an atom
atom_data = {"type": "ConceptNode", "name": "python"}
response = requests.post('http://localhost:18080/atoms', json=atom_data)
result = response.json()
print(f"Created atom: {result['atom']['string']}")
```

### JavaScript WebSocket
```javascript
const ws = new WebSocket('ws://localhost:18080/');

ws.onopen = () => ws.send(JSON.stringify({action: 'subscribe', events: ['*']}));
ws.onmessage = (event) => console.log('Received:', JSON.parse(event.data));
ws.onerror = (error) => console.error('WebSocket error:', error);
```

### Shell Scripts
```bash
#!/bin/bash

# Check if server is running
curl -f http://localhost:18080/ping > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "CogServer is running"
else
    echo "CogServer is not responding"
    exit 1
fi

# Get AtomSpace statistics
curl -s http://localhost:18080/atomspace | jq '.size'
```

## Performance Considerations

- The HTTP API is designed for occasional administrative tasks
- WebSocket connections provide better performance for real-time applications
- Large AtomSpaces may cause slower response times for `/atoms` endpoint
- Session cleanup happens automatically when connections are closed

## Security Notes

The server has no authentication, and its shell commands can change the AtomSpace and read image files on the server host (`see`). It listens on localhost by default; keep it there or behind something that authenticates. For production use, consider:

- Adding authentication mechanisms
- Implementing rate limiting
- Using HTTPS/WSS for encrypted connections
- Restricting network access to trusted clients
- Implementing proper session management and timeouts