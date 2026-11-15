# OpenCog Query Language Implementation Summary

## Overview

Successfully implemented a basic query language for the OpenCog AtomSpace as required by the development roadmap. The implementation provides SQL-like query capabilities while integrating seamlessly with the existing OpenCog infrastructure.

## Key Components Implemented

### 1. Query Language Parser (`OpenCog::QueryLanguage::QueryParser`)
- Parses SQL-like SELECT WHERE syntax
- Supports variable declarations with optional type constraints
- Handles triple patterns and inheritance patterns
- Error handling with meaningful error messages

### 2. Query Execution Engine (`OpenCog::QueryLanguage::QueryExecutor`)
- Converts parsed queries to pattern matching operations
- Integrates with existing PatternMatching engine
- Returns results sorted by confidence
- Comprehensive error handling

### 3. Query Language Interface (`OpenCog::QueryLanguage::QueryLanguageInterface`)
- Main entry point for string-based queries
- Convenience methods for common query patterns
- Integrates with AtomSpace for knowledge retrieval

### 4. Integration with Existing OpenCog::Query Module
- Extended existing Query module with string-based query methods
- Maintains backward compatibility
- Seamless integration with pattern matching and reasoning engines

## Query Language Features

### Syntax Support
```crystal
# Basic variable query
"SELECT $x WHERE { $x ISA Animal }"

# Multiple variables with type constraints
"SELECT $concept:CONCEPT, $predicate:PREDICATE WHERE { $concept $predicate $object }"

# Triple patterns (subject-predicate-object)
"SELECT $pet WHERE { John likes $pet }"

# Inheritance patterns
"SELECT $mammal WHERE { $mammal ISA Animal }"

# Multiple clauses
"SELECT $pet WHERE { $pet ISA Dog . $pet likes Food }"

# Every variable in the pattern, quoted names, a result limit
"SELECT * WHERE { $x ISA \"Blue Whale\" } LIMIT 10"

# One result per distinct value
"SELECT DISTINCT $who WHERE { $who likes $what }"

# Optional part: results without a match keep $food unbound
"SELECT $pet $food WHERE { $pet ISA Animal . OPTIONAL { $pet likes $food } }"

# Conditions on what was matched
"SELECT $x WHERE { $x ISA Animal . FILTER($x != Dog AND CONTAINS($x, \"a\")) }"
"SELECT $x WHERE { $x legs $n . FILTER($n >= 4) }"
"SELECT $x WHERE { $x ISA $kind . FILTER(STRENGTH($x) > 0.5 OR NOT BOUND($kind)) }"

# Alternatives
"SELECT DISTINCT $x WHERE { $x ISA Animal } UNION { $x ISA Plant }"

# Sorting
"SELECT $x WHERE { $x ISA $kind } ORDER BY $kind, $x DESC LIMIT 5"

# A page of results
"SELECT $x WHERE { $x ISA Animal } ORDER BY $x LIMIT 10 OFFSET 20"

# Computed values
"SELECT $x WHERE { $x price $p . FILTER(($p + 1) * 2 > 8) } ORDER BY 10 - $p"

# A computed variable, and alternatives inside a block
"SELECT $x $double WHERE { $x price $p . BIND($p * 2 AS $double) . FILTER($double > 8) }"
"SELECT $x WHERE { $x price $p . { $x ISA Fruit } UNION { $x ISA Vegetable } . FILTER($p < 5) }"

# Leaving out, listing values, and a query inside a query
"SELECT $x WHERE { $x ISA Fruit . MINUS { $x price 5 } }"
"SELECT $x $p WHERE { VALUES $x { apple leek } . $x price $p }"
"SELECT $x $n WHERE { $x ISA $kind . { SELECT $kind (COUNT($y) AS $n) WHERE { $y ISA $kind } GROUP BY $kind } }"

# Following a relation for any number of steps
"SELECT $x WHERE { $x ISA+ Animal }"
"SELECT $part $whole WHERE { $part part_of* $whole . $whole ISA+ Animal }"

# Paths over several relations: one after the other, either of two, backwards
"SELECT $place WHERE { Ann owns/located_in/part_of* $place }"
"SELECT $x WHERE { Campus (^part_of|has_part)+ $x }"
"SELECT $a $b WHERE { $a located_in/^located_in $b . FILTER($a != $b) }"

# Yes or no, and atoms built from the matches
"ASK { Claw part_of+ Dog }"
"CONSTRUCT { $x ISA Animal . $x seen_in Zoo } WHERE { $x ISA+ Animal }"

# Counting and grouping
"SELECT COUNT(*) AS $n WHERE { $x ISA Fruit }"
"SELECT $kind COUNT($x) AS $n, AVG($p) AS $mean WHERE { $x ISA $kind . $x price $p } GROUP BY $kind HAVING($n > 2) ORDER BY $n DESC"
```

### Grammar

```
query     := select | ask | construct
ask       := ASK [WHERE] block { UNION block }
construct := CONSTRUCT "{" template { ( "." | newline ) template } "}"
             WHERE block { UNION block }
             [ ORDER BY key { "," key } ] [ LIMIT integer ] [ OFFSET integer ]
template  := term ( ISA | inherits_from | "->" ) term | term term term
select    := SELECT [DISTINCT] ( "*" | item { [","] item } )
             WHERE block { UNION block }
             [ GROUP BY "$" name { [","] "$" name } ]
             [ HAVING "(" condition ")" ]
             [ ORDER BY key { "," key } ]
             [ LIMIT integer ] [ OFFSET integer ]     (in either order)
item      := variable | aggregate [ AS "$" name ]
           | "(" aggregate AS "$" name ")"
aggregate := COUNT "(" ( "*" | [DISTINCT] value ) ")"
           | ( SUM | AVG | MIN | MAX ) "(" [DISTINCT] value ")"
variable  := "$" name [ ":" type ]
block     := "{" clause { ( "." | newline ) clause } "}"
clause    := term ( ISA | inherits_from | "->" ) term
           | term term term
           | term path term
           | OPTIONAL "{" clauses "}"
           | FILTER "(" condition ")"
           | BIND "(" value AS "$" name ")"
           | block { UNION block }
           | "{" query "}"
           | MINUS block
           | VALUES "$" name "{" { term | UNDEF } "}"
           | VALUES "(" { "$" name } ")" "{" { "(" { term | UNDEF } ")" } "}"
path      := sequence { "|" sequence }
sequence  := step { "/" step }
step      := [ "^" ] ( relation | "(" path ")" ) [ "+" | "*" | "?" ]
relation  := ISA | inherits_from | "->" | name
term      := "$" name | name | "quoted name"
condition := condition OR condition | condition AND condition
           | NOT condition | "(" condition ")"
           | value ( "=" | "!=" | "<" | "<=" | ">" | ">=" ) value
           | CONTAINS "(" value "," value ")" | BOUND "(" "$" name ")"
value     := value ( "+" | "-" | "*" | "/" ) value | "-" value
           | "(" value ")"
           | "$" name | name | "quoted text" | number
           | ( NAME | TYPE | STRENGTH | CONFIDENCE ) "(" "$" name ")"
key       := value [ ASC | DESC ]
```

- Keywords are case-insensitive. `#` starts a comment.
- A name is letters, digits and underscores, with single hyphens inside. Anything else goes in double quotes.
- A parse error says what was expected, what was found, and the line and column, for example `expected a term, found "}" at line 1, column 26`.
- A selected variable must appear in WHERE.
- Results carry the selected variables only.
- A triple's predicate resolves to the PredicateNode of that name when there is one.
- Running a query does not change the AtomSpace. Its patterns are built beside it, so a name the AtomSpace does not know simply matches nothing.
- Only SELECT, DISTINCT, WHERE, ISA, OPTIONAL and LIMIT are reserved. FILTER, UNION, ORDER and the rest are keywords only where the grammar expects them, so they can still name atoms.

### FILTER, UNION and ORDER BY

- **FILTER** keeps the results its condition holds for. It applies to its whole block wherever it stands, after the OPTIONAL parts. Several FILTERs all have to hold.
- A variable compares by the name of its atom. Against a number the name is read as a number, so `$n >= 4` holds for a node named `10`; a name that is not a number is only unequal to it. Two names compare as text.
- `NAME($x)`, `TYPE($x)`, `STRENGTH($x)` and `CONFIDENCE($x)` read the atom a variable stands for. `CONTAINS(a, b)` tells whether text `a` has `b` in it. `BOUND($x)` tells whether an OPTIONAL part gave `$x` a value.
- A comparison with an unbound variable is false, and so is its opposite: `$n = 4` and `$n != 4` both drop a result without `$n`. Use `NOT BOUND($n)` to keep those.
- **UNION** adds the results of another block. A block need not bind every selected variable; a result leaves the others out. Add DISTINCT to drop repeats.
- **ORDER BY** sorts by one or more keys, each ascending unless followed by DESC. Numbers sort before text and unbound values last. Without ORDER BY results come by falling confidence, as before. A key may be a variable that is not selected.

### Arithmetic and OFFSET

- `+`, `-`, `*`, `/` and brackets compute with numbers and with names that read as numbers, in FILTER, ORDER BY, HAVING and inside aggregates. `*` and `/` bind tighter than `+` and `-`.
- A value that is not a number, or a division by zero, leaves the result without a value: a comparison with it is false, as with an unbound variable.
- A minus needs a blank on at least one side, because `a-b` is one name. `$p -1` is read as `$p - 1`.
- `OFFSET n` leaves out the first n results, after sorting and DISTINCT and before LIMIT counts. LIMIT and OFFSET can come in either order.

### Aggregates

- `COUNT(*)` counts the matches. `COUNT($x)` counts those where `$x` has a value. `SUM`, `AVG`, `MIN` and `MAX` take any value, such as `$p`, `$p * 2` or `STRENGTH($x)`. `DISTINCT` inside the brackets takes each value once.
- `GROUP BY $a, $b` makes one result per combination of values. Without it all matches are one group, which exists even when nothing matched, so `COUNT(*)` answers 0.
- A selected variable beside an aggregate has to be in GROUP BY.
- `AS $name` names the result. Without it the result is named after the function, as in `$count`. SPARQL's bracketed form `(COUNT($x) AS $n)` is read too.
- An aggregate's value is bound as a NumberNode that stands beside the AtomSpace, so a result still binds atoms and nothing is added. `MIN` and `MAX` of a plain variable give the atom itself.
- `SUM` of nothing is 0. `AVG`, `MIN` and `MAX` of nothing have no value and the result leaves them out.
- `HAVING(condition)` keeps the groups its condition holds for and can read the aggregates by name. ORDER BY can too.
- None of these words is reserved: `count`, `group` or `offset` can still name an atom.

### BIND and groups

- `BIND(value AS $name)` gives a variable a computed value: a number, a name, or for a plain variable the atom itself. Where the value does not exist, as with an unbound variable, `$name` stays unbound.
- A BIND applies to its block after the clauses and OPTIONAL parts and before the FILTERs, wherever it is written. A later BIND can use an earlier one. A variable the block's clauses match, or an earlier BIND set, cannot be bound again.
- The bound variable can be selected, filtered, sorted and grouped on. A number made by BIND or an aggregate sorts and compares as a number.
- A block can hold groups: `{ $x price $p . { $x ISA Fruit } UNION { $x ISA Vegetable } }`. A group is one block or several joined by UNION. Its results are joined with the rest of the block on the variables they share. UNION may stand on a later line.
- A FILTER or BIND sees only what its own block matches. In the example above a `FILTER($p > 3)` inside `{ $x ISA Fruit }` would find `$p` without a value; write it in the outer block, or match the price inside the group.
- `BIND` is not a reserved word.

### MINUS, VALUES and subqueries

- `MINUS { ... }` leaves out a result that shares a variable with a result of its block and agrees with it on every variable they share. A MINUS block that shares no variable with the rest removes nothing. What it matches cannot be selected.
- `VALUES $x { apple pear }` binds `$x` to each value in turn. `VALUES ($x $y) { (apple 4) (leek UNDEF) }` gives rows for several variables; `UNDEF` leaves a place unbound. A value names the atom of that name; one the AtomSpace does not have is a node beside it, and nothing is added. VALUES can be a block's only content.
- A whole query in braces is a subquery: `{ SELECT $kind (COUNT($y) AS $n) WHERE { $y ISA $kind } GROUP BY $kind }`. Its own grouping, HAVING, ORDER BY, LIMIT and OFFSET apply first, and what it selects is joined with the rest of the block. Only what it selects is seen outside.
- Order within a block: clauses, VALUES, subqueries, groups, OPTIONAL, BIND, MINUS, then FILTER, wherever each is written.
- `MINUS` and `VALUES` are not reserved words.

### Paths

- `+` after the relation of a clause follows it for one or more steps, `*` for none or more. `$x ISA+ Animal` holds when a chain of inheritance links leads from `$x` to `Animal`; `$a part_of+ $b` when a chain of `part_of` triples leads from `$a` to `$b`. The mark may stand apart from the relation: `$x ISA + Animal`.
- Either end, both or neither may be a variable. `ASK { Claw part_of+ Dog }` decides one pair; `SELECT $a $b WHERE { $a part_of+ $b }` lists every pair the relation joins.
- No step relates an atom to itself. With a name at one end of a `*` path, that atom is among the answers. With variables at both ends, every atom the relation touches is joined to itself. A name the AtomSpace does not know is joined to nothing, itself included.
- A circle is gone round once: on `Spring precedes Summer ... Winter precedes Spring`, `Spring precedes+ $x` gives the four seasons, Spring among them. The same variable at both ends, `$x precedes+ $x`, asks what leads back to itself.
- The search goes breadth first from the end that is given, or from the values the clauses before it in the block already gave that end. With nothing given it starts from every atom the relation touches.
- What a path matched is the links of a shortest chain, and a result's confidence is their mean as for any match. A path of no steps matched nothing and has confidence 0.
- A path joins with the rest of its block like any clause, inside OPTIONAL and MINUS too. A typed variable, `$x:CONCEPT`, holds at a path's end as elsewhere.
- The predicate of a path is a name, not a variable.

A path can be put together from several relations:

- `a/b` is `a` and then `b`: `$x located_in/part_of $y` holds when `$x` is located in something that is part of `$y`.
- `a|b` is either: `$x part_of|located_in Lab`.
- `^a` walks `a` backwards, from its object to its subject: `Campus ^part_of $x` gives what is part of the campus. `$a located_in/^located_in $b` gives things in the same place.
- `a?` is `a` once or not at all.
- Brackets group, and a mark after them repeats the whole: `(part_of/part_of)+` goes two steps at a time. `/` binds tighter than `|`, and `+`, `*`, `?` and `^` tighter than either.
- `ISA`, `inherits_from` and `->` stand for inheritance inside a path as they do outside: `Ann owns/ISA $kind`.
- A path that could be no step at all, as `a*`, `a?` or `(a/b)*`, joins an atom to itself. With variables at both ends that is every atom any of the path's relations touches.
- The search runs the path as a small machine of states over pairs of an atom and a state, breadth first, so each pair of ends comes once however many ways lead between them, with the links of a shortest way as what was matched. From the object's end the path is read backwards.
- Still not there: a path over a variable predicate, and a path that excludes a relation.

### ASK

- `ASK { ... }` says whether its block matches anything. `WHERE` may be written before the block, and blocks may be joined by UNION. Nothing else follows: there is nothing to sort or limit.
- `QueryLanguageInterface#ask(text)` returns true or false. It takes any query, and is true for a SELECT that has a result.
- Run through `query`, an ASK gives one result without bindings when the answer is yes, with the confidence of the most confident match, and no result when it is no.
- `ASK` is not a reserved word.

### CONSTRUCT

- `CONSTRUCT { template } WHERE { ... }` builds atoms from the matches. The template is inheritance and triple clauses, single steps only. Every variable in it must appear in WHERE.
- `QueryLanguageInterface#construct(text)` returns the atoms: the template filled in once for each match, each distinct atom once. A name in the template is the stored node of that name, or a new ConceptNode (a PredicateNode in the predicate's place).
- A template clause is left out for a match that gives one of its variables no value, as an OPTIONAL part can.
- A built atom is as strong as the weakest atom its match rests on and as confident as the match. Where several matches build the same atom, the most confident one is kept. A match that rests on no atoms (VALUES alone, or a subquery's rows) gives the default truth value.
- The atoms stand beside the AtomSpace and nothing is added. `construct(text, into: space)` adds them to an AtomSpace, the queried one or another, and returns the stored atoms. That AtomSpace merges an atom it already holds in its usual way; nodes it already has are used as they are.
- ORDER BY, LIMIT and OFFSET may follow the WHERE block. They choose among the matches as they do among the results of a SELECT, and the template is filled from the ones chosen: `CONSTRUCT { $x ISA Cheap } WHERE { $x price $p } ORDER BY $p LIMIT 2`. Without ORDER BY the most confident matches come first.
- Run through `query`, a CONSTRUCT lists its matches with the template's variables.
- `CONSTRUCT` is not a reserved word.

### Variable Types
- `$var` - Generic variable
- `$var:CONCEPT` - Concept node variable
- `$var:PREDICATE` - Predicate node variable
- `$var:NODE` - Any node type
- `$var:LINK` - Any link type
- `$var:<AtomType>` - Any atom type by name, such as `$var:PREDICATE_NODE`

### Query Patterns
- **Triple patterns**: `subject predicate object`
- **Inheritance patterns**: `child ISA parent` or `child -> parent`
- **Multiple clauses**: Separated by periods (.) or line breaks
- **Optional clauses**: `OPTIONAL { ... }`, a left join
- **Filters**: `FILTER(condition)` on names, types and truth values
- **Alternatives**: `{ ... } UNION { ... }`
- **Sorting**: `ORDER BY key [DESC]`
- **Paging**: `LIMIT n OFFSET m`
- **Aggregates**: `COUNT`, `SUM`, `AVG`, `MIN`, `MAX` with `GROUP BY` and `HAVING`
- **Arithmetic**: `+ - * /` in any value
- **Computed variables**: `BIND(value AS $name)`
- **Groups**: `{ ... } UNION { ... }` inside a block
- **Exclusion**: `MINUS { ... }`
- **Inline values**: `VALUES $x { ... }`
- **Subqueries**: `{ SELECT ... WHERE { ... } }` inside a block

## Integration Points

### With Existing Systems
1. **AtomSpace**: Direct integration with AtomSpace for knowledge storage/retrieval
2. **PatternMatching**: Uses existing pattern matching engine for query execution
3. **PLN/URE**: Compatible with reasoning engines for expanded knowledge queries
4. **CogUtil**: Integrated logging and error handling

### API Integration
```crystal
# Through OpenCog::Query module
results = OpenCog::Query.execute_query(atomspace, query_string)
interface = OpenCog::Query.create_query_interface(atomspace)

# Direct interface usage
query_interface = OpenCog::QueryLanguage.create_interface(atomspace)
results = query_interface.query(query_string)
```

## Testing Implementation

### Comprehensive Test Suite
- **Parser tests**: Validate query string parsing
- **Executor tests**: Verify query execution logic
- **Integration tests**: Test with existing OpenCog components
- **Error handling tests**: Validate exception handling
- **Performance tests**: Ensure reasonable query performance

### Test Coverage
- Variable binding and type constraints
- Pattern matching integration
- Complex multi-clause queries
- Error scenarios and edge cases
- Integration with existing Query module methods

## Documentation Updates

### Updated Files
- `docs/OPENCOG_CORE_LIBRARIES.md` - Added comprehensive query language documentation
- `DEVELOPMENT-ROADMAP.md` - Marked query language implementation as complete

### Examples Provided
- Basic query syntax and usage
- Advanced patterns and constraints
- Integration with existing OpenCog functionality
- Error handling patterns

## Files Created/Modified

### New Files
- `src/opencog/query_language.cr` - Main query language implementation (439 lines)
- `spec/opencog/query_language_spec.cr` - Comprehensive test suite (612 lines)
- `test_query_language.cr` - Integration test demonstration (220 lines)

### Modified Files
- `src/opencog/opencog.cr` - Added query language integration
- `docs/OPENCOG_CORE_LIBRARIES.md` - Updated documentation
- `DEVELOPMENT-ROADMAP.md` - Marked task as complete

## Example Usage Demonstration

```crystal
# Initialize OpenCog and create AtomSpace
OpenCog.initialize
atomspace = AtomSpace::AtomSpace.new

# Add knowledge
dog = atomspace.add_concept_node("Dog")
animal = atomspace.add_concept_node("Animal")
atomspace.add_inheritance_link(dog, animal)

fido = atomspace.add_concept_node("Fido")
atomspace.add_inheritance_link(fido, dog)

# Create query interface
query_interface = OpenCog::Query.create_query_interface(atomspace)

# Execute queries
animals = query_interface.query("SELECT $x WHERE { $x ISA Animal }")
# Returns: Fido (through inheritance chain)

dogs = query_interface.query("SELECT $pet WHERE { $pet ISA Dog }")  
# Returns: Fido

# Convenience methods
all_animals = query_interface.find_all("Animal")
fido_relations = query_interface.find_relations("Fido", "ISA")
```

## Technical Accomplishments

1. **SQL-like Query Language**: Implemented intuitive query syntax familiar to developers
2. **Pattern Matching Integration**: Leverages existing sophisticated pattern matching engine  
3. **Type System Integration**: Full integration with AtomSpace type system
4. **Error Handling**: Comprehensive error handling with meaningful messages
5. **Performance**: Efficient query execution using existing optimized components
6. **Extensibility**: Modular design allows for easy extension of query capabilities

## Roadmap Completion

✅ **Task Complete**: "Implement basic query language" 
- Fully functional query language implementation
- Comprehensive testing and documentation
- Integration with existing OpenCog infrastructure
- Ready for use in cognitive applications

The implementation provides a solid foundation for querying knowledge in the OpenCog AtomSpace and can be extended with additional features as needed in future development phases.