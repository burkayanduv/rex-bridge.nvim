-- SPDX-License-Identifier: GPL-2.0-only
-- Adapted from code-bridge.nvim; simplified for Rex, 2026-11-10.
local M = {}

local defaults = { processes = { "claude", "codex", "opencode" }, focus = true }
local config = vim.deepcopy(defaults)

local function process_names(value)
	if type(value) == "string" then
		value = { value }
	end
	assert(type(value) == "table" and vim.islist(value) and #value > 0,
		"processes must be a name or nonempty list of names")
	for _, name in ipairs(value) do
		assert(type(name) == "string" and name ~= "", "process names must be nonempty strings")
	end
	return value
end

function M.send(opts)
	opts = opts or {}
	local name = vim.api.nvim_buf_get_name(0)
	if name == "" or vim.bo.buftype ~= "" then
		vim.notify("rex-bridge: current buffer is not a named file", vim.log.levels.WARN)
		return
	end

	local reference = "@" .. vim.fn.fnamemodify(name, ":~:.")
	if (opts.range or 0) > 0 then
		reference = reference .. "#L" .. opts.line1 .. "-" .. opts.line2
	end
	if reference:find("%c") then
		vim.notify("rex-bridge: file path contains control characters", vim.log.levels.ERROR)
		return
	end

	local resolved, processes = pcall(function()
		local value = config.processes
		if type(value) == "function" then
			value = value()
		end
		return process_names(value)
	end)
	if not resolved then
		local err = "cannot resolve processes: " .. tostring(processes)
		vim.notify("rex-bridge: " .. err, vim.log.levels.ERROR)
		return nil, err
	end
	local ok, err = require("rex-bridge.rex").send(reference, { processes = processes, focus = config.focus })
	if not ok then
		vim.notify("rex-bridge: " .. err, vim.log.levels.ERROR)
	end
	return ok, err
end

function M.setup(opts)
	opts = opts or {}
	local processes = opts.processes or defaults.processes
	if type(processes) ~= "function" then
		process_names(processes)
	end
	assert(opts.focus == nil or type(opts.focus) == "boolean", "rex-bridge: focus must be a boolean")
	config = { processes = vim.deepcopy(processes), focus = opts.focus ~= false }
	vim.api.nvim_create_user_command("RexBridgeSend", M.send, {
		range = true,
		desc = "Send a file or line-range reference to a Rex AI pane",
	})
end

return M
