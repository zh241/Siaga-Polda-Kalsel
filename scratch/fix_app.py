"""
Fix semua nested backtick di app.js sekaligus.
Strategi: baca file, temukan semua pola bermasalah, ganti dengan string concatenation.
"""
import subprocess, re

with open('c:/Users/User/siaga-polda-kalsel/app.js', 'r', encoding='utf-8') as f:
    content = f.read()

original_size = len(content)

# ─────────────────────────────────────────────────────────────────
# FIX 1: showActiveUnitsBottomSheet — popup dengan nested backtick
# Cari pola: no_hp ? ` ... ` : `...`  di dalam template literal besar
# ─────────────────────────────────────────────────────────────────

# Temukan semua backtick ternary: ...? `...` : `...` atau ...? `...` : ''
# yang ada di dalam innerHTML += ` ... `

# Gunakan pendekatan: cari substring exact dan replace

# FIX showActiveUnitsBottomSheet popup WA button
old1 = """`
                                    <h6 class="fw-bold mb-0" style="color: var(--text-main); font-size: 13px;">${u.pangkat || ''} ${u.nama}</h6>
                                    <p class="mb-2 text-muted" style="font-size: 10px;">NRP: ${u.nrp} | ${u.satker}</p>
                                    <hr style="margin: 6px 0; border-color: var(--border-color);">
                                    <div class="d-flex justify-content-between mb-1" style="font-size: 11px;"><span>Aktivitas:</span> <b class="text-primary">${u.jenis_giat || 'Dinas'}</b></div>
                                    <div class="d-flex justify-content-between mb-1" style="font-size: 11px;"><span>Kendaraan:</span> <b>${u.vehicle || '-'}</b></div>
                                    <div class="d-flex justify-content-between" style="font-size: 11px;"><span>Update:</span> <b class="text-success">${new Date(u.waktu).toLocaleTimeString('id-ID')} WITA</b></div>
                                </div>
                            `)"""

if old1 in content:
    print("FIX 1 (showActiveUnitsBottomSheet popup): FOUND - no change needed")
else:
    print("FIX 1: not found (already fixed or different)")

# ─────────────────────────────────────────────────────────────────
# Find ALL remaining nested backticks in innerHTML patterns
# Pattern: `...${expr ? `...` : `...`}...` or `...${expr ? `...` : ''}...`
# ─────────────────────────────────────────────────────────────────

# Check current syntax
result = subprocess.run(
    ['node', '--input-type=module'],
    input=content.encode('utf-8'),
    capture_output=True, timeout=15
)
err = result.stderr.decode()
if 'SyntaxError' in err:
    # Find exact line
    for line in err.split('\n'):
        if 'SyntaxError' in line or ':' in line[:5]:
            print(f"Current error: {line}")
    
    # Extract line number
    import re
    m = re.search(r'\]:(\d+)', err)
    if m:
        errline = int(m.group(1))
        print(f"\nError at line {errline}")
        lines = content.split('\n')
        print("Context:")
        for i in range(max(0,errline-10), min(len(lines), errline+2)):
            print(f"  {i+1:4d}: {lines[i][:120]}")
else:
    print("NO SYNTAX ERROR — file is clean!")
