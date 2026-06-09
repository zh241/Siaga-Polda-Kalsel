import subprocess

with open('c:/Users/User/siaga-polda-kalsel/app.js', 'r', encoding='utf-8') as f:
    lines = f.readlines()

total = len(lines)
print(f"Total lines: {total}")

# Binary search: find the smallest line range that still triggers the error
lo, hi = 1, total

while lo < hi:
    mid = (lo + hi) // 2
    chunk = ''.join(lines[:mid])
    
    result = subprocess.run(
        ['node', '--input-type=module'],
        input=chunk.encode('utf-8'),
        capture_output=True,
        timeout=10
    )
    
    output = result.stderr.decode()
    has_error = 'SyntaxError' in output
    print(f"  lo={lo} mid={mid} hi={hi} → error={'YES' if has_error else 'NO'}")
    
    if has_error:
        hi = mid
    else:
        lo = mid + 1

print(f"\n>>> Error first appears at line {lo}")
print("Lines around it:")
for i in range(max(0, lo-5), min(total, lo+3)):
    print(f"  {i+1:4d}: {lines[i].rstrip()}")
