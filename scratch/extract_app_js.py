import json
import os

log_path = r"C:\Users\User\.gemini\antigravity\brain\d769ea74-d9bf-4a3c-b544-14f593fd0c85\.system_generated\logs\transcript.jsonl"

with open(log_path, 'r', encoding='utf-8') as f:
    for line in f:
        try:
            step = json.loads(line)
            tool_calls = step.get('tool_calls', [])
            if tool_calls:
                for tc in tool_calls:
                    args = tc.get('args', {})
                    if isinstance(args, str):
                        try:
                            args = json.loads(args)
                        except:
                            pass
                    if isinstance(args, dict):
                        target = args.get('TargetFile', '') or args.get('Target', '') or args.get('AbsolutePath', '')
                        if 'app.js' in target:
                            print(f"Step {step.get('step_index')}: {tc.get('name')} to {target}")
        except Exception as e:
            pass
