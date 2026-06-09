with open('c:/Users/User/siaga-polda-kalsel/app.js', 'r', encoding='utf-8') as f:
    lines = f.readlines()

content = ''.join(lines[:251])

i = 0
template_stack = []  # stack of line numbers where backtick was opened
in_single = False
in_double = False
in_comment_line = False

while i < len(content):
    c = content[i]
    
    if c == '\n':
        in_comment_line = False
        i += 1
        continue
    
    # Skip line comments
    if not in_single and not in_double and i+1 < len(content) and c == '/' and content[i+1] == '/':
        while i < len(content) and content[i] != '\n':
            i += 1
        continue
    
    # Skip block comments
    if not in_single and not in_double and i+1 < len(content) and c == '/' and content[i+1] == '*':
        while i < len(content) - 1:
            if content[i] == '*' and content[i+1] == '/':
                i += 2
                break
            i += 1
        continue
    
    if in_single:
        if c == '\\':
            i += 2
            continue
        if c == "'":
            in_single = False
        i += 1
        continue
    
    if in_double:
        if c == '\\':
            i += 2
            continue
        if c == '"':
            in_double = False
        i += 1
        continue
    
    if len(template_stack) == 0:
        # Not inside template literal
        if c == "'":
            in_single = True
        elif c == '"':
            in_double = True
        elif c == '`':
            line_num = content[:i].count('\n') + 1
            template_stack.append(line_num)
    else:
        # Inside template literal
        if c == '`':
            template_stack.pop()
        elif c == '\\':
            i += 2
            continue
    
    i += 1

if template_stack:
    print(f"UNCLOSED template literal(s) in lines 1-251:")
    for ln in template_stack:
        print(f"  Opened at line {ln}: {lines[ln-1].rstrip()}")
else:
    print("All template literals properly closed in lines 1-251")
    print("\nChecking for unclosed parentheses...")
    
    # Re-check parens
    content2 = ''.join(lines[:251])
    paren_stack = []
    i2 = 0
    line2 = 1
    in_s = in_d = False
    
    while i2 < len(content2):
        c2 = content2[i2]
        if c2 == '\n': line2 += 1; i2 += 1; continue
        if in_s:
            if c2 == '\\': i2 += 2; continue
            if c2 == "'": in_s = False
            i2 += 1; continue
        if in_d:
            if c2 == '\\': i2 += 2; continue
            if c2 == '"': in_d = False
            i2 += 1; continue
        if c2 == "'": in_s = True
        elif c2 == '"': in_d = True
        elif c2 in '({[': paren_stack.append((c2, line2))
        elif c2 == ')':
            if paren_stack and paren_stack[-1][0] == '(': paren_stack.pop()
        elif c2 == '}':
            if paren_stack and paren_stack[-1][0] == '{': paren_stack.pop()
        elif c2 == ']':
            if paren_stack and paren_stack[-1][0] == '[': paren_stack.pop()
        i2 += 1
    
    print(f"Unclosed brackets: {len(paren_stack)}")
    for ch, ln in paren_stack:
        print(f"  '{ch}' at line {ln}: {lines[ln-1].rstrip()[:80]}")
