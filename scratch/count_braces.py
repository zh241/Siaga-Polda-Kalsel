"""
Hitung balance {} di dalam blok onValue(refTracking, ...)
untuk menemukan brace yang tidak seimbang.
"""

with open('c:/Users/User/siaga-polda-kalsel/app.js', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Mulai dari baris onValue(refTracking
start_line = None
for i, l in enumerate(lines):
    if 'onValue(refTracking' in l:
        start_line = i
        print(f"Found onValue(refTracking at line {i+1}")

if start_line is None:
    print("Not found!")
    exit()

# Hitung depth dari baris start sampai ketemu penutup
depth = 0
in_str_s = in_str_d = in_template = False
result_line = None

for i in range(start_line, min(start_line + 200, len(lines))):
    line = lines[i]
    for j, c in enumerate(line):
        if in_str_s:
            if c == '\\': continue
            if c == "'": in_str_s = False
            continue
        if in_str_d:
            if c == '\\': continue
            if c == '"': in_str_d = False
            continue
        if in_template:
            if c == '`': in_template = False
            continue
        
        if c == "'": in_str_s = True
        elif c == '"': in_str_d = True
        elif c == '`': in_template = True
        elif c == '{': depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                result_line = i + 1
                print(f"Block closes at line {result_line}: {line.rstrip()}")
                print(f"\nLines around close:")
                for k in range(max(0, i-5), min(len(lines), i+3)):
                    print(f"  {k+1:4d}: {lines[k].rstrip()}")
                break
    
    if result_line:
        break
    
    if i < start_line + 5 or (i - start_line) % 50 == 0:
        print(f"  Line {i+1}, depth={depth}")
