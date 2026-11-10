# rex-bridge.nvim

Send file references from Neovim to an AI terminal in the same Rex tab.

- Normal mode: `@path/to/file.lua`
- Visual mode: `@path/to/file.lua#L10-20`

The reference is pasted into the target and that pane receives focus. It stays a draft: Enter is never sent. Visual selections reference whole lines, including characterwise and blockwise selections. File contents are not sent or saved.

## Requirements

Neovim 0.10+, the `rex` CLI on PATH, and Neovim running inside a Rex terminal. Run your AI terminal in the same Rex tab, with the same project working directory. Paths use Neovim's working directory when possible, otherwise a home-relative or absolute path, matching code-bridge.nvim.

## Setup (lazy.nvim)

```lua
return {
  'burkayanduv/rex-bridge.nvim',
  opts = {
    processes = { 'opencode', 'claude', 'codex' }, -- ordered preference
    focus = true,
  },
  keys = {
    { '<leader>aa', ':RexBridgeSend<CR>', mode = { 'n', 'x' }, desc = 'Send context to AI' },
  },
}
```

These are the defaults; `opts = {}` is enough. With another plugin manager, call `require('rex-bridge').setup()` and define your own mapping.

`processes` also accepts a single name or a function returning a name or ordered list. The function runs on every send, so it can use your current Neovim state:

```lua
opts = {
  processes = function()
    return vim.b.ai_process or { 'opencode', 'claude', 'codex' }
  end,
}
```

Callback errors and invalid results are reported without sending a reference.

`:RexBridgeSend` sends the current file; `:10,20RexBridgeSend` sends a line range. The `:` mapping above preserves the visual range automatically.

Discovery uses `REX_SESSION` and `REX_BLOCK` to locate the editor's tab, even if another tab is focused. Process names match exactly, including executable and script basenames. The first matching pane wins within each process preference. Errors are reported through `vim.notify`.

## Tests

```sh
nvim --headless -u NONE -l tests/run.lua
```

## License

Licensed under [GPL-2.0](LICENSE). Derived from [Samir Roy's code-bridge.nvim](https://github.com/samir-roy/code-bridge.nvim). Simplified for Rex-only file references in November 2026.
