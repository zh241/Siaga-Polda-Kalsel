with open('siaga_tracker/lib/main.dart', 'r', encoding='utf-8') as f:
    content = f.read()

lines = content.split('\n')
for i, line in enumerate(lines):
    if 'history' in line.lower() or 'coordinate' in line.lower() or 'koordinat' in line.lower():
        if 'set(' in line or 'push(' in line or 'update(' in line:
            print(f"L{i+1}: {line.strip()}")
