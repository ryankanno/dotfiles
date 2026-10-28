# The critic's tokens under opencode

pr-review §2 links here when the critic ran under opencode.

opencode's task tool
reports no usage, but its result starts with `<task id="ses_...">`, and
the opencode database holds that session's tokens:

```bash
sqlite3 -readonly "file:$HOME/.local/share/opencode/opencode.db?mode=ro" \
  "select tokens_input + tokens_output + tokens_reasoning + tokens_cache_read + tokens_cache_write from session where id = '<ses_id>'"
```
