#!/usr/bin/env crystal run

# Demo: Advanced Pattern Matching for Agent-Zero Genesis
# This demonstration showcases the key advanced pattern matching features
# implemented as part of the Month 3+ roadmap goals

require "../../src/pattern_matching/pattern_matching_main"

puts "🧠 Agent-Zero Genesis: Advanced Pattern Matching Demo"
puts "=" * 55
puts

# Create a knowledge base representing an AI research lab
puts "📚 Creating Knowledge Base: AI Research Lab"
atomspace = AtomSpace::AtomSpace.new

# Research areas
ai = atomspace.add_concept_node("artificial_intelligence")
ml = atomspace.add_concept_node("machine_learning")
nlp = atomspace.add_concept_node("natural_language_processing")
cv = atomspace.add_concept_node("computer_vision")
robotics = atomspace.add_concept_node("robotics")

# Researchers
alice = atomspace.add_concept_node("alice")
bob = atomspace.add_concept_node("bob")
carol = atomspace.add_concept_node("carol")

# Create specialization hierarchy
atomspace.add_inheritance_link(ml, ai)
atomspace.add_inheritance_link(nlp, ai)
atomspace.add_inheritance_link(cv, ai)
atomspace.add_inheritance_link(robotics, ai)

# Research relationships
works_on = atomspace.add_predicate_node("works_on")
collaborates = atomspace.add_predicate_node("collaborates_with")
publishes = atomspace.add_predicate_node("publishes_in")

# Add research activities
atomspace.add_evaluation_link(works_on, atomspace.add_list_link([alice, ml]))
atomspace.add_evaluation_link(works_on, atomspace.add_list_link([bob, nlp]))
atomspace.add_evaluation_link(works_on, atomspace.add_list_link([carol, cv]))

atomspace.add_evaluation_link(collaborates, atomspace.add_list_link([alice, bob]))
atomspace.add_evaluation_link(collaborates, atomspace.add_list_link([bob, carol]))

puts "  ✓ Created #{atomspace.size} atoms representing research knowledge"
puts "  ✓ Includes: research areas, researchers, and relationships"
puts

# 1. Recursive Query Composition Demo
puts "🔄 Feature 1: Recursive Query Composition"
puts "-" * 40

composer = PatternMatching::Advanced::RecursiveQueryComposer.new(atomspace)

# Register base patterns
var_x = AtomSpace::VariableNode.new("$X")
var_y = AtomSpace::VariableNode.new("$Y")

# Pattern: X is an AI subfield
ai_pattern = AtomSpace::InheritanceLink.new(var_x, ai)
composer.register_pattern("ai_field", ai_pattern)

# Pattern: X works on Y
works_pattern = AtomSpace::EvaluationLink.new(works_on, 
  AtomSpace::ListLink.new([var_x, var_y].map(&.as(AtomSpace::Atom))))
composer.register_pattern("works_on_field", works_pattern)

# Compose: Find researchers working on AI fields
puts "Query: Who works on AI subfields?"
and_results = composer.compose_and(["works_on_field", "ai_field"])
puts "  Found #{and_results.size} researcher-field combinations"

# Demonstrate OR composition
ml_pattern = AtomSpace::InheritanceLink.new(var_x, ml)
nlp_pattern = AtomSpace::InheritanceLink.new(var_x, nlp)
composer.register_pattern("ml_field", ml_pattern)
composer.register_pattern("nlp_field", nlp_pattern)

or_results = composer.compose_or(["ml_field", "nlp_field"])
puts "  Found #{or_results.size} ML or NLP related items"

puts "  ✓ Recursive composition enables complex multi-step reasoning"
puts

# 2. Pattern Learning Demo  
puts "🎓 Feature 2: Automatic Pattern Learning"
puts "-" * 40

learner = PatternMatching::Advanced::PatternLearner.new(atomspace, 0.05, 0.6)

puts "Learning patterns from research lab knowledge..."
learned_patterns = learner.learn_patterns

puts "  Discovered Patterns:"
learned_patterns.each_with_index do |pattern, i|
  puts "    Pattern #{i+1}: frequency=#{pattern.frequency.round(3)}, " \
       "confidence=#{pattern.confidence.round(3)}, " \
       "strength=#{pattern.strength.round(3)}"
end

# Apply learned patterns
learned_results = learner.apply_learned_patterns
puts "  ✓ Applied learned patterns: #{learned_results.size} new inferences"

stats = learner.pattern_statistics
puts "  ✓ Learning efficiency: #{stats["average_strength"]?.try(&.round(3)) || "N/A"} average strength"
puts

# 3. Statistical Pattern Matching Demo
puts "📊 Feature 3: Statistical & Probabilistic Matching"
puts "-" * 45

statistical_matcher = PatternMatching::Advanced::StatisticalMatcher.new(atomspace, 0.5)

# Create a pattern to match probabilistically
research_pattern = PatternMatching::Pattern.new(ai_pattern)

puts "Probabilistic matching for AI research patterns..."
prob_results = statistical_matcher.probabilistic_match(research_pattern)

if prob_results.empty?
  # Demonstrate fuzzy matching instead
  puts "  Using fuzzy matching for pattern discovery..."
  fuzzy_results = statistical_matcher.fuzzy_match(research_pattern, 0.6)
  
  puts "  Fuzzy Match Results:"
  fuzzy_results.first(3).each_with_index do |match, i|
    puts "    Match #{i+1}: probability=#{match.probability.round(3)}, " \
         "significant=#{match.is_significant?}"
  end
else
  puts "  Probabilistic Results:"
  prob_results.each_with_index do |match, i|
    puts "    Match #{i+1}: probability=#{match.probability.round(3)}"
  end
end

# Demonstrate Bayesian inference
puts "\nBayesian Inference: P(works_on_AI | is_researcher)"
evidence_patterns = [PatternMatching::Pattern.new(works_pattern)]
hypothesis_pattern = PatternMatching::Pattern.new(ai_pattern)

bayesian_result = statistical_matcher.bayesian_inference(evidence_patterns, hypothesis_pattern)
if bayesian_result
  puts "  Posterior probability: #{bayesian_result.probability.round(3)}"
  puts "  ✓ Bayesian inference suggests researchers likely work on AI"
else
  puts "  ✓ Insufficient evidence for Bayesian inference"
end

puts

# 4. Temporal Pattern Matching Demo
puts "⏰ Feature 4: Temporal Pattern Analysis"
puts "-" * 40

temporal_matcher = PatternMatching::Advanced::TemporalPatternMatcher.new(atomspace, 10000_i64)

# Create temporal sequence: research -> collaboration -> publication
research_seq = [
  PatternMatching::Pattern.new(works_pattern),
  PatternMatching::Pattern.new(AtomSpace::EvaluationLink.new(collaborates, 
    AtomSpace::ListLink.new([var_x, var_y].map(&.as(AtomSpace::Atom))))),
  PatternMatching::Pattern.new(ai_pattern)
]

puts "Analyzing temporal research workflow patterns..."
temporal_matches = temporal_matcher.match_sequence(research_seq, "research_workflow")

puts "  Temporal Sequences Found: #{temporal_matches.size}"
temporal_matches.each_with_index do |match, i|
  puts "    Sequence #{i+1}: duration=#{match.duration_ms}ms, " \
       "patterns=#{match.pattern_results.size}"
end

# Detect repeating patterns
repeating_matches = temporal_matcher.detect_repeating_patterns(
  PatternMatching::Pattern.new(works_pattern), 2)
puts "  ✓ Found #{repeating_matches.size} repeating research patterns"
puts

# 5. Advanced Pattern Builder Demo
puts "🏗️  Feature 5: Unified Advanced Pattern Builder"
puts "-" * 45

builder = PatternMatching::AdvancedPatternBuilder.new(atomspace)

# Register patterns for unified access
builder.register_pattern("researchers", works_pattern)
builder.register_pattern("ai_areas", ai_pattern)
builder.register_pattern("collaborations", AtomSpace::EvaluationLink.new(collaborates,
  AtomSpace::ListLink.new([var_x, var_y].map(&.as(AtomSpace::Atom)))))

puts "Unified pattern operations:"

# Composition
unified_and = builder.and_patterns(["researchers", "ai_areas"])
puts "  AND composition: #{unified_and.size} results"

# Learning
unified_learned = builder.learn_patterns
puts "  Pattern learning: #{unified_learned.size} patterns discovered"

# Statistical analysis
unified_fuzzy = builder.fuzzy_match(research_pattern, 0.7)
puts "  Fuzzy matching: #{unified_fuzzy.size} matches"

puts "  ✓ Unified interface provides seamless access to all features"
puts

# Performance Summary
puts "⚡ Performance Summary"
puts "-" * 20

start_time = Time.monotonic

# Add more data for performance testing
(1..20).each do |i|
  topic = atomspace.add_concept_node("topic_#{i}")
  atomspace.add_inheritance_link(topic, ai)
end

perf_time = Time.monotonic
load_time = (perf_time - start_time).total_milliseconds

# Test composition performance
comp_start = Time.monotonic
perf_results = builder.and_patterns(["researchers", "ai_areas"])
comp_time = (Time.monotonic - comp_start).total_milliseconds

# Test learning performance
learn_start = Time.monotonic
perf_learned = builder.learn_patterns
learn_time = (Time.monotonic - learn_start).total_milliseconds

total_atoms = atomspace.size
total_time = (Time.monotonic - start_time).total_milliseconds

puts "  Dataset: #{total_atoms} atoms loaded in #{load_time.round(1)}ms"
puts "  Composition: #{perf_results.size} results in #{comp_time.round(1)}ms"
puts "  Learning: #{perf_learned.size} patterns in #{learn_time.round(1)}ms"
puts "  Total runtime: #{total_time.round(1)}ms"
puts

# Conclusion
puts "🎯 Agent-Zero Genesis: Advanced Pattern Matching Complete!"
puts "=" * 55
puts "✅ Recursive Query Composition - Enables complex multi-step reasoning"
puts "✅ Automatic Pattern Learning - Discovers knowledge patterns autonomously"  
puts "✅ Statistical Matching - Provides probabilistic and fuzzy reasoning"
puts "✅ Temporal Analysis - Understands patterns across time"
puts "✅ Unified Interface - Seamless integration of all advanced features"
puts
puts "🚀 These capabilities enable sophisticated cognitive reasoning for Agent-Zero"
puts "   Genesis systems, supporting autonomous knowledge discovery and inference."
puts
puts "📋 Roadmap Status: Month 3+ Advanced Pattern Matching ✅ COMPLETE"