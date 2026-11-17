#!/usr/bin/env python3
"""Merge this setup's Handy settings into settings_store.json.

Only the keys listed here are changed. Everything else (dictionary, history
settings, microphone choice, your own prompts) is left alone. Run while Handy
is stopped, otherwise Handy overwrites the file on exit.
"""
import argparse, json, os, shutil, time
from pathlib import Path

ap = argparse.ArgumentParser()
ap.add_argument('--cleanup-model', default='', help='OpenRouter model id; empty disables the cleanup bridge settings')
ap.add_argument('--port', type=int, default=18784)
ap.add_argument('--model-id', required=True)
ap.add_argument('--settings', default=str(Path.home() / '.local/share/com.pais.handy/settings_store.json'))
args = ap.parse_args()

here = Path(__file__).resolve().parent
path = Path(args.settings)
path.parent.mkdir(parents=True, exist_ok=True)
store = {'settings': {}}
if path.exists():
    shutil.copy2(path, path.with_name(path.name + '.bak-handy-omarchy-' + time.strftime('%Y%m%d%H%M%S')))
    store = json.loads(path.read_text())
s = store.setdefault('settings', {})

s.update({
    'onboarding_completed': True,
    'start_hidden': True,
    'autostart_enabled': False,          # systemd starts Handy instead
    'selected_model': args.model_id,
    'transcribe_accelerator': 'cpu',     # Parakeet Q8 was faster on CPU than Vulkan in my test
    'shortcut_activation': 'toggle',
    'overlay_style': 'none',             # the bar widget replaces the floating overlay
    'always_on_microphone': False,       # the widget follows the per-recording mic stream
    'log_level': 'info',                 # the widget reads recording events from the journal
    'paste_method': 'external_script',
    'external_script_path': str(Path.home() / '.local/bin/handy-paste'),
    'typing_tool': 'wtype',
    'audio_feedback': True,
    'audio_feedback_volume': 0.25,
    'sound_theme': 'custom',
})

if args.cleanup_model:
    providers = s.get('post_process_providers') or json.loads((here / 'default-providers.json').read_text())
    for p in providers:
        if p.get('id') == 'custom':
            p['base_url'] = f'http://127.0.0.1:{args.port}/v1'
    s['post_process_providers'] = providers
    models = s.get('post_process_models') or {p['id']: '' for p in providers}
    models['custom'] = args.cleanup_model
    s['post_process_models'] = models
    prompts = [p for p in (s.get('post_process_prompts') or []) if p.get('id') != 'handy_omarchy_cleanup']
    prompts.append({'id': 'handy_omarchy_cleanup', 'name': 'Dictation cleanup',
                    'prompt': (here.parent / 'prompts/cleanup.txt').read_text().rstrip('\n')})
    s['post_process_prompts'] = prompts
    s['post_process_selected_prompt_id'] = 'handy_omarchy_cleanup'
    s['post_process_provider_id'] = 'custom'
    s['post_process_enabled'] = True

tmp = path.with_name(path.name + '.tmp')
tmp.write_text(json.dumps(store, indent=2))
os.chmod(tmp, 0o600)
tmp.replace(path)
print('Handy settings updated:', path)
