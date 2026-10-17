# OpenCog Python API Reference

## Overview

This document provides comprehensive documentation for all Python APIs available in the OpenCog ecosystem, including AtomSpace operations, natural language processing, machine learning components, and utility functions.

## Table of Contents

1. [AtomSpace Python API](#atomspace-python-api)
2. [Natural Language Processing APIs](#natural-language-processing-apis)
3. [Machine Learning APIs](#machine-learning-apis)
4. [PLN (Probabilistic Logic Networks) APIs](#pln-apis)
5. [Utility Functions](#utility-functions)
6. [Examples and Best Practices](#examples-and-best-practices)

## AtomSpace Python API

### Core Module: `opencog.scheme_wrapper`

**File:** `atomspace/opencog/cython/opencog/scheme_wrapper.py`

#### Functions

##### `scheme_eval(atomspace, scheme_code)`

Evaluates Scheme code in the given atomspace.

**Parameters:**
- `atomspace`: The atomspace instance to evaluate code in
- `scheme_code` (string): Scheme code to execute

**Returns:**
- None (executes code in the atomspace)

**Example:**
```python
from opencog.scheme_wrapper import scheme_eval

# Initialize atomspace
python_atomspace = AtomSpace()

# Load OpenCog modules
scheme_eval(python_atomspace, "(use-modules (opencog) (opencog exec))")
scheme_eval(python_atomspace, "(use-modules (opencog nlp))")
scheme_eval(python_atomspace, "(use-modules (opencog nlp chatbot))")
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

# Get the current atomspace
atomspace = scheme_eval_as('(cog-atomspace)')

# Get all concept nodes
concept_nodes = scheme_eval_as("(cog-get-atoms 'ConceptNode)")

# Get attention focus boundary
af_boundary = scheme_eval_as("(cog-af-boundary)")
```

### Execution Module: `opencog.exec`

**File:** `atomspace/opencog/cython/opencog/exec.py`

**Note:** This module has been renamed to `opencog.execute`. The wrapper provides backward compatibility.

### BindLink Module: `opencog.bindlink`

**File:** `atomspace/opencog/cython/opencog/bindlink.py`

Provides functionality for pattern matching and binding.

## Natural Language Processing APIs

### Sentiment Analysis Module

**Module:** `opencog.opencog.nlp.sentiment.basic_sentiment_analysis`

**File:** `opencog/opencog/nlp/sentiment/basic_sentiment_analysis.py`

#### Classes

##### `Splitter`

Splits text into sentences and tokenizes them.

**Methods:**

###### `__init__(self)`
Initializes the splitter with NLTK components.

**Example:**
```python
from opencog.opencog.nlp.sentiment.basic_sentiment_analysis import Splitter

splitter = Splitter()
```

###### `split(self, text)`
Splits text into tokenized sentences.

**Parameters:**
- `text` (string): Input text to split

**Returns:**
- List of lists of words (tokenized sentences)

**Example:**
```python
text = "This is a sentence. This is another one."
tokenized_sentences = splitter.split(text)
# Result: [['this', 'is', 'a', 'sentence'], ['this', 'is', 'another', 'one']]
```

##### `POSTagger`

Performs part-of-speech tagging.

**Methods:**

###### `__init__(self)`
Initializes the POS tagger.

**Example:**
```python
from opencog.opencog.nlp.sentiment.basic_sentiment_analysis import POSTagger

tagger = POSTagger()
```

###### `pos_tag(self, sentences)`
Tags sentences with part-of-speech information.

**Parameters:**
- `sentences` (list): List of tokenized sentences

**Returns:**
- List of lists of tagged tokens with form, lemma, and tags

**Example:**
```python
tagged_sentences = tagger.pos_tag(tokenized_sentences)
# Result: [[('this', 'this', ['DT']), ('is', 'be', ['VB']), ...]]
```

##### `DictionaryTagger`

Tags sentences using dictionary-based sentiment analysis.

**Methods:**

###### `__init__(self, dictionary_paths)`
Initializes the dictionary tagger with sentiment dictionaries.

**Parameters:**
- `dictionary_paths` (list): List of paths to YAML sentiment dictionaries

**Example:**
```python
from opencog.opencog.nlp.sentiment.basic_sentiment_analysis import DictionaryTagger

dictionary_paths = ['positive_words.yml', 'negative_words.yml']
tagger = DictionaryTagger(dictionary_paths)
```

###### `tag(self, postagged_sentences)`
Tags sentences with sentiment information.

**Parameters:**
- `postagged_sentences` (list): List of POS-tagged sentences

**Returns:**
- List of sentiment-tagged sentences

**Example:**
```python
sentiment_tagged = tagger.tag(tagged_sentences)
```

###### `tag_sentence(self, sentence, tag_with_lemmas=False)`
Tags a single sentence with sentiment information.

**Parameters:**
- `sentence` (list): POS-tagged sentence
- `tag_with_lemmas` (bool): Whether to use lemmas for tagging

**Returns:**
- Sentiment-tagged sentence

**Example:**
```python
tagged_sentence = tagger.tag_sentence(tagged_sentences[0])
```

#### Functions

##### `value_of(sentiment)`

Converts sentiment tags to numerical values.

**Parameters:**
- `sentiment` (string): Sentiment tag

**Returns:**
- Numerical sentiment value

**Example:**
```python
from opencog.opencog.nlp.sentiment.basic_sentiment_analysis import value_of

value = value_of('positive')  # Returns positive sentiment value
```

##### `sentence_score(sentence_tokens, previous_token, acum_score, neg_num)`

Calculates sentiment score for a sentence.

**Parameters:**
- `sentence_tokens` (list): Tokenized sentence
- `previous_token` (string): Previous token for context
- `acum_score` (float): Accumulated score
- `neg_num` (int): Number of negations

**Returns:**
- Tuple of (score, negations)

**Example:**
```python
from opencog.opencog.nlp.sentiment.basic_sentiment_analysis import sentence_score

score, negations = sentence_score(tokens, prev_token, 0.0, 0)
```

##### `sentiment_score(review)`

Calculates overall sentiment score for a review.

**Parameters:**
- `review` (string): Text to analyze

**Returns:**
- Sentiment score (float)

**Example:**
```python
from opencog.opencog.nlp.sentiment.basic_sentiment_analysis import sentiment_score

score = sentiment_score("I love this product! It's amazing.")
print(f"Sentiment score: {score}")
```

##### `sentiment_parse(plain_text)`

Parses plain text and returns comprehensive sentiment analysis.

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

### Chatbot Module

**Module:** `opencog.opencog.nlp.chatbot.telegram_bot`

**File:** `opencog/opencog/nlp/chatbot/telegram_bot.py`

#### Setup and Configuration

**Constants:**
```python
TOKEN = 'YOUR_TOKEN'  # Telegram bot token
```

#### Functions

##### `start(bot, update)`

Handles the /start command from Telegram.

**Parameters:**
- `bot`: Telegram bot instance
- `update`: Telegram update object

**Example:**
```python
from opencog.opencog.nlp.chatbot.telegram_bot import start

# This function is automatically called by the Telegram bot framework
```

##### `help(bot, update)`

Handles the /help command from Telegram.

**Parameters:**
- `bot`: Telegram bot instance
- `update`: Telegram update object

##### `echo(bot, update)`

Processes user messages and generates responses.

**Parameters:**
- `bot`: Telegram bot instance
- `update`: Telegram update object

**Example:**
```python
from opencog.opencog.nlp.chatbot.telegram_bot import echo

# This function processes incoming messages and generates responses
# using the OpenCog atomspace and NLP components
```

##### `error(bot, update)`

Handles errors in the Telegram bot.

**Parameters:**
- `bot`: Telegram bot instance
- `update`: Telegram update object

##### `main()`

Main function to start the Telegram bot.

**Example:**
```python
from opencog.opencog.nlp.chatbot.telegram_bot import main

if __name__ == '__main__':
    main()
```

### Anaphora Resolution Module

**Module:** `opencog.opencog.nlp.anaphora`

**File:** `opencog/opencog/nlp/anaphora/agents/hobbs.py`

#### Hobbs Algorithm

Provides anaphora resolution using the Hobbs algorithm.

**Example:**
```python
from opencog.opencog.nlp.anaphora.agents.hobbs import HobbsAgent

agent = HobbsAgent()
resolved_text = agent.resolve_anaphora(text)
```

## Machine Learning APIs

### DeSTIN (Deep Spatiotemporal Inference Network)

**Module:** `python-destin/destin`

**File:** `python-destin/destin/__init__.py`

#### Components

##### Network Module
**File:** `python-destin/destin/network.py`

Provides deep spatiotemporal inference network functionality.

**Example:**
```python
import destin
from destin import network

network_instance = network.Network()
# Configure and use the network
```

##### Layer Module
**File:** `python-destin/destin/layer.py`

Implements network layer functionality.

**Example:**
```python
from destin import layer

layer_instance = layer.Layer()
# Configure and use the layer
```

##### Node Module
**File:** `python-destin/destin/node.py`

Implements network node functionality.

**Example:**
```python
from destin import node

node_instance = node.Node()
# Configure and use the node
```

##### Clustering Module
**File:** `python-destin/destin/clustering.py`

Provides clustering algorithms.

**Example:**
```python
from destin import clustering

clustering_instance = clustering.Clustering()
# Configure and use clustering
```

##### Auto Encoder Module
**File:** `python-destin/destin/auto_encoder.py`

Implements auto-encoder functionality.

**Example:**
```python
from destin import auto_encoder

auto_encoder_instance = auto_encoder.AutoEncoder()
# Configure and use auto-encoder
```

## PLN (Probabilistic Logic Networks) APIs

**Module:** `pln/opencog/torchpln/pln`

**File:** `pln/opencog/torchpln/pln/__init__.py`

### Core Components

#### Common Utilities
**File:** `pln/opencog/torchpln/pln/common.py`

##### `TTruthValue`

Represents a truth value in PLN.

**Example:**
```python
from pln.common import TTruthValue

ttv = TTruthValue(0.8, 0.2)  # strength, count
```

##### `get_ttv(atom)`

Gets the truth value of an atom.

**Parameters:**
- `atom`: The atom to get truth value from

**Returns:**
- Truth value object

**Example:**
```python
from pln.common import get_ttv

ttv = get_ttv(atom)
```

##### `set_ttv(atom, ttv)`

Sets the truth value of an atom.

**Parameters:**
- `atom`: The atom to set truth value for
- `ttv`: The truth value to set

**Example:**
```python
from pln.common import set_ttv, TTruthValue

new_ttv = TTruthValue(0.8, 0.2)
set_ttv(atom, new_ttv)
```

#### Rules
**Directory:** `pln/opencog/torchpln/pln/rules/`

Contains various PLN inference rules organized by category:

- **Propositional Rules:** `pln/rules/propositional/`
- **Other rule categories:** Additional rule directories

**Example:**
```python
from pln.rules.propositional import some_rule

# Use specific PLN rules
```

## Utility Functions

### Scripts and Utilities

#### `opencog/scripts/get_python_lib.py`

Utility script for getting Python library information.

#### `opencog/scripts/make_benchmark_graphs.py`

Script for creating benchmark graphs.

#### `cogserver/scripts/get_python_lib.py`

CogServer-specific Python library utility.

## Examples and Best Practices

### Complete Sentiment Analysis Example

```python
from opencog.opencog.nlp.sentiment.basic_sentiment_analysis import (
    Splitter, POSTagger, DictionaryTagger, sentiment_score, sentiment_parse
)

def analyze_sentiment(text):
    """Complete sentiment analysis pipeline"""
    
    # Initialize components
    splitter = Splitter()
    tagger = POSTagger()
    
    # Load sentiment dictionaries
    dictionary_paths = [
        'dictionaries/positive_words.yml',
        'dictionaries/negative_words.yml'
    ]
    dict_tagger = DictionaryTagger(dictionary_paths)
    
    # Process text
    tokenized = splitter.split(text)
    tagged = tagger.pos_tag(tokenized)
    sentiment_tagged = dict_tagger.tag(tagged)
    
    # Get overall score
    score = sentiment_score(text)
    
    # Get detailed analysis
    detailed = sentiment_parse(text)
    
    return {
        'score': score,
        'detailed': detailed,
        'tokenized': tokenized,
        'tagged': tagged,
        'sentiment_tagged': sentiment_tagged
    }

# Usage
text = "I love this product! It's absolutely amazing and wonderful."
result = analyze_sentiment(text)
print(f"Sentiment score: {result['score']}")
print(f"Detailed analysis: {result['detailed']}")
```

### OpenCog AtomSpace Integration Example

```python
from opencog.scheme_wrapper import scheme_eval, scheme_eval_as

def setup_opencog():
    """Setup OpenCog atomspace with all necessary modules"""
    
    # Initialize atomspace
    python_atomspace = AtomSpace()
    
    # Load core modules
    scheme_eval(python_atomspace, "(use-modules (opencog) (opencog exec))")
    atomspace = scheme_eval_as('(cog-atomspace)')
    
    # Load NLP modules
    scheme_eval(atomspace, '(use-modules (opencog nlp))')
    scheme_eval(atomspace, '(use-modules (opencog nlp chatbot))')
    scheme_eval(atomspace, '(use-modules (opencog nlp relex2logic))')
    scheme_eval(atomspace, '(load-r2l-rulebase)')
    
    return atomspace

def create_concept_node(atomspace, name, strength=0.8, count=0.2):
    """Create a concept node in the atomspace"""
    
    scheme_code = f"""
    (ConceptNode "{name}")
    """
    scheme_eval(atomspace, scheme_code)
    
    # Set truth value
    tv_code = f"""
    (cog-set-tv! (ConceptNode "{name}") (SimpleTruthValue {strength} {count}))
    """
    scheme_eval(atomspace, tv_code)

def get_all_concepts(atomspace):
    """Get all concept nodes from the atomspace"""
    
    return scheme_eval_as("(cog-get-atoms 'ConceptNode)")

# Usage
atomspace = setup_opencog()
create_concept_node(atomspace, "TestConcept", 0.9, 0.3)
concepts = get_all_concepts(atomspace)
print(f"Found {len(concepts)} concept nodes")
```

### Telegram Bot Integration Example

```python
from opencog.opencog.nlp.chatbot.telegram_bot import *
from telegram.ext import Updater, CommandHandler, MessageHandler, Filters

def setup_chatbot():
    """Setup the Telegram chatbot with OpenCog integration"""
    
    # Initialize atomspace
    python_atomspace = AtomSpace()
    scheme_eval(python_atomspace, "(use-modules (opencog) (opencog exec))")
    atomspace = scheme_eval_as('(cog-atomspace)')
    
    # Load NLP modules
    scheme_eval(atomspace, '(use-modules (opencog nlp))')
    scheme_eval(atomspace, '(use-modules (opencog nlp chatbot))')
    scheme_eval(atomspace, '(use-modules (opencog nlp relex2logic))')
    scheme_eval(atomspace, '(load-r2l-rulebase)')
    
    # Start cogserver
    scheme_eval(atomspace, '(start-cogserver "../lib/opencog-chatbot.conf")')
    
    return atomspace

def create_bot():
    """Create and configure the Telegram bot"""
    
    updater = Updater(TOKEN)
    dp = updater.dispatcher
    
    # Add handlers
    dp.add_handler(CommandHandler("start", start))
    dp.add_handler(CommandHandler("help", help))
    dp.add_handler(MessageHandler(Filters.text, echo))
    dp.add_error_handler(error)
    
    return updater

# Usage
if __name__ == '__main__':
    atomspace = setup_chatbot()
    updater = create_bot()
    updater.start_polling()
    updater.idle()
```

### DeSTIN Network Example

```python
import destin
from destin import network, layer, node, clustering, auto_encoder

def create_destin_network():
    """Create a DeSTIN network with all components"""
    
    # Create network components
    network_instance = network.Network()
    layer_instance = layer.Layer()
    node_instance = node.Node()
    clustering_instance = clustering.Clustering()
    auto_encoder_instance = auto_encoder.AutoEncoder()
    
    # Configure components (implementation details depend on specific requirements)
    # network_instance.configure(...)
    # layer_instance.configure(...)
    # etc.
    
    return {
        'network': network_instance,
        'layer': layer_instance,
        'node': node_instance,
        'clustering': clustering_instance,
        'auto_encoder': auto_encoder_instance
    }

# Usage
components = create_destin_network()
print("DeSTIN network components created successfully")
```

### PLN Truth Value Example

```python
from pln.common import TTruthValue, get_ttv, set_ttv

def work_with_truth_values(atom):
    """Demonstrate PLN truth value operations"""
    
    # Get current truth value
    current_ttv = get_ttv(atom)
    print(f"Current truth value: {current_ttv}")
    
    # Create new truth value
    new_ttv = TTruthValue(0.8, 0.2)  # strength=0.8, count=0.2
    print(f"New truth value: {new_ttv}")
    
    # Set new truth value
    set_ttv(atom, new_ttv)
    
    # Verify change
    updated_ttv = get_ttv(atom)
    print(f"Updated truth value: {updated_ttv}")
    
    return updated_ttv

# Usage (assuming you have an atom)
# result = work_with_truth_values(some_atom)
```

## Error Handling

### Common Exceptions

```python
try:
    result = scheme_eval(atomspace, scheme_code)
except Exception as e:
    print(f"Scheme evaluation error: {e}")
    # Handle the error appropriately
```

### Sentiment Analysis Error Handling

```python
def safe_sentiment_analysis(text):
    """Safe sentiment analysis with error handling"""
    
    try:
        score = sentiment_score(text)
        return {'success': True, 'score': score}
    except Exception as e:
        return {'success': False, 'error': str(e)}
```

## Performance Considerations

1. **AtomSpace Operations**: Large atomspaces may require significant memory
2. **Scheme Evaluation**: Complex Scheme operations can be computationally expensive
3. **Sentiment Analysis**: Dictionary-based analysis can be slow for large texts
4. **DeSTIN Networks**: May require GPU acceleration for large datasets

## Best Practices

1. **Initialize Components Once**: Reuse initialized components when possible
2. **Error Handling**: Always wrap API calls in try-catch blocks
3. **Resource Management**: Properly close files and connections
4. **Memory Management**: Be mindful of large atomspaces
5. **Testing**: Test all components thoroughly before production use

## Dependencies

### Required Python Packages
- numpy
- pandas
- scikit-learn
- nltk
- yaml
- telegram.ext (for chatbot)
- requests (for REST API)

### Optional Dependencies
- torch (for PLN)
- matplotlib (for visualization)
- seaborn (for plotting)

## Version Compatibility

- Python 3.7+
- OpenCog AtomSpace compatible versions
- NLTK 3.6+
- NumPy 1.19+

## Contributing

When adding new Python APIs:

1. Follow the existing code style
2. Add comprehensive docstrings
3. Include examples in this documentation
4. Add appropriate error handling
5. Test thoroughly before submitting