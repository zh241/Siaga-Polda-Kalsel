import re

with open('c:/Users/User/siaga-polda-kalsel/app.js', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Track backtick depth
depth = 0
problems = []
in_template = False

for i, line in enumerate(lines, 1):
    # Simple heuristic: find lines that have backtick INSIDE ${ ... }
    # Look for pattern: backtick after ${ on same line while already inside a template
    stripped = line.strip()
    
    # Count backticks in the line (crude check)
    backtick_count = line.count('`')
    
    if backtick_count > 0:
        # Check if this line has nested template literal patterns
        # Pattern: ${...`...`...} nested ternary with backtick
        nested = re.search(r'\$\{[^}]*`[^`]*`[^}]*\}', line)
        nested2 = re.search(r'\$\{[^}]*`[^`\n]*$', line)  # unclosed nested backtick
        if nested or nested2:
            problems.append((i, line.rstrip()))

print(f"Found {len(problems)} potentially problematic lines:\n")
for lineno, content in problems:
    print(f"Line {lineno}: {content[:120]}")
