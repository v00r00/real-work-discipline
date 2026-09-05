#!/usr/bin/env bash
# Validates skills against the Agent Skills specification (agentskills.io).
# Catches: broken YAML frontmatter · name not matching the directory · a name that
# breaks the required form · a description over 1024 characters · angle brackets
# in a description · unknown frontmatter keys.
#
# Origin: some rules come from quick_validate.py in Anthropic's official
# skill-creator plugin. Two deliberate differences:
#  - runs over ALL skills at once, not one at a time — otherwise it never gets run;
#  - `disable-model-invocation` is in the allowed key list: Claude Code supports it,
#    and their list does not know about it.
#
# Why it exists: a colon inside a description made the frontmatter invalid YAML;
# one description was 1292 characters against a limit of 1024; another contained an
# angle bracket. All three would have gone unnoticed — Claude Code parses more
# leniently than the specification, so the defect is invisible by eye.
#
# Requires: python3 with pyyaml.
set -euo pipefail
cd "$(dirname "$0")"
python3 - <<'PY'
import io,os,re,sys,yaml

ALLOWED={'name','description','license','allowed-tools','metadata',
         'compatibility','disable-model-invocation'}
ok=True
print(f"{'skill':<24}{'yaml':<8}{'keys':<20}{'name':<14}{'chars':<8}{'brackets':<10}limit")
for d in sorted(os.listdir('.')):
    f=os.path.join(d,'SKILL.md')
    if not os.path.isfile(f): continue
    s=io.open(f,encoding='utf-8').read()
    m=re.match(r'^---\n(.*?)\n---\n', s, re.S)
    if not m:
        print(f"{d:<24}NO FRONTMATTER"); ok=False; continue
    try:
        fm=yaml.safe_load(m.group(1))
    except Exception as e:
        print(f"{d:<24}YAML ERROR — {str(e).splitlines()[0]}"); ok=False; continue
    if not isinstance(fm,dict):
        print(f"{d:<24}FRONTMATTER IS NOT A MAPPING"); ok=False; continue

    extra=sorted(set(fm)-ALLOWED)
    keys="ok" if not extra else "UNKNOWN:"+",".join(extra)

    name=fm.get('name') or ''
    if name!=d: nm=f"MISMATCH:{name}"
    elif not re.fullmatch(r'[a-z0-9]+(-[a-z0-9]+)*', name): nm="BAD FORM"
    elif len(name)>64: nm=f"TOO LONG:{len(name)}"
    else: nm="ok"

    desc=fm.get('description') or ''
    ang="".join(c for c in '<>' if c in desc)
    br="ok" if not ang else f"HAS {ang}"
    lim="ok" if len(desc)<=1024 else "OVER 1024"

    if keys!="ok" or nm!="ok" or br!="ok" or lim!="ok": ok=False
    print(f"{d:<24}{'ok':<8}{keys:<20}{nm:<14}{len(desc):<8}{br:<10}{lim}")
print()
print("ALL SKILLS MATCH THE SPECIFICATION" if ok else "VIOLATIONS FOUND")
sys.exit(0 if ok else 1)
PY
