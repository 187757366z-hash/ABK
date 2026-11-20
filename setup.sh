#!/usr/bin/env bash
# ABK after_patch hook for Xiaomi 17 Max (byron / SM8850), Droidspaces GKI build.
#
# Why: Android GKI vendor modules carry DWARF-derived symbol CRCs
# (CONFIG_GENDWARFKSYMS=y). A locally rebuilt kernel almost always produces a
# different CRC fingerprint than the OEM kernel, so every vendor module is
# rejected with "disagrees about version of symbol" and the phone bootloops.
# Droidspaces' own kABI patch keeps the real struct offsets intact; this hook
# only relaxes the runtime CRC comparison, matching what other SM8850 GKI
# rebuilds do.
set -euo pipefail
: "${KERNEL_ROOT:?KERNEL_ROOT is not set by ABK}"
V="$KERNEL_ROOT/common/kernel/module/version.c"
[ -f "$V" ] || { echo "::error::version.c not found: $V"; exit 1; }

python3 - "$V" <<'PY'
import sys, re
p = sys.argv[1]
s = open(p, encoding='utf-8', errors='replace').read()
if 'ABK_DS_SKIP_CRC' in s:
    print('CRC-skip patch already present')
    sys.exit(0)
m = re.search(r'\bint\s+check_version\s*\(', s)
if not m:
    sys.exit('check_version not found')
i = s.find('{', m.end())
if i < 0:
    sys.exit('check_version body not found')
depth = 0
j = i
while j < len(s):
    c = s[j]
    if c == '{':
        depth += 1
    elif c == '}':
        depth -= 1
        if depth == 0:
            break
    elif c == '"':
        j += 1
        while j < len(s) and s[j] != '"':
            if s[j] == '\\':
                j += 1
            j += 1
    elif c == "'":
        j += 1
        while j < len(s) and s[j] != "'":
            if s[j] == '\\':
                j += 1
            j += 1
    j += 1
if depth != 0:
    sys.exit('unbalanced braces while parsing check_version')
new = '''int check_version(const struct load_info *info,
		  const char *symname,
		  struct module *mod,
		  const u32 *crc)
{
	/* ABK_DS_SKIP_CRC: GKI kABI is preserved by the Droidspaces
	 * SYSVIPC padding patch; DWARF CRC fingerprints differ between
	 * build toolchains, so accept the vendor module's CRC.
	 */
	(void)info; (void)symname; (void)mod; (void)crc;
	return 1;
}'''
s = s[:m.start()] + new + s[j+1:]
open(p, 'w', encoding='utf-8').write(s)
print('patched check_version -> always accept (ABK_DS_SKIP_CRC)')
PY

grep -q 'ABK_DS_SKIP_CRC' "$V"
grep -q 'return 1;' "$V"
echo "ABK Droidspaces CRC-skip hook applied: $V"
