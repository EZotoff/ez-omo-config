#!/usr/bin/env python3
"""Derive the no-think + multi-system chat template for FLARE-4B (SGLang serving).

Starts from the tokenizer_config.json chat_template of a FLARE-4B snapshot and
applies two transformations:

1. NO-THINK: force the `enable_thinking is false` branch so the assistant turn
   starts with a closed `<think>\\n\\n</think>` block (OpenCode sends no
   chat_template_kwargs, and FLARE-4B otherwise rambles in an open think block
   that never closes).

2. MULTI-SYSTEM MERGE: OpenCode sends [system, system, user, ...] (agent prompt
   plus config-plugin system transforms). The stock template raises
   'System message must be at the beginning.' for any system message at index
   > 0. The derived template merges ALL leading system messages into a single
   system block and only raises for system messages that appear after a
   non-system message.

Usage:
  python3 derive-flare-chat-template.py <model-snapshot-dir> <output.jinja>

The output is referenced by systemd/user/flare-serve.service via --chat-template.
Regenerate and `systemctl --user restart flare-serve` after a model upgrade.
"""
import json
import sys
from pathlib import Path


def main() -> None:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    snapshot = Path(sys.argv[1])
    out_path = Path(sys.argv[2])

    template = json.load(open(snapshot / "tokenizer_config.json"))["chat_template"]
    assert isinstance(template, str), "chat_template must be a string"

    # --- 1. force no-think branch -------------------------------------------
    old_cond = "{%- if enable_thinking is defined and enable_thinking is false %}"
    assert template.count(old_cond) == 1, "enable_thinking condition not found exactly once"
    template = template.replace(old_cond, "{%- if true %}")

    # --- 2. multi-system merge ----------------------------------------------
    # 2a. compute the number of leading system messages right after the
    #     'No messages provided.' guard.
    guard = "{%- if not messages %}\n    {{- raise_exception('No messages provided.') }}\n{%- endif %}"
    assert template.count(guard) == 1, "messages guard not found"
    lead_calc = guard + (
        "\n{#- number of consecutive system messages at the start of the conversation -#}\n"
        "{%- set ns_lead = namespace(n=messages|length) %}\n"
        "{%- for message in messages %}\n"
        "    {%- if message.role != 'system' and loop.index0 < ns_lead.n %}\n"
        "        {%- set ns_lead.n = loop.index0 %}\n"
        "    {%- endif %}\n"
        "{%- endfor %}"
    )
    template = template.replace(guard, lead_calc)

    # 2b. tools branch: append ALL leading system contents to the tools system block.
    tools_block = """    {%- if messages[0].role == 'system' %}
        {%- set content = render_content(messages[0].content, false, true)|trim %}
        {%- if content %}
            {{- '\\n\\n' + content }}
        {%- endif %}
    {%- endif %}"""
    tools_new = """    {%- if ns_lead.n > 0 %}
        {%- set ns_sys = namespace(acc='') %}
        {%- for sysmsg in messages[:ns_lead.n] %}
            {%- set content = render_content(sysmsg.content, false, true)|trim %}
            {%- if content %}
                {%- set ns_sys.acc = ns_sys.acc ~ ('\\n\\n' if ns_sys.acc else '') ~ content %}
            {%- endif %}
        {%- endfor %}
        {%- if ns_sys.acc %}
            {{- '\\n\\n' + ns_sys.acc }}
        {%- endif %}
    {%- endif %}"""
    assert template.count(tools_block) == 1, "tools-branch system block not found exactly once"
    template = template.replace(tools_block, tools_new)

    # 2c. no-tools branch: render ALL leading system messages as one merged system block.
    plain_block = """    {%- if messages[0].role == 'system' %}
        {%- set content = render_content(messages[0].content, false, true)|trim %}
        {{- '<|im_start|>system\\n' + content + '<|im_end|>\\n' }}
    {%- endif %}"""
    plain_new = """    {%- if ns_lead.n > 0 %}
        {%- set ns_sys = namespace(acc='') %}
        {%- for sysmsg in messages[:ns_lead.n] %}
            {%- set content = render_content(sysmsg.content, false, true)|trim %}
            {%- if content %}
                {%- set ns_sys.acc = ns_sys.acc ~ ('\\n\\n' if ns_sys.acc else '') ~ content %}
            {%- endif %}
        {%- endfor %}
        {%- if ns_sys.acc %}
            {{- '<|im_start|>system\\n' + ns_sys.acc + '<|im_end|>\\n' }}
        {%- endif %}
    {%- endif %}"""
    assert template.count(plain_block) == 1, "plain system block not found exactly once"
    template = template.replace(plain_block, plain_new)

    # 2d. main loop: skip already-rendered leading system messages; raise only
    #     for system messages that appear after a non-system message.
    old_raise = """    {%- if message.role == "system" %}
        {%- if not loop.first %}
            {{- raise_exception('System message must be at the beginning.') }}
        {%- endif %}"""
    new_raise = """    {%- if message.role == "system" %}
        {%- if loop.index0 >= ns_lead.n %}
            {{- raise_exception('System message must appear only at the beginning.') }}
        {%- endif %}"""
    assert template.count(old_raise) == 1, "system raise guard not found exactly once"
    template = template.replace(old_raise, new_raise)

    out_path.write_text(template)
    print(f"wrote {out_path} ({len(template)} bytes)")


if __name__ == "__main__":
    main()
