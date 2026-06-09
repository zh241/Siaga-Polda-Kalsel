with open('c:/Users/User/siaga-polda-kalsel/app.js', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Check first 252 lines only
content = ''.join(lines[:252])

stack = []  # (char, line_number)
in_str_single = False
in_str_double = False
in_template = 0  # depth
i = 0
line = 1

while i < len(content):
    c = content[i]
    
    if c == '\n':
        line += 1
        i += 1
        continue
    
    # Track strings to avoid counting brackets inside strings
    if not in_str_single and not in_str_double and in_template == 0:
        if c == "'":
            in_str_single = True
            i += 1
            continue
        if c == '"':
            in_str_double = True
            i += 1
            continue
    
    if in_str_single:
        if c == '\\':
            i += 2
            continue
        if c == "'":
            in_str_single = False
        i += 1
        continue
    
    if in_str_double:
        if c == '\\':
            i += 2
            continue
        if c == '"':
            in_str_double = False
        i += 1
        continue
    
    # Track parentheses/braces
    if c in ('(', '{', '['):
        stack.append((c, line))
    elif c == ')':
        if stack and stack[-1][0] == '(':
            stack.pop()
        else:
            print(f"UNMATCHED ) at line {line}")
    elif c == '}':
        if stack and stack[-1][0] == '{':
            stack.pop()
        else:
            print(f"UNMATCHED }} at line {line}")
    elif c == ']':
        if stack and stack[-1][0] == '[':
            stack.pop()
        else:
            print(f"UNMATCHED ] at line {line}")
    
    i += 1

print(f"\nUnclosed brackets in first 252 lines:")
for char, lineno in stack[-20:]:  # show last 20 unclosed
    print(f"  '{char}' opened at line {lineno}")
print(f"Total unclosed: {len(stack)}")
