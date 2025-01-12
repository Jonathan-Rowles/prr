local M = {}

---@param url string
function M.open_url(url)
    local is_mac = (vim.fn.has("macunix") == 1)
    local is_win = (vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1)
    local is_wsl = (vim.fn.has("wsl") == 1)

    if is_mac then
        vim.fn.jobstart({ "open", url })
    elseif is_wsl then
        vim.fn.jobstart({ "cmd.exe", "/C", "start", url })
    elseif is_win then
        vim.fn.jobstart({ "start", url })
    else
        vim.fn.jobstart({ "xdg-open", url })
    end
end

function M.keymap(mode, lhs, rhs, opts)
    vim.keymap.set(mode, lhs, rhs, opts or {})
end

return M
