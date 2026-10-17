# OpenCog API Documentation

## Table of Contents

1. [Overview](#overview)
2. [Core Components](#core-components)
3. [REST API](#rest-api)
4. [Python APIs](#python-apis)
5. [Rust APIs](#rust-apis)
6. [Machine Learning APIs](#machine-learning-apis)
7. [Natural Language Processing APIs](#natural-language-processing-apis)
8. [AtomSpace APIs](#atomspace-apis)
9. [CogServer APIs](#cogserver-apis)
10. [PLN (Probabilistic Logic Networks) APIs](#pln-apis)
11. [DeSTIN APIs](#destin-apis)
12. [Examples and Usage](#examples-and-usage)

## Overview

OpenCog is a comprehensive artificial general intelligence (AGI) framework that provides multiple APIs for cognitive architecture, natural language processing, machine learning, and knowledge representation. This documentation covers all public APIs, functions, and components available in the OpenCog ecosystem.

## Core Components

### Main CrystalCog Implementation

**Directory:** `src/`

CrystalCog is the complete Crystal language implementation of the OpenCog framework:

```crystal
# Example: Basic AtomSpace usage
require "./src/atomspace/atomspace"
require "./src/cogutil/logger"

atomspace = AtomSpace::AtomSpace.new
concept = atomspace.add_node(AtomSpace::AtomType::ConceptNode, "Example")

CogUtil::Logger.info("Created atom: #{concept.name}")
```

# Creating the model
knn = KNeighborsClassifier(n_neighbors=1)

# Fitting the model
knn.fit(X_train, y_train)

# Making predictions
y_pred = knn.predict(X_test)

# Evaluating the model
print("Test set score: {:.2f}".format(np.mean(y_pred == y_test)))
```

## REST API

### Base URL
```
http://localhost:5000/api/v1.1
```

### Authentication
No authentication required for local development.

### Endpoints

#### 1. Atoms API

**Base Path:** `/api/v1.1/atoms`

##### GET /api/v1.1/atoms
Retrieves atoms from the AtomSpace.

**Parameters:**
- `id` (int, optional): Specific atom handle
- `type` (string, optional): Atom type filter
- `name` (string, optional): Atom name filter
- `filterby` (string, optional): Predefined filters ('stirange' or 'attentionalfocus')
- `stimin` (float, optional): Minimum STI value (with filterby=stirange)
- `stimax` (float, optional): Maximum STI value (with filterby=stirange)
- `tvStrengthMin` (float, optional): Minimum truth value strength
- `tvConfidenceMin` (float, optional): Minimum truth value confidence
- `tvCountMin` (float, optional): Minimum truth value count
- `includeIncoming` (boolean, optional): Include incoming sets
- `includeOutgoing` (boolean, optional): Include outgoing sets
- `dot` (boolean, optional): Return in DOT graph format
- `callback` (string, optional): JSONP callback function

**Example Request:**
```bash
curl "http://localhost:5000/api/v1.1/atoms?type=ConceptNode&includeIncoming=true"
```

**Example Response:**
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

##### POST /api/v1.1/atoms
Creates a new atom or updates an existing one.

**Request Body:**
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

##### PUT /api/v1.1/atoms/{id}
Updates an atom's truth value or attention value.

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

##### DELETE /api/v1.1/atoms/{id}
Removes an atom from the AtomSpace.

#### 2. Types API

**Base Path:** `/api/v1.1/types`

##### GET /api/v1.1/types
Returns a list of valid atom types.

**Example Response:**
```json
{
  "types": [
    "TrueLink",
    "NumberNode",
    "OrLink",
    "PrepositionalRelationshipNode"
  ]
}
```

#### 3. Shell API

**Base Path:** `/api/v1.1/shell`

##### POST /api/v1.1/shell
Sends a shell command to the cogserver.

**Request Body:**
```json
{
  "command": "agents-step"
}
```

#### 4. Scheme API

**Base Path:** `/api/v1.1/scheme`

##### POST /api/v1.1/scheme
Sends a Scheme command to the interpreter.

**Request Body:**
```json
{
  "command": "(cog-set-af-boundary! 100)"
}
```

**Example Response:**
```json
{
  "response": "100\n"
}
```

## Python APIs

### AtomSpace Python API

**Module:** `opencog.atomspace`

#### Core Functions

##### `scheme_eval(atomspace, scheme_code)`
Evaluates Scheme code in the given atomspace.

**Parameters:**
- `atomspace`: The atomspace instance
- `scheme_code` (string): Scheme code to execute

**Example:**
```python
from opencog.scheme_wrapper import scheme_eval

# Initialize atomspace
python_atomspace = AtomSpace()
scheme_eval(python_atomspace, "(use-modules (opencog) (opencog exec))")
```

##### `scheme_eval_as(scheme_code)`
Evaluates Scheme code and returns the result as a Python object.

**Parameters:**
- `scheme_code` (string): Scheme code to execute

**Returns:**
- Python object representing the Scheme result

**Example:**
```python
from opencog.scheme_wrapper import scheme_eval_as

atomspace = scheme_eval_as('(cog-atomspace)')
```

### Natural Language Processing APIs

#### Sentiment Analysis API

**Module:** `opencog.opencog.nlp.sentiment.basic_sentiment_analysis`

##### `Splitter` Class
Splits text into sentences and tokenizes them.

**Methods:**
- `split(text)`: Splits text into tokenized sentences

**Example:**
```python
from opencog.opencog.nlp.sentiment.basic_sentiment_analysis import Splitter

splitter = Splitter()
tokenized_sentences = splitter.split("This is a sentence. This is another one.")
```

##### `POSTagger` Class
Performs part-of-speech tagging.

**Methods:**
- `pos_tag(sentences)`: Tags sentences with POS information

**Example:**
```python
from opencog.opencog.nlp.sentiment.basic_sentiment_analysis import POSTagger

tagger = POSTagger()
tagged_sentences = tagger.pos_tag(tokenized_sentences)
```

##### `DictionaryTagger` Class
Tags sentences using dictionary-based sentiment analysis.

**Methods:**
- `tag(postagged_sentences)`: Tags sentences with sentiment information
- `tag_sentence(sentence, tag_with_lemmas=False)`: Tags a single sentence

**Example:**
```python
from opencog.opencog.nlp.sentiment.basic_sentiment_analysis import DictionaryTagger

dictionary_paths = ['path/to/dictionary1.yml', 'path/to/dictionary2.yml']
tagger = DictionaryTagger(dictionary_paths)
tagged_sentences = tagger.tag(tagged_sentences)
```

##### `sentiment_score(review)`
Calculates sentiment score for a review.

**Parameters:**
- `review` (string): Text to analyze

**Returns:**
- Sentiment score (float)

**Example:**
```python
from opencog.opencog.nlp.sentiment.basic_sentiment_analysis import sentiment_score

score = sentiment_score("This product is amazing!")
print(f"Sentiment score: {score}")
```

##### `sentiment_parse(plain_text)`
Parses plain text and returns sentiment analysis.

**Parameters:**
- `plain_text` (string): Text to analyze

**Returns:**
- Dictionary with sentiment analysis results

**Example:**
```python
from opencog.opencog.nlp.sentiment.basic_sentiment_analysis import sentiment_parse

result = sentiment_parse("I love this product!")
print(result)
```

#### Chatbot API

**Module:** `opencog.opencog.nlp.chatbot.telegram_bot`

##### Telegram Bot Integration
Provides integration with Telegram for chatbot functionality.

**Setup:**
```python
from opencog.opencog.nlp.chatbot.telegram_bot import *

# Initialize atomspace and load modules
python_atomspace = AtomSpace()
scheme_eval(python_atomspace, "(use-modules (opencog) (opencog exec))")
atomspace = scheme_eval_as('(cog-atomspace)')
scheme_eval(atomspace, '(use-modules (opencog nlp))')
scheme_eval(atomspace, '(use-modules (opencog nlp chatbot))')
scheme_eval(atomspace, '(use-modules (opencog nlp relex2logic))')
scheme_eval(atomspace, '(load-r2l-rulebase)')
```

**Key Functions:**
- `start(bot, update)`: Handles /start command
- `help(bot, update)`: Handles /help command
- `echo(bot, update)`: Processes user messages
- `error(bot, update)`: Handles errors

**Example Usage:**
```python
from telegram.ext import Updater, CommandHandler, MessageHandler, Filters

def main():
    updater = Updater(TOKEN)
    dp = updater.dispatcher
    
    dp.add_handler(CommandHandler("start", start))
    dp.add_handler(CommandHandler("help", help))
    dp.add_handler(MessageHandler(Filters.text, echo))
    dp.add_error_handler(error)
    
    updater.start_polling()
    updater.idle()
```

### Anaphora Resolution API

**Module:** `opencog.opencog.nlp.anaphora`

#### Hobbs Algorithm
**File:** `opencog/opencog/nlp/anaphora/agents/hobbs.py`

Provides anaphora resolution using the Hobbs algorithm.

**Example:**
```python
from opencog.opencog.nlp.anaphora.agents.hobbs import HobbsAgent

agent = HobbsAgent()
resolved_text = agent.resolve_anaphora(text)
```

## Rust APIs

### Hyperon Library

**Module:** `src/lib.rs`

#### Functions

##### `hello()`
Prints a greeting message from Hyperon.

**Example:**
```rust
use your_crate_name;

fn main() {
    your_crate_name::hello();
}
```

**Output:**
```
Hello from Hyperon!
```

## Machine Learning APIs

### DeSTIN (Deep Spatiotemporal Inference Network)

**Module:** `python-destin/destin`

#### Components

##### Network
**File:** `python-destin/destin/network.py`

Provides deep spatiotemporal inference network functionality.

##### Layer
**File:** `python-destin/destin/layer.py`

Implements network layer functionality.

##### Node
**File:** `python-destin/destin/node.py`

Implements network node functionality.

##### Clustering
**File:** `python-destin/destin/clustering.py`

Provides clustering algorithms.

##### Auto Encoder
**File:** `python-destin/destin/auto_encoder.py`

Implements auto-encoder functionality.

**Example Usage:**
```python
import destin

# Import specific components
from destin import network, layer, node, clustering, auto_encoder

# Use the components
network_instance = network.Network()
layer_instance = layer.Layer()
node_instance = node.Node()
clustering_instance = clustering.Clustering()
auto_encoder_instance = auto_encoder.AutoEncoder()
```

## PLN (Probabilistic Logic Networks) APIs

**Module:** `pln/opencog/torchpln/pln`

### Core Components

#### Common Utilities
**File:** `pln/opencog/torchpln/pln/common.py`

##### `TTruthValue`
Represents a truth value in PLN.

##### `get_ttv(atom)`
Gets the truth value of an atom.

**Parameters:**
- `atom`: The atom to get truth value from

**Returns:**
- Truth value object

##### `set_ttv(atom, ttv)`
Sets the truth value of an atom.

**Parameters:**
- `atom`: The atom to set truth value for
- `ttv`: The truth value to set

**Example:**
```python
from pln.common import TTruthValue, get_ttv, set_ttv

# Get truth value
ttv = get_ttv(atom)

# Set truth value
new_ttv = TTruthValue(0.8, 0.2)
set_ttv(atom, new_ttv)
```

#### Rules
**Directory:** `pln/opencog/torchpln/pln/rules/`

Contains various PLN inference rules organized by category:

- **Propositional Rules:** `pln/rules/propositional/`
- **Other rule categories:** Additional rule directories

## AtomSpace APIs

### Core AtomSpace Functions

**Module:** `atomspace/opencog/cython/opencog`

#### Scheme Wrapper
**File:** `atomspace/opencog/cython/opencog/scheme_wrapper.py`

Provides Python bindings for Scheme evaluation.

**Note:** This module has been renamed to `opencog.scheme`. The wrapper provides backward compatibility.

#### Execution Functions
**File:** `atomspace/opencog/cython/opencog/exec.py`

Provides execution functionality for OpenCog.

**Note:** This module has been renamed to `opencog.execute`. The wrapper provides backward compatibility.

#### BindLink Functions
**File:** `atomspace/opencog/cython/opencog/bindlink.py`

Provides functionality for pattern matching and binding.

## CogServer APIs

### CogServer Python Integration

**Module:** `cogserver/opencog/cython/opencog`

Provides Python bindings for the CogServer functionality.

## Examples and Usage

### Basic OpenCog Setup

```python
# Initialize atomspace
from opencog.scheme_wrapper import scheme_eval, scheme_eval_as

python_atomspace = AtomSpace()
scheme_eval(python_atomspace, "(use-modules (opencog) (opencog exec))")
atomspace = scheme_eval_as('(cog-atomspace)')

# Load additional modules
scheme_eval(atomspace, '(use-modules (opencog nlp))')
scheme_eval(atomspace, '(use-modules (opencog nlp chatbot))')
```

### Sentiment Analysis Example

```python
from opencog.opencog.nlp.sentiment.basic_sentiment_analysis import (
    Splitter, POSTagger, DictionaryTagger, sentiment_score
)

# Initialize components
splitter = Splitter()
tagger = POSTagger()
dictionary_paths = ['sentiment_dictionary.yml']
dict_tagger = DictionaryTagger(dictionary_paths)

# Analyze text
text = "I love this product! It's amazing."
tokenized = splitter.split(text)
tagged = tagger.pos_tag(tokenized)
sentiment = sentiment_score(text)

print(f"Sentiment score: {sentiment}")
```

### REST API Example

```python
import requests

# Get all atoms
response = requests.get("http://localhost:5000/api/v1.1/atoms")
atoms = response.json()

# Create a new atom
new_atom = {
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

response = requests.post("http://localhost:5000/api/v1.1/atoms", json=new_atom)
result = response.json()
```

### DeSTIN Example

```python
import destin
from destin import network, layer, node

# Create network components
network_instance = network.Network()
layer_instance = layer.Layer()
node_instance = node.Node()

# Configure and use components
# (Specific usage depends on the implementation details)
```

## Error Handling

### Common Error Codes

- **200**: Success
- **400**: Bad Request (invalid parameters)
- **404**: Not Found (handle not found)
- **500**: Internal Server Error

### Python Exception Handling

```python
try:
    result = scheme_eval(atomspace, scheme_code)
except Exception as e:
    print(f"Scheme evaluation error: {e}")
```

## Performance Considerations

1. **AtomSpace Operations**: Large atomspaces may require significant memory
2. **Scheme Evaluation**: Complex Scheme operations can be computationally expensive
3. **REST API**: Consider pagination for large result sets
4. **Machine Learning**: DeSTIN and other ML components may require GPU acceleration for large datasets

## Security Considerations

1. **REST API**: No authentication by default - implement proper security for production
2. **Scheme Evaluation**: Be careful with user-provided Scheme code
3. **File Operations**: Validate file paths and permissions
4. **Network Operations**: Use HTTPS in production environments

## Dependencies

### Python Dependencies
- numpy
- pandas
- scikit-learn
- nltk
- yaml
- telegram.ext (for chatbot)
- requests (for REST API)

### Rust Dependencies
- Standard library (no external dependencies for basic functionality)

### System Dependencies
- Python 3.x
- Rust toolchain
- OpenCog Scheme interpreter
- Various NLP and ML libraries

## Contributing

When adding new APIs or modifying existing ones:

1. Update this documentation
2. Add appropriate examples
3. Include error handling documentation
4. Test with the provided examples
5. Follow the existing code style and patterns

## License

This project is licensed under the MIT License. See the `LICENSE` file for details.