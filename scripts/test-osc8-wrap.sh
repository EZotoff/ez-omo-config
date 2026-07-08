#!/usr/bin/env bash
# Standalone OSC 8 hyperlink wrapping test for Alacritty.
# Run this DIRECTLY in Alacritty (not through opencode TUI):
#   bash ~/ez-omo-config/scripts/test-osc8-wrap.sh
#
# It emits three hyperlinks that force a line-wrap at narrow widths.
# After running, try Ctrl+Click (or Cmd+Click) on EACH visual line of each link.
#
# Expected if Alacritty handles multi-line OSC 8 correctly:
#   - ALL visual lines of each link are clickable.
#
# If only the FIRST visual line of each link is clickable:
#   - Confirmed: Alacritty has a multi-line OSC 8 hyperlink bug.
#
# Reference: https://gist.github.com/egmontkov/eb114294efbcd5adb1944c9842f0ec18

OSC8_OPEN='\x1b]8;;%s\x1b\\'
OSC8_CLOSE='\x1b]8;;\x1b\\'

printf '\n=== OSC 8 Multi-line Hyperlink Test ===\n\n'

# Link 1: long file path that wraps at 40 cols
printf 'Link 1 (file path, wraps at ~40 cols):\n'
tput cuf 0  # ensure left margin
printf "$OSC8_OPEN" "file:///home/ezotoff/ez-omo-config/configs/opencode/opencode.json"
printf '/home/ezotoff/ez-omo-config/configs/opencode/opencode.json'
printf "$OSC8_CLOSE"
printf '\n\n'

# Link 2: explicit two-line text within one OSC 8 region (uses \n inside hyperlink)
printf 'Link 2 (explicit newline inside OSC 8 region):\n'
printf "$OSC8_OPEN" "https://example.com/very/long/url/that/should/be/clickable/on/both/lines"
printf 'Line A of link\nLine B of link'
printf "$OSC8_CLOSE"
printf '\n\n'

# Link 3: short link (single line, control — should always be clickable)
printf 'Link 3 (single line, control):\n'
printf "$OSC8_OPEN" "https://example.com"
printf 'click me (single line)'
printf "$OSC8_CLOSE"
printf '\n\n'

printf '=== End of test ===\n'
printf 'If Link 1 and Link 2 are only clickable on their FIRST line,\n'
printf 'but Link 3 works fine, the bug is in Alacritty OSC 8 handling.\n'
