"""
Scan app.js untuk menemukan SEMUA nested backtick di dalam template literal.
Cara kerja: track kedalaman template literal dengan stack,
lalu flag setiap backtick yang dibuka di dalam level > 1.
"""

with open('c:/Users/User/siaga-polda-kalsel/app.js', 'r', encoding='utf-8') as f:
    content = f.read()

lines = content.split('\n')

# State machine
i = 0
n = len(content)
depth = 0          # kedalaman template literal
expr_depth = []    # stack: kedalaman { } di dalam template literal
problems = []

while i < n:
    c = content[i]
    
    if c == '`':
        if depth == 0:
            depth = 1
            expr_depth = [0]
        else:
            # Nested backtick
            line_num = content[:i].count('\n') + 1
            col = i - content.rfind('\n', 0, i)
            problems.append((line_num, col, lines[line_num-1].strip()[:100]))
            depth += 1
            expr_depth.append(0)
        i += 1
        continue

    if depth > 0:
        if c == '$' and i+1 < n and content[i+1] == '{':
            expr_depth[-1] += 1
            i += 2
            continue
        if c == '{' and expr_depth[-1] > 0:
            expr_depth[-1] += 1
        elif c == '}' and expr_depth[-1] > 0:
            expr_depth[-1] -= 1
            if expr_depth[-1] == 0:
                pass  # kembali ke dalam template
        elif c == '`' and expr_depth[-1] == 0:
            depth -= 1
            expr_depth.pop()
    
    # Skip string literals di luar template (hindari false positive)
    if depth == 0 and c in ('"', "'"):
        quote = c
        i += 1
        while i < n and content[i] != quote:
            if content[i] == '\\':
                i += 1
            i += 1
    
    i += 1

print(f"Ditemukan {len(problems)} nested backtick:\n")
for lineno, col, ctx in problems:
    print(f"  Line {lineno}, Col {col}: {ctx}")
