with open('siaga_tracker/lib/main.dart', 'r', encoding='utf-8') as f:
    content = f.read()

lines = content.split('\n')
for i, line in enumerate(lines):
    if '_sessionTrackingPositions' in line:
        print(f"L{i+1}: {line.strip()}")
