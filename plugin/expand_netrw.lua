-- Only load once
if vim.g.expand_netrw_loaded == 1 then
	return
end
vim.g.expand_netrw_loaded = 1


-- Global variables
if vim.g.expand_netrw_open_cmd == nil then
	vim.g.expand_netrw_open_cmd = 'Lexplore'
end
if vim.g.expand_netrw_grow_direction == nil then
	vim.g.expand_netrw_grow_direction = 'belowright'
end

expand_netrw = {} -- Global functions


-- Shortcuts
local cmd = vim.cmd
local expand = vim.fn.expand
local input = vim.fn.input


-- Configure Netrw display options
vim.g.netrw_banner = 0
vim.g.netrw_liststyle = 3
vim.g.netrw_browse_split = 4
vim.g.netrw_winsize = 20
vim.g.netrw_browse_split = 1

if string.sub(vim.g.expand_netrw_open_cmd, 1, 8) == 'Hexplore' then
	vim.g.netrw_browse_split = 2
end
	


-- Variables
local popups = {}


-- Popup handling
function popupOpen(win, label)
	local popup = popups[win]
	if popup ~= nil then
		vim.api.nvim_win_close(popup.win, true)
		vim.api.nvim_buf_delete(popup.buf, { force=true })
	else
		popup = {}
	end

	local win_half_height = math.floor(vim.fn.winheight(win) / 2)
	local win_half_width = math.floor(vim.fn.winwidth(win) / 2)

	popup.buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(popup.buf, 0, 0, false, {
		' +-------+', ' |   ' .. label .. '   |', ' +-------+'
	})

	vim.api.nvim_set_current_win(win)
	popup.win = vim.api.nvim_open_win(popup.buf, false, {
		relative='win',
		width=11,
		height=3,
		row=win_half_height - 2,
		col=win_half_width - 5,
		focusable=false,
		style='minimal',
		border='shadow',
		noautocmd=true
	})
	vim.wo[popup.win].number = false
	vim.wo[popup.win].winhighlight = 'Normal:MatchParen'

	popups[win] = popup
end

function popupCloseAll()
	for win, popup in pairs(popups) do
		vim.api.nvim_win_close(popup.win, true)
		vim.api.nvim_buf_delete(popup.buf, { force=true })

		popups[win] = nil
	end
end


-- Utility functions
local function getPathTrail(path)
	slash = 0

	for i=#path,1,-1 do
		if string.byte(path, i) == 47 then
			slash = i
			break
		end
	end

	return string.sub(path, slash + 1)
end


local function promptFocus()
	local windows = vim.api.nvim_list_wins()
	local length = #windows

	-- Auto select if only one present or if there are too many present
	if length == 2  or length > 27 then
		local first_window_buf = vim.api.nvim_win_get_buf(windows[1])
		local first_window_buf_name
			= getPathTrail(vim.api.nvim_buf_get_name(first_window_buf))
		if first_window_buf_name == 'NetrwTreeListing' then
			vim.api.nvim_set_current_win(windows[2])
		else
			vim.api.nvim_set_current_win(windows[1])
		end
		return true
	end

	-- Label windows
	local netrw = nil
	local offset = 0
	for i=1,length do
		local buf = vim.api.nvim_win_get_buf(windows[i])
		if getPathTrail(vim.api.nvim_buf_get_name(buf)) == 'NetrwTreeListing' then
			if netrw ~= nil then
				error('Cannot have more than one Netrw window open')
				popupCloseAll()
				return false
			end
			netrw = i
			offset = -1
		else
			popupOpen(windows[i], string.char(64 + i + offset))
		end
	end

	if netrw == nil then
		error('Missing Netrw window')
		popupCloseAll()
		return false
	end

	cmd('redraw')

	-- Get input after delay so windows can render
	vim.fn.inputsave()
	local window = input('Select a window: ')
	popupCloseAll()
	vim.fn.inputrestore()

	if window ~= '' then
		window = string.byte(window)
		if window > 90 then
			window = window - 96
		else
			window = window - 64
		end
	else
		window = -1
	end

	-- Check for bad input
	if window < 1 or window > #windows then
		vim.api.nvim_set_current_win(windows[netrw])
		print('Invalid selection')
		return false
	end

	-- Adjust input for Netrw position and then focus it
	if window >= netrw then
		window = window + 1
	end

	vim.api.nvim_set_current_win(windows[window])
	return true
end


-- Netrw callbacks
local bindNetrwKeys

local function splitFile(direction)
	local file = vim.fn.getline('.')

	if string.byte(file, #file) == 47 then
		-- Default behavior for directories
		cmd('execute ":normal \\<CR>"')
		bindNetrwKeys()
		return
	end

	-- Get path through Netrw split
	cmd('execute ":normal \\<CR>"')
	local path = expand('%')
	cmd('quit')


	-- Forward to prompted split
	if promptFocus() then
		cmd(vim.g.expand_netrw_grow_direction .. ' ' .. direction .. ' ' .. path)
	end
end

expand_netrw.splitVertical = function()
	splitFile('vnew')
end

expand_netrw.splitHorizontal = function()
	splitFile('new')
end

expand_netrw.open = function()
	local file = vim.fn.getline('.')

	if string.byte(file, #file) == 47 then
		-- Default behavior for directories
		cmd('execute ":normal \\<CR>"')
		bindNetrwKeys()
		return
	end

	-- Get path through Netrw split
	cmd('execute ":normal \\<CR>"')
	local path = expand('%')
	cmd('quit')

	-- Forward to prompted edit
	if promptFocus() then
		cmd('edit ' .. path)
	end
end

bindNetrwKeys = function()
	-- Rebind move left
	cmd('nmap <buffer><silent> <C-l> :wincmd l<CR>')
	cmd('nmap <buffer><silent> <C-r> :wincmd t<CR>')


	-- Splitting
	cmd('nmap <buffer><silent> s :lua expand_netrw.splitVertical()<CR>')
	cmd('nmap <buffer><silent> h :lua expand_netrw.splitHorizontal()<CR>')
	cmd('nmap <buffer><silent> n :lua expand_netrw.open()<CR>')
end


-- Initalize function
expand_netrw.toggleNetrw = function()
	-- Test if Netrw is open
	local windows = vim.api.nvim_list_wins()
	local length = #windows
	local window = nil

	for i=1,length do
		local buf = vim.api.nvim_win_get_buf(windows[i])
		if getPathTrail(vim.api.nvim_buf_get_name(buf)) == 'NetrwTreeListing' then
			window = windows[i]
			break
		end
	end

	if window ~= nil then
		-- Netrw is open
		if expand('%') == 'NetrwTreeListing' then
			-- Netrw is selected, close it
			cmd('quit')
		else
			-- Go to netrw
			vim.api.nvim_set_current_win(window)
		end
	else
		-- Netrw is not open
		cmd(vim.g.expand_netrw_open_cmd)
		bindNetrwKeys()
	end
end


-- Close Netrw if it's the last thing open
expand_netrw.enterNetrw = function()
	if #vim.api.nvim_list_wins() == 1 then
		cmd('quit')
	end
end
vim.cmd([[
	augroup expand_netrew
		autocmd!
		autocmd WinEnter NetrwTreeListing lua expand_netrw.enterNetrw()
	augroup END
]])


-- Key maps
cmd('nmap <silent> e :lua expand_netrw.toggleNetrw()<CR>')
