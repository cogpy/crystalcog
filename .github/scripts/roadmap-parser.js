#!/usr/bin/env node

/**
 * Unified Roadmap Parser for CrystalCog
 * 
 * This module provides a unified parser for roadmap files to eliminate
 * code duplication between generate-next-steps.yml and roadmap-issues.yml.
 * 
 * Supports multiple roadmap formats:
 * - AGENT-ZERO-GENESIS.md (numbered timeline format)
 * - DEVELOPMENT-ROADMAP.md (subsection + numbered items format)
 * 
 * Usage:
 *   const parser = require('./roadmap-parser.js');
 *   const result = parser.parseRoadmap(content);
 */

const fs = require('fs');

/**
 * Parse task items from a section of text
 * Supports multiple formats: checkbox [x]/[ ], checkmark emoji ✅, plain bullets
 * 
 * @param {string} tasksText - The text containing task items
 * @returns {Array} Array of task objects with completed, description, and format properties
 */
function parseTaskItems(tasksText) {
  const tasks = [];
  const seenDescriptions = new Set();
  
  // Standard markdown checkboxes: - [x] or - [ ]
  const checkboxRegex = /^\s*-\s\[([^\]]*)\]\s(.+)$/gm;
  let match;
  while ((match = checkboxRegex.exec(tasksText)) !== null) {
    const [, status, description] = match;
    const trimmedDesc = description.trim();
    if (!seenDescriptions.has(trimmedDesc)) {
      seenDescriptions.add(trimmedDesc);
      tasks.push({
        completed: status.trim().toLowerCase() === 'x',
        description: trimmedDesc,
        format: 'checkbox'
      });
    }
  }
  
  // Checkmark emojis: - ✅
  const checkmarkRegex = /^\s*-\s✅\s(.+)$/gm;
  while ((match = checkmarkRegex.exec(tasksText)) !== null) {
    const [, description] = match;
    const trimmedDesc = description.trim();
    if (!seenDescriptions.has(trimmedDesc)) {
      seenDescriptions.add(trimmedDesc);
      tasks.push({
        completed: true,
        description: trimmedDesc,
        format: 'checkmark'
      });
    }
  }
  
  // Plain bullet points (assumed incomplete, unless they contain completion markers)
  const lines = tasksText.split('\n');
  for (const line of lines) {
    const trimmedLine = line.trim();
    
    // Skip if already processed as checkbox or checkmark
    if (trimmedLine.match(/^\s*-\s\[.*\]/) || trimmedLine.match(/^\s*-\s✅/)) {
      continue;
    }
    
    // Match plain bullet points
    const plainMatch = trimmedLine.match(/^-\s(.+)/);
    if (plainMatch) {
      const [, description] = plainMatch;
      const trimmedDesc = description.trim();
      
      // Skip if it contains completed indicators or was already processed
      if (!trimmedDesc.includes('✅') && 
          !trimmedDesc.includes('[x]') && 
          !seenDescriptions.has(trimmedDesc)) {
        seenDescriptions.add(trimmedDesc);
        tasks.push({
          completed: false,
          description: trimmedDesc,
          format: 'plain'
        });
      }
    }
  }
  
  return tasks;
}

/**
 * Parse direct numbered timeline format (AGENT-ZERO-GENESIS.md style)
 * Format: 1. **Timeline (Duration)**:\n   - [x] Task
 * 
 * @param {string} content - The content to parse
 * @returns {Array} Array of timeline section objects
 */
function parseNumberedTimelineFormat(content) {
  const sections = [];
  const timelineRegex = /(\d+)\.\s\*\*([^*:]+)[^:]*\*\*:\s*\n((?:\s*-\s[^\n]*\n?)*)/g;
  let match;
  
  while ((match = timelineRegex.exec(content)) !== null) {
    const [, number, title, tasksText] = match;
    const tasks = parseTaskItems(tasksText);
    
    if (tasks.length > 0) {
      sections.push({
        number: parseInt(number),
        title: title.trim(),
        tasks: tasks,
        format: 'numbered-timeline'
      });
    }
  }
  
  return sections;
}

/**
 * Parse subsection format (DEVELOPMENT-ROADMAP.md style)
 * Format: ### Section Title\n\n1. **Item Title**\n   - [x] Task
 * 
 * @param {string} content - The content to parse
 * @returns {Array} Array of section objects with nested items
 */
function parseSubsectionFormat(content) {
  const sections = [];
  const subsectionRegex = /### ([^#\n]+)\n\n([\s\S]*?)(?=\n### |\n## |$)/g;
  let match;
  
  while ((match = subsectionRegex.exec(content)) !== null) {
    const [, sectionTitle, sectionContent] = match;
    
    // Skip non-actionable sections
    const skipSections = ['Summary', 'Resources', 'Metrics', 'Workflow', 'Documentation'];
    if (skipSections.some(skip => sectionTitle.includes(skip))) {
      continue;
    }
    
    const items = [];
    const itemRegex = /(\d+)\.\s\*\*([^*]+)\*\*[^\n]*\n((?:\s*-\s[^\n]*\n?)*)/g;
    let itemMatch;
    
    while ((itemMatch = itemRegex.exec(sectionContent)) !== null) {
      const [, itemNumber, itemTitle, tasksText] = itemMatch;
      const tasks = parseTaskItems(tasksText);
      
      if (tasks.length > 0) {
        items.push({
          number: parseInt(itemNumber),
          title: itemTitle.trim(),
          tasks: tasks
        });
      }
    }
    
    if (items.length > 0) {
      sections.push({
        title: sectionTitle.trim(),
        items: items,
        format: 'subsection'
      });
    }
  }
  
  return sections;
}

/**
 * Parse the "Next Steps" or "Next Development Steps" section from roadmap content
 * 
 * @param {string} content - Full roadmap content
 * @returns {Object} Parsed roadmap data with sections, stats, and metadata
 */
function parseRoadmap(content) {
  const result = {
    sections: [],
    stats: {
      totalSections: 0,
      totalTasks: 0,
      completedTasks: 0,
      incompleteTasks: 0,
      formatBreakdown: { checkbox: 0, checkmark: 0, plain: 0 }
    },
    metadata: {
      hasNextSteps: false,
      format: 'unknown',
      errors: []
    }
  };
  
  // Find "Next Steps" or "Next Development Steps" section
  const nextStepsMatch = content.match(/## Next (?:Development )?Steps\n\n([\s\S]*?)(?=\n## |$)/);
  if (!nextStepsMatch) {
    result.metadata.errors.push('No "Next Steps" or "Next Development Steps" section found');
    return result;
  }
  
  result.metadata.hasNextSteps = true;
  const nextStepsContent = nextStepsMatch[1];
  
  // Try subsection format first (DEVELOPMENT-ROADMAP.md style)
  const subsectionSections = parseSubsectionFormat(nextStepsContent);
  
  if (subsectionSections.length > 0) {
    result.metadata.format = 'subsection';
    result.sections = subsectionSections;
    
    // Calculate stats for subsection format
    for (const section of subsectionSections) {
      result.stats.totalSections++;
      for (const item of section.items) {
        for (const task of item.tasks) {
          result.stats.totalTasks++;
          if (task.completed) {
            result.stats.completedTasks++;
          } else {
            result.stats.incompleteTasks++;
          }
          result.stats.formatBreakdown[task.format]++;
        }
      }
    }
  } else {
    // Try numbered timeline format (AGENT-ZERO-GENESIS.md style)
    const timelineSections = parseNumberedTimelineFormat(nextStepsContent);
    
    if (timelineSections.length > 0) {
      result.metadata.format = 'numbered-timeline';
      result.sections = timelineSections;
      
      // Calculate stats for timeline format
      for (const section of timelineSections) {
        result.stats.totalSections++;
        for (const task of section.tasks) {
          result.stats.totalTasks++;
          if (task.completed) {
            result.stats.completedTasks++;
          } else {
            result.stats.incompleteTasks++;
          }
          result.stats.formatBreakdown[task.format]++;
        }
      }
    } else {
      result.metadata.errors.push('Could not parse any sections from Next Steps content');
    }
  }
  
  return result;
}

/**
 * Get all incomplete tasks from a parsed roadmap result
 * 
 * @param {Object} parsedRoadmap - Result from parseRoadmap()
 * @returns {Array} Array of incomplete task objects with section context
 */
function getIncompleteTasks(parsedRoadmap) {
  const incompleteTasks = [];
  
  for (const section of parsedRoadmap.sections) {
    if (parsedRoadmap.metadata.format === 'numbered-timeline') {
      // Direct tasks on the section
      for (const task of section.tasks) {
        if (!task.completed) {
          incompleteTasks.push({
            sectionTitle: section.title,
            sectionNumber: section.number,
            task: task
          });
        }
      }
    } else if (parsedRoadmap.metadata.format === 'subsection') {
      // Tasks nested in items
      for (const item of section.items) {
        for (const task of item.tasks) {
          if (!task.completed) {
            incompleteTasks.push({
              sectionTitle: section.title,
              itemTitle: item.title,
              itemNumber: item.number,
              task: task
            });
          }
        }
      }
    }
  }
  
  return incompleteTasks;
}

/**
 * Generate a label-safe string from a section/timeline title
 * 
 * @param {string} title - Section title to convert
 * @returns {string} Lowercase, hyphenated, label-safe string
 */
function generateLabelFromTitle(title) {
  return title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '');
}

/**
 * Determine priority level based on section title keywords
 * 
 * @param {string} sectionTitle - Section title to analyze
 * @returns {string} Priority level: 'high', 'medium', or 'low'
 */
function getPriorityFromSection(sectionTitle) {
  const title = sectionTitle.toLowerCase();
  
  if (title.includes('immediate') || title.includes('week 1') || title.includes('critical')) {
    return 'high';
  }
  if (title.includes('short-term') || title.includes('month 1') || title.includes('phase 2')) {
    return 'medium';
  }
  if (title.includes('long-term') || title.includes('month 3') || title.includes('future')) {
    return 'low';
  }
  
  return 'medium';
}

/**
 * Extract component tags from a task description
 * 
 * @param {string} description - Task description to analyze
 * @returns {Array} Array of component tag strings
 */
function getComponentTags(description) {
  const tags = [];
  const desc = description.toLowerCase();
  
  const componentKeywords = {
    'cogutil': ['cogutil', 'logger', 'config', 'utility'],
    'atomspace': ['atomspace', 'atom', 'hypergraph', 'node', 'link'],
    'opencog': ['opencog', 'cognitive'],
    'pln': ['pln', 'probabilistic logic', 'reasoning'],
    'ure': ['ure', 'rule engine', 'unified rule'],
    'cogserver': ['cogserver', 'server', 'network api'],
    'moses': ['moses', 'optimization', 'evolutionary'],
    'nlp': ['nlp', 'language', 'parsing', 'grammar'],
    'testing': ['test', 'spec', 'validation'],
    'ci-cd': ['ci', 'cd', 'pipeline', 'workflow', 'build'],
    'documentation': ['doc', 'readme', 'guide']
  };
  
  for (const [tag, keywords] of Object.entries(componentKeywords)) {
    if (keywords.some(keyword => desc.includes(keyword))) {
      tags.push(tag);
    }
  }
  
  return tags;
}

/**
 * Generate a consistent issue title for a task
 * 
 * @param {string} sectionTitle - Section or timeline title
 * @param {string} taskDescription - Task description
 * @returns {string} Formatted issue title
 */
function generateIssueTitle(sectionTitle, taskDescription) {
  return `[${sectionTitle}] ${taskDescription}`;
}

/**
 * Generate a content hash for deduplication purposes
 * 
 * @param {string} sectionTitle - Section title
 * @param {string} taskDescription - Task description
 * @returns {string} Hash string for deduplication
 */
function generateContentHash(sectionTitle, taskDescription) {
  const content = `${sectionTitle.toLowerCase().trim()}|${taskDescription.toLowerCase().trim()}`;
  // Simple hash for deduplication (not cryptographic)
  let hash = 0;
  for (let i = 0; i < content.length; i++) {
    const char = content.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash = hash & hash; // Convert to 32-bit integer
  }
  return `rdmp-${Math.abs(hash).toString(16)}`;
}

/**
 * Parse a roadmap file and return structured results
 * Convenience function that reads a file and parses it
 * 
 * @param {string} filePath - Path to the roadmap file
 * @returns {Object} Parsed roadmap result with file metadata
 */
function parseRoadmapFile(filePath) {
  if (!fs.existsSync(filePath)) {
    return {
      success: false,
      error: `File not found: ${filePath}`,
      filePath: filePath
    };
  }
  
  const content = fs.readFileSync(filePath, 'utf8');
  const parsed = parseRoadmap(content);
  
  return {
    success: true,
    filePath: filePath,
    fileSize: content.length,
    ...parsed
  };
}

// Export functions for use in workflows and scripts
module.exports = {
  parseRoadmap,
  parseRoadmapFile,
  parseTaskItems,
  parseNumberedTimelineFormat,
  parseSubsectionFormat,
  getIncompleteTasks,
  generateLabelFromTitle,
  getPriorityFromSection,
  getComponentTags,
  generateIssueTitle,
  generateContentHash
};

// CLI support for direct execution
if (require.main === module) {
  const args = process.argv.slice(2);
  const filePath = args[0] || process.env.ROADMAP_FILE || 'docs/DEVELOPMENT-ROADMAP.md';
  
  console.log(`Parsing roadmap: ${filePath}`);
  console.log('='.repeat(50));
  
  const result = parseRoadmapFile(filePath);
  
  if (!result.success) {
    console.error(`Error: ${result.error}`);
    process.exit(1);
  }
  
  console.log(`Format detected: ${result.metadata.format}`);
  console.log(`Total sections: ${result.stats.totalSections}`);
  console.log(`Total tasks: ${result.stats.totalTasks}`);
  console.log(`Completed: ${result.stats.completedTasks}`);
  console.log(`Incomplete: ${result.stats.incompleteTasks}`);
  console.log(`Format breakdown: ${JSON.stringify(result.stats.formatBreakdown)}`);
  
  if (result.stats.incompleteTasks > 0) {
    console.log('\nIncomplete tasks:');
    const incomplete = getIncompleteTasks(result);
    incomplete.forEach((item, index) => {
      console.log(`  ${index + 1}. [${item.sectionTitle}] ${item.task.description}`);
    });
  }
}
