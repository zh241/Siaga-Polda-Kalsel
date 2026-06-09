with open('siaga_tracker/lib/main.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

for i in range(2195, min(2235, len(lines))):
    print(f"{i+1}: {lines[i]}", end="")
