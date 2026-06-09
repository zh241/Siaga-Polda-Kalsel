import subprocess

with open('c:/Users/User/siaga-polda-kalsel/app.js', 'r', encoding='utf-8') as f:
    lines = f.readlines()

total = len(lines)

# Kita tahu error muncul pertama kali di range 252-1415
# Binary search di range itu
lo, hi = 252, 1415

# Header yang valid (import statements) agar node bisa parse sebagai module
header = ''.join(lines[:251])

while lo < hi:
    mid = (lo + hi) // 2
    chunk = header + ''.join(lines[251:mid])
    
    result = subprocess.run(
        ['node', '--input-type=module'],
        input=chunk.encode('utf-8'),
        capture_output=True,
        timeout=10
    )
    
    output = result.stderr.decode()
    has_error = 'SyntaxError' in output
    print(f"  lo={lo} mid={mid} hi={hi} → {'ERROR' if has_error else 'OK'}")
    
    if has_error:
        hi = mid
    else:
        lo = mid + 1

print(f"\n>>> Error introduced at line {lo}")
print("Context (lines around it):")
for i in range(max(0, lo-8), min(total, lo+3)):
    print(f"  {i+1:4d}: {lines[i].rstrip()}")
