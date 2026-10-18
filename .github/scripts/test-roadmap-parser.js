#!/usr/bin/env node

/**
 * Test suite for the unified roadmap parser module
 * 
 * This script validates the roadmap parser functionality against
 * the actual roadmap files in the repository.
 * 
 * Usage: node .github/scripts/test-roadmap-parser.js
 */

const fs = require('fs');
const path = require('path');

// Import the parser module
const parser = require('./roadmap-parser.js');

// Colors for output
const colors = {
  green: '\x1b[32m',
  red: '\x1b[31m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  reset: '\x1b[0m',
  bold: '\x1b[1m'
};

function log(color, message) {
  console.log(`${color}${message}${colors.reset}`);
}

let passCount = 0;
let failCount = 0;

function test(name, condition, expected, actual) {
  if (condition) {
    log(colors.green, `✓ ${name}`);
    passCount++;
  } else {
    log(colors.red, `✗ ${name}`);
    log(colors.yellow, `  Expected: ${expected}`);
    log(colors.yellow, `  Actual: ${actual}`);
    failCount++;
  }
}

// Test 1: Parse AGENT-ZERO-GENESIS.md
log(colors.bold + colors.blue, '\n📋 Testing AGENT-ZERO-GENESIS.md parsing...');
const agentZeroResult = parser.parseRoadmapFile('docs/agent-zero/AGENT-ZERO-GENESIS.md');

test(
  'File exists and parses successfully',
  agentZeroResult.success === true,
  'true',
  agentZeroResult.success
);

test(
  'Format detected as numbered-timeline',
  agentZeroResult.metadata?.format === 'numbered-timeline',
  'numbered-timeline',
  agentZeroResult.metadata?.format
);

test(
  'Found 4 timeline sections',
  agentZeroResult.stats?.totalSections === 4,
  4,
  agentZeroResult.stats?.totalSections
);

test(
  'Found 16 total tasks',
  agentZeroResult.stats?.totalTasks === 16,
  16,
  agentZeroResult.stats?.totalTasks
);

test(
  'All 16 tasks are completed',
  agentZeroResult.stats?.completedTasks === 16,
  16,
  agentZeroResult.stats?.completedTasks
);

test(
  'No incomplete tasks',
  agentZeroResult.stats?.incompleteTasks === 0,
  0,
  agentZeroResult.stats?.incompleteTasks
);

// Test 2: Parse DEVELOPMENT-ROADMAP.md
log(colors.bold + colors.blue, '\n📋 Testing DEVELOPMENT-ROADMAP.md parsing...');
const devRoadmapResult = parser.parseRoadmapFile('docs/DEVELOPMENT-ROADMAP.md');

test(
  'File exists and parses successfully',
  devRoadmapResult.success === true,
  'true',
  devRoadmapResult.success
);

test(
  'Format detected as subsection',
  devRoadmapResult.metadata?.format === 'subsection',
  'subsection',
  devRoadmapResult.metadata?.format
);

test(
  'Found at least 1 section',
  devRoadmapResult.stats?.totalSections >= 1,
  '>= 1',
  devRoadmapResult.stats?.totalSections
);

test(
  'Found tasks in roadmap',
  devRoadmapResult.stats?.totalTasks > 0,
  '> 0',
  devRoadmapResult.stats?.totalTasks
);

// Test 3: Helper functions
log(colors.bold + colors.blue, '\n📋 Testing helper functions...');

test(
  'generateLabelFromTitle removes special chars',
  parser.generateLabelFromTitle('Immediate (Week 1-2)') === 'immediate-week-1-2',
  'immediate-week-1-2',
  parser.generateLabelFromTitle('Immediate (Week 1-2)')
);

test(
  'getPriorityFromSection returns high for immediate',
  parser.getPriorityFromSection('Immediate (Week 1-2)') === 'high',
  'high',
  parser.getPriorityFromSection('Immediate (Week 1-2)')
);

test(
  'getPriorityFromSection returns medium for short-term',
  parser.getPriorityFromSection('Short-term (Month 1)') === 'medium',
  'medium',
  parser.getPriorityFromSection('Short-term (Month 1)')
);

test(
  'getPriorityFromSection returns low for long-term',
  parser.getPriorityFromSection('Long-term (Month 3+)') === 'low',
  'low',
  parser.getPriorityFromSection('Long-term (Month 3+)')
);

test(
  'getComponentTags finds atomspace keyword',
  parser.getComponentTags('Implement AtomSpace clustering').includes('atomspace'),
  'true',
  parser.getComponentTags('Implement AtomSpace clustering').includes('atomspace')
);

test(
  'getComponentTags finds multiple keywords',
  parser.getComponentTags('Add PLN reasoning with URE framework').length >= 2,
  '>= 2',
  parser.getComponentTags('Add PLN reasoning with URE framework').length
);

test(
  'generateIssueTitle creates correct format',
  parser.generateIssueTitle('Section', 'Description') === '[Section] Description',
  '[Section] Description',
  parser.generateIssueTitle('Section', 'Description')
);

test(
  'generateContentHash creates consistent hash',
  parser.generateContentHash('Section', 'Task').startsWith('rdmp-'),
  'rdmp-*',
  parser.generateContentHash('Section', 'Task')
);

test(
  'generateContentHash is consistent',
  parser.generateContentHash('Section', 'Task') === parser.generateContentHash('Section', 'Task'),
  'equal hashes',
  parser.generateContentHash('Section', 'Task') === parser.generateContentHash('Section', 'Task') ? 'equal' : 'not equal'
);

// Test 4: getIncompleteTasks
log(colors.bold + colors.blue, '\n📋 Testing getIncompleteTasks...');

const incompleteTasks = parser.getIncompleteTasks(agentZeroResult);
test(
  'No incomplete tasks in AGENT-ZERO-GENESIS.md',
  incompleteTasks.length === 0,
  0,
  incompleteTasks.length
);

// The roadmap's open-task count changes as work lands, so check the parser
// against a fixed document instead of the live file.
const fixtureIncomplete = parser.getIncompleteTasks(
  parser.parseRoadmap('## Next Development Steps\n\n### Phase 1\n\n1. **Core** (Week 1)\n   - [x] Done task\n   - [ ] Open task\n')
);
test(
  'Finds incomplete tasks in a roadmap with open items',
  fixtureIncomplete.length === 1,
  1,
  fixtureIncomplete.length
);

// Test 5: Task parsing
log(colors.bold + colors.blue, '\n📋 Testing task parsing...');

const checkboxTasks = parser.parseTaskItems('- [x] Completed task\n- [ ] Incomplete task');
test(
  'Parses checkbox tasks correctly',
  checkboxTasks.length === 2,
  2,
  checkboxTasks.length
);

test(
  'First checkbox task is completed',
  checkboxTasks[0]?.completed === true,
  'true',
  checkboxTasks[0]?.completed
);

test(
  'Second checkbox task is incomplete',
  checkboxTasks[1]?.completed === false,
  'false',
  checkboxTasks[1]?.completed
);

const checkmarkTasks = parser.parseTaskItems('- ✅ Done with emoji');
test(
  'Parses checkmark emoji tasks',
  checkmarkTasks.length === 1 && checkmarkTasks[0].completed === true,
  '1 completed task',
  `${checkmarkTasks.length} tasks, completed=${checkmarkTasks[0]?.completed}`
);

// Summary
log(colors.bold + colors.blue, '\n========================================');
log(colors.bold, `📊 Test Results: ${passCount} passed, ${failCount} failed`);

if (failCount === 0) {
  log(colors.green, '✅ All tests passed!');
  process.exit(0);
} else {
  log(colors.red, `❌ ${failCount} test(s) failed`);
  process.exit(1);
}
