vim.opt.rtp:prepend('.')

local calls, failure, invalid_json, bracketed, blocks, processes, notices
local original_system = vim.system
local original_notify = vim.notify
local bridge = require('rex-bridge')
local count = 0

local function reset()
  calls, notices = {}, {}
  failure, invalid_json, bracketed = nil, false, true
  vim.env.REX_SESSION, vim.env.REX_BLOCK = 'session', 'editor'
  blocks = {
    { block_id = 'editor', window_id = 'here', creator_name = 'com.superlogical.terminal' },
    { block_id = 'claude', window_id = 'here', creator_name = 'com.superlogical.terminal' },
    { block_id = 'agent', window_id = 'here', creator_name = 'com.superlogical.terminal' },
    { block_id = 'other', window_id = 'elsewhere', creator_name = 'com.superlogical.terminal' },
    { block_id = 'browser', window_id = 'here', creator_name = 'browser' },
  }
  processes = {
    claude = { foreground = { name = 'zsh' } },
    agent = { foreground = { name = 'node', script = '/bin/opencode' } },
  }
  vim.bo.buftype = ''
  vim.api.nvim_buf_set_name(0, vim.fn.getcwd() .. '/example.lua')
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'one', 'two', 'three' })
  bridge.setup()
end

vim.notify = function(message)
  notices[#notices + 1] = message
end
vim.system = function(args, opts)
  calls[#calls + 1] = { args = args, input = opts.stdin }
  assert(args[1] == 'rex' and args[2] == '-s' and args[3] == 'session')
  local response = {}
  if args[4] == 'block' and args[5] == 'ls' then
    response = { blocks = blocks }
  elseif args[#args] == 'process' then
    response = assert(processes[args[#args - 1]], 'queried a pane outside the target scope')
  elseif args[#args] == 'modes' then
    response = { modes = { { name = 'bracketed_paste', set = bracketed } } }
  end
  return { wait = function()
    return {
      code = failure == args[4] and 1 or 0,
      stderr = failure and 'simulated failure' or '',
      stdout = invalid_json and 'not JSON' or vim.json.encode(response),
    }
  end }
end

local function pasted()
  for _, call in ipairs(calls) do
    if call.args[4] == 'send' then
      assert(call.args[6] == 'agent')
      return call.input
    end
  end
end

local function test(name, fn)
  reset()
  fn()
  count = count + 1
  print('ok: ' .. name)
end

test('normal command, process priority, tab scope, draft and focus', function()
  processes.claude.foreground = { name = 'claude' }
  assert(bridge.send())
  assert(calls[#calls].args[5] == 'claude')
  calls = {}
  processes.claude.foreground = { name = 'codex' }
  assert(bridge.send())
  assert(calls[#calls].args[5] == 'claude')
  calls = {}
  processes.claude.foreground = { name = 'zsh' }
  vim.cmd('RexBridgeSend')
  assert(pasted() == '\27[200~@example.lua\27[201~')
  assert(calls[#calls].args[4] == 'focus' and calls[#calls].args[5] == 'agent')
  for _, call in ipairs(calls) do
    assert(call.args[4] ~= 'send-key')
  end
end)

test('visual mapping carries range and a later normal send has none', function()
  vim.keymap.set({ 'n', 'x' }, '<F6>', ':RexBridgeSend<CR>')
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  local keys = vim.api.nvim_replace_termcodes('Vj<F6>', true, false, true)
  vim.api.nvim_feedkeys(keys, 'xt', false)
  assert(pasted() == '\27[200~@example.lua#L1-2\27[201~')
  calls = {}
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<F6>', true, false, true), 'xt', false)
  assert(pasted() == '\27[200~@example.lua\27[201~')
end)

test('explicit single-line range', function()
  vim.cmd('2RexBridgeSend')
  assert(pasted() == '\27[200~@example.lua#L2-2\27[201~')
end)

test('literal path and focus disabled', function()
  bridge.setup({ focus = false })
  bracketed = false
  vim.api.nvim_buf_set_name(0, vim.fn.getcwd() .. '/λ space $ quote".lua')
  assert(bridge.send())
  assert(pasted() == '@λ space $ quote".lua')
  assert(calls[#calls].args[4] == 'send')
end)

test('custom process list replaces defaults and setup resets', function()
  bridge.setup({ processes = { 'missing' } })
  assert(not bridge.send() and not pasted())
  bridge.setup()
  assert(bridge.send())
end)

test('process callback is evaluated on each send and supports names and lists', function()
  processes.claude.foreground = { name = 'claude' }
  local selected, invocations = 'claude', 0
  bridge.setup({ processes = function()
    invocations = invocations + 1
    return selected
  end })
  assert(invocations == 0)
  assert(bridge.send())
  assert(calls[#calls].args[5] == 'claude')
  calls, selected = {}, { 'opencode', 'claude' }
  assert(bridge.send() and pasted())
  assert(invocations == 2)
end)

test('callback errors and invalid results never send', function()
  local callbacks = {
    function() error('finder failed') end,
    function() return nil end,
    function() return false end,
    function() return {} end,
    function() return { '' } end,
    function() return 42 end,
  }
  for _, callback in ipairs(callbacks) do
    bridge.setup({ processes = callback })
    local ok, err = bridge.send()
    assert(not ok and err:find('cannot resolve processes') and #calls == 0)
  end
end)

test('defaults fall back to codex', function()
  processes.claude.foreground = { name = 'zsh' }
  processes.agent.foreground = { name = 'codex' }
  assert(bridge.send() and pasted())
end)

test('static single process name', function()
  processes.claude.foreground = { name = 'claude' }
  bridge.setup({ processes = 'claude' })
  assert(bridge.send())
  assert(calls[#calls].args[5] == 'claude')
end)

test('exact process matching', function()
  processes.agent.foreground = { name = 'opencode-other' }
  processes.claude.foreground = { name = 'claude-other' }
  assert(not bridge.send() and not pasted())
end)

test('missing session and stale editor', function()
  vim.env.REX_SESSION = nil
  assert(not bridge.send() and #calls == 0)
  vim.env.REX_SESSION, vim.env.REX_BLOCK = 'session', 'stale'
  assert(not bridge.send() and not pasted())
end)

test('unnamed and special buffers', function()
  vim.api.nvim_buf_set_name(0, '')
  assert(not bridge.send() and #calls == 0)
  vim.api.nvim_buf_set_name(0, 'special')
  vim.bo.buftype = 'nofile'
  assert(not bridge.send() and #calls == 0)
end)

test('control characters in paths', function()
  vim.api.nvim_buf_set_name(0, vim.fn.getcwd() .. '/bad\nname')
  assert(not bridge.send() and #calls == 0)
end)

test('discovery failure and malformed JSON', function()
  failure = 'block'
  assert(not bridge.send() and not pasted())
  failure, invalid_json = nil, true
  assert(not bridge.send() and not pasted())
end)

test('delivery failure never focuses', function()
  failure = 'send'
  assert(not bridge.send())
  assert(calls[#calls].args[4] == 'send')
end)

test('focus failure reports successful paste', function()
  failure = 'focus'
  local ok, err = bridge.send()
  assert(not ok and err:find('reference pasted') and pasted())
end)

test('missing executable', function()
  local mock = vim.system
  vim.system = function() error('ENOENT') end
  local ok, err = bridge.send()
  vim.system = mock
  assert(not ok and err:find('cannot run Rex'))
end)

vim.system, vim.notify = original_system, original_notify
print(('%d tests passed'):format(count))
