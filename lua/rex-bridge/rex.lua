-- SPDX-License-Identifier: GPL-2.0-only
-- Adapted from code-bridge.nvim's Rex backend, 2026-11-10.
local M = {}

local function run(session, args, input, json)
	local command = { "rex", "-s", session }
	vim.list_extend(command, args)
	local started, result = pcall(function()
		return vim.system(command, { stdin = input, text = true, timeout = 3000 }):wait()
	end)
	if not started then
		return nil, "cannot run Rex: " .. tostring(result)
	end
	if result.code ~= 0 then
		local err = vim.trim(result.stderr or "")
		return nil, err ~= "" and err or "Rex command failed or timed out"
	end
	if not json then
		return true
	end
	local ok, data = pcall(vim.json.decode, result.stdout)
	if not ok or type(data) ~= "table" then
		return nil, "invalid JSON from Rex"
	end
	return data
end

local function find_target(session, editor, processes)
	local listing, err = run(session, { "block", "ls", "--json" }, nil, true)
	if not listing then
		return nil, err
	end
	local window
	for _, block in ipairs(listing.blocks or {}) do
		if block.block_id == editor then
			window = block.window_id
			break
		end
	end
	if not window then
		return nil, "cannot locate the editor Rex pane"
	end

	local candidates = {}
	for _, block in ipairs(listing.blocks or {}) do
		if
			block.window_id == window
			and block.block_id ~= editor
			and block.creator_name == "com.superlogical.terminal"
		then
			local process, process_err = run(session, { "block", "call", "-b", block.block_id, "process" }, nil, true)
			if not process then
				return nil, process_err
			end
			if type(process.foreground) == "table" then
				candidates[#candidates + 1] = { id = block.block_id, process = process.foreground }
			end
		end
	end
	-- Process order is priority; Rex listing order breaks ties.
	for _, name in ipairs(processes) do
		for _, candidate in ipairs(candidates) do
			for _, field in ipairs({ "name", "argv0", "invoked_path", "script" }) do
				local value = candidate.process[field]
				if type(value) == "string" and vim.fn.fnamemodify(value, ":t") == name then
					return candidate.id
				end
			end
		end
	end
	return nil, "no pane running " .. table.concat(processes, " or ") .. " in the editor Rex tab"
end

function M.send(reference, config)
	local session, editor = vim.env.REX_SESSION, vim.env.REX_BLOCK
	if not session or session == "" or not editor or editor == "" then
		return nil, "Neovim must run inside a Rex terminal"
	end
	local target, err = find_target(session, editor, config.processes)
	if not target then
		return nil, err
	end
	local modes
	modes, err = run(session, { "block", "call", "-b", target, "modes" }, nil, true)
	if not modes then
		return nil, err
	end
	for _, mode in ipairs(modes.modes or {}) do
		if mode.name == "bracketed_paste" and mode.set then
			reference = "\27[200~" .. reference .. "\27[201~"
			break
		end
	end
	local ok
	ok, err = run(session, { "send", "-b", target }, reference)
	if not ok then
		return nil, err
	end
	if config.focus then
		ok, err = run(session, { "focus", target })
		if not ok then
			return nil, "reference pasted, but focus failed: " .. err
		end
	end
	return true
end

return M
