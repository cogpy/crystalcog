# PLN Reasoning Module

This document describes the PLN (Probabilistic Logic Networks) reasoning module implemented for the Agent-Zero Genesis cognitive architecture.

## Overview

The PLN reasoning module provides probabilistic logic reasoning capabilities to the Agent-Zero system, enabling sophisticated inference, learning, and meta-cognitive reflection. It integrates seamlessly with the existing cognitive kernel and ECAN attention allocation systems.

## Features

### Core PLN Functionality
- **Backward Chaining**: Goal-driven inference from premises to conclusions
- **Forward Chaining**: Data-driven inference from facts to new knowledge
- **Truth Value Reasoning**: Handles probabilistic truth values with strength and confidence
- **Rule-based Inference**: Includes common PLN rules (modus ponens, deduction, induction, abduction)

### Cognitive Integration
- **Meta-Cognitive Reflection**: PLN-powered self-assessment and adaptation
- **Attention Integration**: Works with ECAN attention allocation
- **Kernel Integration**: Seamlessly integrates with cognitive kernels
- **Knowledge Management**: Efficient storage and retrieval of facts and rules

## Architecture

### Components

1. **PLN Reasoner** (`pln-reasoning.scm`)
   - Core reasoning engine
   - Rule management
   - Knowledge base operations
   - Truth value computations

2. **Meta-Cognition Integration** (`meta-cognition.scm`)
   - Enhanced with real PLN reasoning
   - Meta-cognitive reflection using PLN
   - Cognitive state analysis

3. **Test Suite** (`pln-reasoning-tests.scm`)
   - Comprehensive test coverage
   - Integration tests
   - Validation scripts

## Usage

### Basic PLN Reasoning

```scheme
;; Create a PLN reasoner
(define reasoner (make-pln-reasoner))

;; Add knowledge with truth values (strength . confidence)
(pln-add-knowledge reasoner 'intelligent-agent (cons 0.9 0.85))
(pln-add-knowledge reasoner 'learning-capable (cons 0.8 0.9))

;; Perform backward chaining
(define result (pln-query reasoner 'backward-chain 'intelligent-agent))
```

### Cognitive Integration

```scheme
;; Create cognitive kernel
(define kernel (spawn-cognitive-kernel '(64 32) 0.8))

;; Perform PLN-enhanced meta-cognitive reflection
(define reflection (meta-cognitive-reflection kernel))

;; Access results
(define self-assessment (assoc-ref reflection 'self-assessment))
(define adaptation-suggestions (assoc-ref reflection 'adaptation-suggestions))
```

### AtomSpace Integration

```scheme
;; Create atomspace and add knowledge
(define atomspace (make-atomspace))
(hash-set! atomspace 'concept1 (cons 0.8 0.9))

;; Perform PLN reasoning on atomspace
(define result (pln-backward-chaining atomspace 'concept1))
```

## API Reference

### Core Functions

#### `make-pln-reasoner`
Creates a new PLN reasoner instance with default configuration.

#### `pln-add-knowledge reasoner knowledge-item truth-value`
Adds knowledge to the reasoner's knowledge base.

#### `pln-query reasoner query-type target [options...]`
Performs PLN reasoning with specified query type ('backward-chain or 'forward-chain).

#### `pln-get-strength truth-value`
Extracts strength component from truth value.

#### `pln-get-confidence truth-value`
Extracts confidence component from truth value.

### Cognitive Integration Functions

#### `cognitive-pln-reasoning cognitive-state query`
Performs PLN reasoning on cognitive state for specific query.

#### `meta-pln-inference kernel meta-goals`
Performs meta-level PLN inference about kernel state and goals.

#### `meta-cognitive-reflection kernel`
Enhanced meta-cognitive reflection using PLN reasoning.

## Configuration

### Default PLN Configuration
```scheme
'((max-iterations . 100)
  (confidence-threshold . 0.7)
  (strength-threshold . 0.5)
  (complexity-penalty . 0.1)
  (target-tv-strength . 0.9)
  (target-tv-confidence . 0.9))
```

### Strength formulas in the Crystal engine

`PLN::Formulas` (`src/pln/pln.cr`) holds the strength formulas the Crystal rules use. `s_ab` reads P(B|A) and `s_a` is the term probability P(A).

| Rule | Formula |
|---|---|
| Deduction (A→B, B→C ⊢ A→C) | `s_ab*s_bc + (1 - s_ab)*(s_c - s_b*s_bc)/(1 - s_b)` |
| Inversion (A→B ⊢ B→A) | `s_ab*s_a/s_b` (Bayes) |
| Abduction (A→B, C→B ⊢ A→C) | invert C→B, then deduce through B |
| Induction (A→B, A→C ⊢ B→C) | invert A→B, then deduce through A |
| Modus ponens (A→B, A ⊢ B) | `s_ab*s_a + 0.2*(1 - s_a)` |

- A node has a term probability when its truth value has confidence above zero; its strength is then read as P(node).
- When a node involved has none, deduction uses `s_ab*s_bc`, inversion keeps the strength, and abduction and induction use the odds that the two premises agree.
- `Formulas.consistent?(s_a, s_b, s_ab)` tells whether a conditional probability is possible for the given term probabilities.
- Induction is available as a formula; the stock engine has no induction rule.

### Available PLN Rules
- **Modus Ponens**: If A implies B and A is true, then B is true
- **Deduction**: If A implies B and B implies C, then A implies C
- **Induction**: Generalization from specific instances
- **Abduction**: Inference to the best explanation
- **Similarity**: Symmetric similarity relationships
- **Inheritance**: Transitive inheritance relationships

## Testing

### Run PLN-specific Tests
```bash
# Run comprehensive PLN reasoning tests
./tests/agent-zero/pln-integration-test.sh
```

### Test Coverage
- PLN reasoner creation and configuration
- Knowledge management operations
- Backward and forward chaining
- Cognitive integration
- Meta-cognitive reflection
- Truth value operations
- Error handling

## Examples

See `examples/agent-zero-pln-usage.scm` for comprehensive usage examples including:
- Basic PLN reasoning
- Cognitive integration
- Knowledge-based reasoning
- Multi-kernel attention allocation
- Advanced PLN integration

## Integration with Agent-Zero Genesis

The PLN reasoning module is fully integrated into the Agent-Zero Genesis roadmap:

- ✅ **Implemented**: PLN reasoning module
- 🔄 **Next**: ECAN attention allocation enhancement
- 🔄 **Future**: MOSES optimization framework integration

## Performance Considerations

- Truth value computations are optimized for real-time reasoning
- Knowledge base uses efficient hash table storage
- Rule application is cached for common patterns
- Memory usage is managed through attention-based forgetting

## Future Enhancements

- Integration with external PLN rule bases
- Advanced truth value fusion algorithms
- Distributed PLN reasoning across multiple kernels
- Learning of new PLN rules from experience
- Integration with OpenCog PLN system

## Contributing

When contributing to the PLN reasoning module:

1. Follow existing code patterns and documentation
2. Add comprehensive tests for new functionality
3. Update this README for new features
4. Ensure integration with existing cognitive components
5. Validate with the integration test suite

## References

- [OpenCog PLN Documentation](https://github.com/opencog/pln)
- [Agent-Zero Genesis Roadmap](../AGENT-ZERO-GENESIS.md)
- [Probabilistic Logic Networks Theory](http://wiki.opencog.org/wikihome/index.php/PLN)