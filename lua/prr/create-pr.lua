local Job = require('plenary.job')
local utilz = require('prr.utilz')

local M = {}

local function input_in_floating_win(prompt, on_done, initial_text)
    local prompt_buf    = vim.api.nvim_create_buf(false, true)
    local input_buf     = vim.api.nvim_create_buf(false, true)

    local total_width   = math.floor(vim.o.columns * 0.6)
    local prompt_height = 5
    local input_height  = 15
    local total_height  = prompt_height + input_height

    local row           = math.floor((vim.o.lines - total_height) / 2)
    local col           = math.floor((vim.o.columns - total_width) / 2)

    vim.api.nvim_open_win(prompt_buf, false, {
        relative = 'editor',
        style    = 'minimal',
        border   = 'single',
        row      = row,
        col      = col,
        width    = total_width,
        height   = prompt_height,
    })

    local prompt_lines = {
        ("=== %s ==="):format(prompt),
        "Type your text in the bottom window.",
        "Press <leader>c to confirm, or 'q' to cancel.",
    }
    vim.api.nvim_buf_set_lines(prompt_buf, 0, -1, false, prompt_lines)
    vim.bo[prompt_buf].bufhidden = "wipe"
    vim.bo[prompt_buf].filetype  = "markdown"

    vim.api.nvim_buf_set_keymap(
        prompt_buf,
        'n',
        'q',
        '<cmd>lua vim.api.nvim_win_close(0, true)<CR>',
        { noremap = true, silent = true }
    )

    local input_win = vim.api.nvim_open_win(input_buf, true, {
        relative = 'editor',
        style    = 'minimal',
        border   = 'single',
        row      = row + prompt_height,
        col      = col,
        width    = total_width,
        height   = input_height,
    })

    vim.bo[input_buf].filetype = "markdown"
    if initial_text then
        local lines = {}
        for line in initial_text:gmatch("([^\n]+)") do
            table.insert(lines, line)
        end
        vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, lines)
    end

    local function commit_input(b)
        if vim.api.nvim_buf_is_loaded(b) then
            local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
            local text  = table.concat(lines, "\n")
            if vim.api.nvim_win_is_valid(input_win) then
                vim.api.nvim_win_close(input_win, true)
            end
            for _, win_id in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
                local wbuf = vim.api.nvim_win_get_buf(win_id)
                if wbuf == prompt_buf and vim.api.nvim_win_is_valid(win_id) then
                    vim.api.nvim_win_close(win_id, true)
                end
            end
            if on_done then
                on_done(text)
            end
        end
    end

    vim.keymap.set('n', '<leader>c', function()
        commit_input(input_buf)
    end, { buffer = input_buf, noremap = true, silent = true })

    vim.keymap.set('n', 'q', function()
        if vim.api.nvim_win_is_valid(input_win) then
            vim.api.nvim_win_close(input_win, true)
        end
        for _, win_id in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            local wbuf = vim.api.nvim_win_get_buf(win_id)
            if wbuf == prompt_buf and vim.api.nvim_win_is_valid(win_id) then
                vim.api.nvim_win_close(win_id, true)
            end
        end
    end, { buffer = input_buf, noremap = true, silent = true })
end

function M.create_pr()
    input_in_floating_win("Enter PR Title", function(title)
        local pr_template = nil
        local git_root = vim.fn.trim(vim.fn.system("git rev-parse --show-toplevel"))
        if git_root ~= "" and vim.fn.isdirectory(git_root) == 1 then
            local template_path = git_root .. "/.github/PULL_REQUEST_TEMPLATE.md"
            if vim.fn.filereadable(template_path) == 1 then
                pr_template = table.concat(vim.fn.readfile(template_path), "\n")
            end
        end
        input_in_floating_win("Enter PR Body", function(body)
            Job
                :new({
                    command = 'gh',
                    args = { 'pr', 'create', '--title', title, '--body', body },
                    on_exit = function(j, return_val)
                        if return_val == 0 then
                            local result = j:result()
                            local output_str = table.concat(result, '\n')
                            local pr_url = output_str:match("(https://github%.com/%S+)")
                            if pr_url then
                                vim.schedule(function()
                                    utilz.open_url(pr_url)
                                end)
                            else
                                print("Could not find PR URL in gh output:\n" .. output_str)
                            end
                        else
                            print("Failed to create PR. Return value: " .. return_val)
                        end
                    end,
                })
                :sync()
        end, pr_template)
    end)
end

return M
