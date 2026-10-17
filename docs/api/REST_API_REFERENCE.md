# OpenCog REST API Reference

## Overview

The OpenCog REST API provides programmatic access to the AtomSpace, CogServer, and various OpenCog components. This API follows RESTful principles and returns JSON responses.

## Base Information

- **Base URL**: `http://localhost:5000/api/v1.1`
- **Content-Type**: `application/json`
- **Authentication**: None (for local development)

## API Endpoints

### 1. Atoms API

#### GET /api/v1.1/atoms

Retrieves atoms from the AtomSpace with optional filtering.

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | int | No | Specific atom handle |
| `type` | string | No | Atom type filter |
| `name` | string | No | Atom name filter |
| `filterby` | string | No | Predefined filter ('stirange' or 'attentionalfocus') |
| `stimin` | float | No | Minimum STI value (requires filterby=stirange) |
| `stimax` | float | No | Maximum STI value (requires filterby=stirange) |
| `tvStrengthMin` | float | No | Minimum truth value strength |
| `tvConfidenceMin` | float | No | Minimum truth value confidence |
| `tvCountMin` | float | No | Minimum truth value count |
| `includeIncoming` | boolean | No | Include incoming sets |
| `includeOutgoing` | boolean | No | Include outgoing sets |
| `dot` | boolean | No | Return in DOT graph format |
| `callback` | string | No | JSONP callback function |

**Example Requests:**

```bash
# Get all atoms
curl "http://localhost:5000/api/v1.1/atoms"

# Get atoms by type
curl "http://localhost:5000/api/v1.1/atoms?type=ConceptNode"

# Get atoms with incoming sets
curl "http://localhost:5000/api/v1.1/atoms?includeIncoming=true"

# Get atoms in attentional focus
curl "http://localhost:5000/api/v1.1/atoms?filterby=attentionalfocus"

# Get atoms in STI range
curl "http://localhost:5000/api/v1.1/atoms?filterby=stirange&stimin=5&stimax=10"

# Get specific atom by handle
curl "http://localhost:5000/api/v1.1/atoms/123"
```

**Response Format:**

```json
{
  "result": {
    "complete": "true",
    "skipped": "false",
    "total": 10,
    "atoms": [
      {
        "handle": 6,
        "name": "",
        "type": "InheritanceLink",
        "outgoing": [2, 1],
        "incoming": [],
        "truthvalue": {
          "type": "simple",
          "details": {
            "count": "0.4000000059604645",
            "confidence": "0.0004997501382604241",
            "strength": "0.5"
          }
        },
        "attentionvalue": {
          "lti": 0,
          "sti": 0,
          "vlti": false
        }
      }
    ]
  }
}
```

#### POST /api/v1.1/atoms

Creates a new atom or updates an existing one.

**Request Body:**

For a Node:
```json
{
  "type": "ConceptNode",
  "name": "Frog",
  "truthvalue": {
    "type": "simple",
    "details": {
      "strength": 0.8,
      "count": 0.2
    }
  }
}
```

For a Link:
```json
{
  "type": "InheritanceLink",
  "outgoing": [1, 2],
  "truthvalue": {
    "type": "simple",
    "details": {
      "strength": 0.5,
      "count": 0.4
    }
  }
}
```

**Response:**

```json
{
  "atoms": {
    "handle": 6,
    "name": "",
    "type": "InheritanceLink",
    "outgoing": [2, 1],
    "incoming": [],
    "truthvalue": {
      "type": "simple",
      "details": {
        "count": "0.4000000059604645",
        "confidence": "0.0004997501382604241",
        "strength": "0.5"
      }
    },
    "attentionvalue": {
      "lti": 0,
      "sti": 0,
      "vlti": false
    }
  }
}
```

#### PUT /api/v1.1/atoms/{id}

Updates an atom's truth value or attention value.

**Path Parameters:**
- `id` (int, required): Atom handle

**Request Body:**

```json
{
  "truthvalue": {
    "type": "simple",
    "details": {
      "strength": 0.005,
      "count": 0.8
    }
  },
  "attentionvalue": {
    "sti": 9,
    "lti": 2,
    "vlti": true
  }
}
```

**Response:**

```json
{
  "atoms": {
    "handle": 6,
    "name": "",
    "type": "InheritanceLink",
    "outgoing": [2, 1],
    "incoming": [],
    "truthvalue": {
      "type": "simple",
      "details": {
        "count": "0.4000000059604645",
        "confidence": "0.0004997501382604241",
        "strength": "0.5"
      }
    },
    "attentionvalue": {
      "lti": 0,
      "sti": 0,
      "vlti": false
    }
  }
}
```

#### DELETE /api/v1.1/atoms/{id}

Removes an atom from the AtomSpace.

**Path Parameters:**
- `id` (int, required): Atom handle

**Response:**

```json
{
  "result": {
    "handle": 2,
    "success": "true"
  }
}
```

### 2. Types API

#### GET /api/v1.1/types

Returns a list of valid atom types.

**Response:**

```json
{
  "types": [
    "TrueLink",
    "NumberNode",
    "OrLink",
    "PrepositionalRelationshipNode",
    "ConceptNode",
    "InheritanceLink",
    "EvaluationLink",
    "MemberLink",
    "SimilarityLink",
    "SubsetLink"
  ]
}
```

### 3. Shell API

#### POST /api/v1.1/shell

Sends a shell command to the cogserver.

**Request Body:**

```json
{
  "command": "agents-step"
}
```

**Additional Commands:**
```json
{"command": "agents-step opencog::SimpleImportanceDiffusionAgent"}
{"command": "agents-step opencog::HebbianUpdatingAgent"}
{"command": "agents-step opencog::AttentionAllocationAgent"}
```

**Response:**

```json
{
  "result": "Command executed successfully"
}
```

### 4. Scheme API

#### POST /api/v1.1/scheme

Sends a Scheme command to the interpreter.

**Request Body:**

```json
{
  "command": "(cog-set-af-boundary! 100)"
}
```

**Common Scheme Commands:**

```json
{"command": "(cog-atomspace)"}
{"command": "(cog-get-atoms 'ConceptNode)"}
{"command": "(cog-get-atoms 'InheritanceLink)"}
{"command": "(cog-set-af-boundary! 100)"}
{"command": "(cog-set-af-boundary! 200)"}
{"command": "(cog-af-boundary)"}
```

**Response:**

```json
{
  "response": "100\n"
}
```

## Error Responses

### 400 Bad Request

```json
{
  "error": "Invalid request: Required parameter command missing"
}
```

### 404 Not Found

```json
{
  "error": "Handle not found"
}
```

### 500 Internal Server Error

```json
{
  "error": "Error processing request. Check your parameters"
}
```

## Usage Examples

### Python Client

```python
import requests
import json

class OpenCogClient:
    def __init__(self, base_url="http://localhost:5000/api/v1.1"):
        self.base_url = base_url
    
    def get_atoms(self, **params):
        """Get atoms with optional filtering"""
        response = requests.get(f"{self.base_url}/atoms", params=params)
        return response.json()
    
    def create_atom(self, atom_data):
        """Create a new atom"""
        response = requests.post(f"{self.base_url}/atoms", json=atom_data)
        return response.json()
    
    def update_atom(self, atom_id, update_data):
        """Update an atom's truth value or attention value"""
        response = requests.put(f"{self.base_url}/atoms/{atom_id}", json=update_data)
        return response.json()
    
    def delete_atom(self, atom_id):
        """Delete an atom"""
        response = requests.delete(f"{self.base_url}/atoms/{atom_id}")
        return response.json()
    
    def get_types(self):
        """Get list of valid atom types"""
        response = requests.get(f"{self.base_url}/types")
        return response.json()
    
    def execute_shell_command(self, command):
        """Execute a shell command"""
        response = requests.post(f"{self.base_url}/shell", json={"command": command})
        return response.json()
    
    def execute_scheme_command(self, command):
        """Execute a Scheme command"""
        response = requests.post(f"{self.base_url}/scheme", json={"command": command})
        return response.json()

# Usage example
client = OpenCogClient()

# Get all atoms
atoms = client.get_atoms()

# Create a concept node
concept_data = {
    "type": "ConceptNode",
    "name": "TestConcept",
    "truthvalue": {
        "type": "simple",
        "details": {
            "strength": 0.8,
            "count": 0.2
        }
    }
}
result = client.create_atom(concept_data)

# Execute a shell command
shell_result = client.execute_shell_command("agents-step")

# Execute a Scheme command
scheme_result = client.execute_scheme_command("(cog-atomspace)")
```

### JavaScript Client

```javascript
class OpenCogClient {
    constructor(baseUrl = 'http://localhost:5000/api/v1.1') {
        this.baseUrl = baseUrl;
    }
    
    async getAtoms(params = {}) {
        const queryString = new URLSearchParams(params).toString();
        const response = await fetch(`${this.baseUrl}/atoms?${queryString}`);
        return await response.json();
    }
    
    async createAtom(atomData) {
        const response = await fetch(`${this.baseUrl}/atoms`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(atomData)
        });
        return await response.json();
    }
    
    async updateAtom(atomId, updateData) {
        const response = await fetch(`${this.baseUrl}/atoms/${atomId}`, {
            method: 'PUT',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(updateData)
        });
        return await response.json();
    }
    
    async deleteAtom(atomId) {
        const response = await fetch(`${this.baseUrl}/atoms/${atomId}`, {
            method: 'DELETE'
        });
        return await response.json();
    }
    
    async getTypes() {
        const response = await fetch(`${this.baseUrl}/types`);
        return await response.json();
    }
    
    async executeShellCommand(command) {
        const response = await fetch(`${this.baseUrl}/shell`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({ command })
        });
        return await response.json();
    }
    
    async executeSchemeCommand(command) {
        const response = await fetch(`${this.baseUrl}/scheme`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({ command })
        });
        return await response.json();
    }
}

// Usage example
const client = new OpenCogClient();

// Get all atoms
client.getAtoms().then(atoms => console.log(atoms));

// Create a concept node
const conceptData = {
    type: "ConceptNode",
    name: "TestConcept",
    truthvalue: {
        type: "simple",
        details: {
            strength: 0.8,
            count: 0.2
        }
    }
};
client.createAtom(conceptData).then(result => console.log(result));
```

### cURL Examples

```bash
# Get all atoms
curl "http://localhost:5000/api/v1.1/atoms"

# Get atoms by type
curl "http://localhost:5000/api/v1.1/atoms?type=ConceptNode"

# Create a new atom
curl -X POST "http://localhost:5000/api/v1.1/atoms" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "ConceptNode",
    "name": "TestConcept",
    "truthvalue": {
      "type": "simple",
      "details": {
        "strength": 0.8,
        "count": 0.2
      }
    }
  }'

# Update an atom
curl -X PUT "http://localhost:5000/api/v1.1/atoms/123" \
  -H "Content-Type: application/json" \
  -d '{
    "truthvalue": {
      "type": "simple",
      "details": {
        "strength": 0.9,
        "count": 0.3
      }
    }
  }'

# Delete an atom
curl -X DELETE "http://localhost:5000/api/v1.1/atoms/123"

# Get atom types
curl "http://localhost:5000/api/v1.1/types"

# Execute shell command
curl -X POST "http://localhost:5000/api/v1.1/shell" \
  -H "Content-Type: application/json" \
  -d '{"command": "agents-step"}'

# Execute Scheme command
curl -X POST "http://localhost:5000/api/v1.1/scheme" \
  -H "Content-Type: application/json" \
  -d '{"command": "(cog-atomspace)"}'
```

## Rate Limiting

Currently, no rate limiting is implemented. However, it's recommended to:

1. Limit requests to reasonable frequencies
2. Implement proper error handling
3. Use connection pooling for high-frequency requests

## Security Considerations

1. **No Authentication**: The API has no authentication by default
2. **Local Access Only**: Designed for local development
3. **Input Validation**: Validate all inputs before sending to the API
4. **HTTPS**: Use HTTPS in production environments

## Performance Tips

1. **Pagination**: For large result sets, use appropriate filtering
2. **Connection Reuse**: Reuse HTTP connections when possible
3. **Batch Operations**: Consider batching multiple operations
4. **Caching**: Cache frequently accessed data

## Troubleshooting

### Common Issues

1. **Connection Refused**: Ensure the OpenCog server is running
2. **Invalid JSON**: Check request body format
3. **Missing Parameters**: Verify all required parameters are provided
4. **Atom Not Found**: Confirm the atom handle exists

### Debug Mode

Enable debug logging in your OpenCog configuration to get detailed error information.

## Version History

- **v1.1**: Current version with full atom management capabilities
- **v1.0**: Initial release with basic functionality