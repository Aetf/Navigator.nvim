local A = vim.api
local F = vim.fn
local cmd = A.nvim_command

---State and defaults
---@class Nav
---@field last_pane boolean
---@field config? Config
local N = {
    last_pane = false,
    config = nil,
}

---Detect and load correct mux
---@return Vi
local function load_mux()
    local ok_tmux, tmux = pcall(function()
        return require('Navigator.mux.tmux'):new()
    end)
    if ok_tmux then
        return tmux
    end
    local ok_wezterm, wezterm = pcall(function()
        return require('Navigator.mux.wezterm'):new()
    end)
    if ok_wezterm then
        return wezterm
    end
    return require('Navigator.mux.vi'):new()
end

local function tabcmd(direction)
    if direction == 'n' then
        cmd('tabnext')
    elseif direction == 'p' then
        cmd('tabprevious')
    elseif direction == 'l' then
        -- g<Tab> goes to the last accessed tab
        cmd('normal! g\t')
    end
end

local function maybe_auto_save()
    local w = N.config.auto_save
    if w ~= nil then
        if w == 'current' then
            local cur_buf = A.nvim_get_current_buf()
            if F.exists(A.nvim_buf_get_name(cur_buf)) then
                cmd('update')
            end
        end

        if w == 'all' then
            for _, buf in pairs(A.nvim_list_bufs()) do
                if A.nvim_buf_is_loaded(buf) and F.exists(A.nvim_buf_get_name(buf)) then
                    A.nvim_buf_call(buf, function()
                        cmd('update')
                    end)
                end
            end
        end
    end
end

---For setting up the plugin with the user provided options
---@param opts Config
function N.setup(opts)
    ---@type Config
    local config = {
        disable_on_zoom = false,
        auto_save = nil,
        mux = 'auto',
    }

    if opts ~= nil then
        N.config = vim.tbl_extend('keep', opts, config)
    else
        N.config = config
    end

    if N.config.mux == 'auto' then
        N.config.mux = load_mux()
    end

    A.nvim_create_autocmd('WinEnter', {
        group = A.nvim_create_augroup('NAVIGATOR', { clear = true }),
        callback = function()
            N.last_pane = false
        end,
    })
end

---Checks whether we need to move to the nearby mux pane
---@param at_edge boolean
---@return boolean
local function back_to_mux(at_edge)
    if N.config.disable_on_zoom and N.config.mux:zoomed() then
        return false
    end
    return N.last_pane or at_edge
end

---For smoothly navigating through neovim splits and mux panes
---@param direction string
function N.navigate(direction)
    -- window id before navigation
    local cur_win = A.nvim_get_current_win()

    local mux_last_pane = direction == 'p' and N.last_pane
    if not mux_last_pane then
        cmd('wincmd ' .. direction)
    end

    -- After navigation, if the old window and new window matches
    local at_edge = cur_win == A.nvim_get_current_win()

    -- then we can assume that we hit the edge
    -- there is mux pane besided the edge
    -- So we can navigate to the mux pane
    if back_to_mux(at_edge) then
        N.config.mux:navigate(direction)
        maybe_auto_save()
        N.last_pane = true
    else
        N.last_pane = false
    end
end

---For smoothly navigating through neovim tabpages and tmux windows
---@param direction string
function N.navi_tab(direction)
    -- tab nvaivation wraps around in neovim, so we need to check at edge before actually acting
    -- `nvim_list_tabpages` returns tab handles that are not the same as gettabinfo, which is used by bufferline
    local tabs = F.gettabinfo()
    local curr_tab = F.tabpagenr()
    local at_edge = (curr_tab == tabs[1].tabnr and direction == 'p')
                    or (curr_tab == tabs[#tabs].tabnr and direction == 'n')

    local tmux_last_pane = direction == 'l' and N.last_pane
    if not at_edge and not tmux_last_pane then
        tabcmd(direction)
        return
    end

    -- go to tmux instead
    if back_to_mux(at_edge) then
        N.config.mux:change_window(direction)
        maybe_auto_save()
        N.last_pane = true
    else
        N.last_pane = false
    end
end

return N
