local M = {}

function M.setup()
    local actions = require('telescope.actions')
    local action_state = require('telescope.actions.state')
    local Job = require('plenary.job')
    local telescope_builtin = require('telescope.builtin')
    local pickers = require('telescope.pickers')
    local finders = require('telescope.finders')
    local previewers = require('telescope.previewers')
    local conf = require('telescope.config').values

    local function keymap(mode, lhs, rhs, opts)
        vim.keymap.set(mode, lhs, rhs, opts or {})
    end

    local function get_default_branch_from_gh()
        local default_branch = nil
        Job:new({
            command = 'gh',
            args = { 'repo', 'view', '--json', 'defaultBranchRef', '--jq', '.defaultBranchRef.name' },
            on_exit = function(j, return_val)
                if return_val == 0 then
                    default_branch = table.concat(j:result(), '')
                end
            end,
        }):sync()

        return default_branch or "main"
    end

    local function open_diffview_for_branch(branch)
        local default_branch = get_default_branch_from_gh()
        vim.cmd("DiffviewClose")
        vim.cmd(string.format("DiffviewOpen origin/%s...origin/%s", default_branch, branch))
    end

    local function git_diff_to_quickfix(branch)
        vim.cmd(string.format("Git checkout %s", branch))
        local default_branch = get_default_branch_from_gh()

        local diff_output = vim.fn.systemlist(string.format("git diff origin/%s...origin/%s --name-only",
            default_branch, branch))

        local qf_list = {}
        for _, file in ipairs(diff_output) do
            table.insert(qf_list, { filename = file })
        end

        vim.fn.setqflist(qf_list)

        open_diffview_for_branch(branch)
    end

    local function get_branches_with_open_prs()
        local results = {}

        local has_changes = false
        Job:new({
            command = 'git',
            args = { 'status', '--porcelain' },
            on_exit = function(j, _)
                local output = table.concat(j:result(), '\n')
                if output ~= '' then
                    has_changes = true
                end
            end,
        }):sync()

        if has_changes then
            vim.notify(
                "Unstaged or uncommitted changes detected. Please commit or stash your changes before proceeding.",
                vim.log.levels.ERROR)
            return results
        end

        local git_root = nil
        Job:new({
            command = 'git',
            args = { 'rev-parse', '--show-toplevel' },
            on_exit = function(j, return_val)
                if return_val == 0 then
                    git_root = table.concat(j:result(), '')
                end
            end,
        }):sync()

        vim.cmd('lcd ' .. git_root)

        Job:new({ command = 'git', args = { 'fetch' } }):sync()
        Job:new({ command = 'git', args = { 'pull' } }):sync()

        Job:new({
            command = 'gh',
            args = { 'pr', 'list', '--json', 'title,body,headRefName,author,createdAt', '--limit', '100' },
            on_exit = function(j, return_val)
                if return_val == 0 then
                    local output = table.concat(j:result(), '')
                    local pr_data = vim.json.decode(output)
                    for _, pr in ipairs(pr_data) do
                        table.insert(results, {
                            branch = pr.headRefName or "unknown",
                            title = pr.title or "No Title",
                            body = pr.body or 'No description provided.',
                            author = pr.author and pr.author.login or 'unknown',
                            createdAt = pr.createdAt or 'unknown',
                        })
                    end
                else
                    vim.schedule(function()
                        vim.notify(
                            "Failed to fetch pull requests. Ensure GitHub CLI is installed and authenticated.",
                            vim.log.levels.ERROR
                        )
                    end)
                end
            end,
        }):sync()

        table.sort(results, function(a, b)
            return a.createdAt > b.createdAt
        end)

        return results
    end

    local function open_pr_comments_in_new_tab(branch)
        local json_output = {}

        local job = Job:new({
            command = "gh",
            args = {
                "pr", "view", branch,
                "--json", "comments,reviews",
                "--jq", "{ comments: .comments, reviews: .reviews }"
            },

            on_stdout = function(_, line)
                table.insert(json_output, line)
            end,

            on_stderr = function(_, err_line)
                vim.schedule(function()
                    vim.notify("Error fetching PR data: " .. err_line, vim.log.levels.ERROR)
                end)
            end,

            on_exit = function(j, return_val)
                if return_val ~= 0 then
                    vim.schedule(function()
                        local stderr_lines = j:stderr_result()
                        vim.notify("Failed to fetch PR data: " .. table.concat(stderr_lines, "\n"),
                            vim.log.levels.ERROR)
                    end)
                    return
                end

                vim.schedule(function()
                    local raw_json = table.concat(json_output, "\n")
                    local decoded = vim.json.decode(raw_json)

                    if not decoded then
                        vim.notify("No comments found for PR: " .. branch, vim.log.levels.INFO)
                        return
                    end

                    local conversation_comments = decoded.comments or {}
                    local file_threads = decoded.reviewThreads or {}

                    local lines = {}

                    if #conversation_comments > 0 then
                        table.insert(lines, "### Conversation Comments")
                        table.insert(lines, "----------------------------------------------")
                        for _, comment in ipairs(conversation_comments) do
                            local author = (comment.author and comment.author.login) or "unknown"
                            local body = comment.body or ""
                            table.insert(lines, string.format("By: %s", author))
                            table.insert(lines, body)
                            table.insert(lines, "")
                        end
                    else
                        table.insert(lines, "No conversation-level comments found.")
                        table.insert(lines, "")
                    end

                    if #file_threads > 0 then
                        table.insert(lines, "### File-Specific (Inline) Comments")
                        table.insert(lines, "----------------------------------------------")
                        for _, thread in ipairs(file_threads) do
                            local path = thread.path or "unknown-file"
                            table.insert(lines, "File: " .. path)

                            for _, inline_comment in ipairs(thread.comments or {}) do
                                local author = (inline_comment.author and inline_comment.author.login) or
                                    "unknown"
                                local body = inline_comment.body or ""
                                table.insert(lines, string.format("  By: %s", author))
                                table.insert(lines, "  " .. body)
                                table.insert(lines, "")
                            end
                            table.insert(lines, "")
                        end
                    else
                        table.insert(lines, "No file-specific review threads found.")
                        table.insert(lines, "")
                    end

                    vim.cmd("tabnew")
                    local bufnr = vim.api.nvim_get_current_buf()
                    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
                    vim.bo[bufnr].buftype = "nofile"
                    vim.bo[bufnr].bufhidden = "wipe"
                    vim.bo[bufnr].swapfile = false
                    vim.bo[bufnr].filetype = "markdown"
                    vim.api.nvim_buf_set_name(bufnr, "Comment")
                end)
            end,
        })

        job:start()
    end

    local function pick_branch_with_open_pr()
        vim.notify(
            "Checking for open pr ...",
            vim.log.levels.INFO)
        local branches = get_branches_with_open_prs()
        if vim.tbl_isempty(branches) then
            return
        end

        pickers.new({}, {
            prompt_title = 'Pull Requests',
            finder = finders.new_table({
                results = branches,
                entry_maker = function(entry)
                    return {
                        value = entry.branch,
                        display = string.format("[%s] %s", entry.branch, entry.title),
                        ordinal = entry.branch .. " " .. entry.title,
                        author = entry.author,
                        createdAt = entry.createdAt,
                        body = entry.body,
                        title = entry.title,
                    }
                end,
            }),
            sorter = conf.generic_sorter({}),
            previewer = previewers.new_buffer_previewer({
                title = 'PR Details',
                define_preview = function(self, entry)
                    local lines = {
                        "Branch: " .. entry.value,
                        "Author: " .. entry.author,
                        "Date Opened: " .. entry.createdAt,
                        "",
                        "Title: " .. entry.title,
                        "",
                        "Description:",
                    }

                    if entry.body and entry.body ~= "" then
                        local normalized_body = entry.body:gsub("\r\n", "\n")
                        local body_lines = vim.split(normalized_body, "\n")
                        vim.list_extend(lines, body_lines)
                    else
                        table.insert(lines, "No description provided.")
                    end

                    vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)

                    vim.api.nvim_set_option_value("wrap", true, { win = self.state.winid })
                    vim.api.nvim_set_option_value("linebreak", true, { win = self.state.winid })
                end,
            }),

            attach_mappings = function(prompt_bufnr, map)
                local select_branch = function()
                    local selection = action_state.get_selected_entry()
                    if not selection then
                        vim.notify("No PR selected.", vim.log.levels.WARN)
                        return
                    end

                    actions.close(prompt_bufnr)

                    git_diff_to_quickfix(selection.value)
                    open_pr_comments_in_new_tab(selection.value)
                end

                map('i', '<CR>', select_branch)
                map('n', '<CR>', select_branch)

                return true
            end

        }):find()
    end

    keymap('n', '<leader>pr', pick_branch_with_open_pr, { silent = true, noremap = true })

    local function pick_branc_diff()
        telescope_builtin.git_branches({
            attach_mappings = function(prompt_bufnr, map)
                map('i', '<CR>', function()
                    local selection = action_state.get_selected_entry()
                    actions.close(prompt_bufnr)
                    local branch = selection.value
                    vim.cmd("DiffviewOpen " .. branch .. "...HEAD")
                end)

                map('n', '<CR>', function()
                    local selection = action_state.get_selected_entry()
                    actions.close(prompt_bufnr)
                    local branch = selection.value
                    vim.cmd("DiffviewOpen " .. branch .. "...HEAD")
                end)

                return true
            end
        })
    end

    keymap('n', '<leader>dv', pick_branc_diff,  { silent = true, noremap = true })

    local function approve_pr()
        vim.notify(
            "Starting PR approval process...",
            vim.log.levels.INFO)
        Job:new({
            command = "gh",
            args = { "pr", "review", "--approve" },
            on_exit = function(j, return_val)
                vim.schedule(function()
                    if return_val == 0 then
                        vim.notify(
                            "PR approved successfully!",
                            vim.log.levels.INFO)
                        print(table.concat(j:result(), "\n"))
                        print("Starting PR squash and merge...")
                        Job:new({
                            command = "gh",
                            args = { "pr", "merge", "--squash" },
                            on_exit = function(j_merge, merge_val)
                                vim.schedule(function()
                                    if merge_val == 0 then
                                        print(table.concat(j_merge:result(), "\n"))
                                        vim.notify(
                                            "PR merged successfully!",
                                            vim.log.levels.INFO)
                                    else
                                        vim.notify(
                                            "Merge Error: " .. table.concat(j_merge:stderr_result(), "\n"),
                                            vim.log.levels.ERROR)
                                    end
                                end)
                            end,
                        }):start()
                    else
                        vim.notify(
                            "Approval Error: " .. table.concat(j:stderr_result(), "\n"),
                            vim.log.levels.ERROR)
                    end
                end)
            end,
        }):start()
    end

    keymap('n', '<leader>pa', approve_pr, { noremap = true, silent = true })

    local function open_url(u)
        local is_mac = (vim.fn.has("macunix") == 1)
        local is_win = (vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1)
        local is_wsl = (vim.fn.has("wsl") == 1)

        if is_mac then
            vim.fn.jobstart({ "open", u })
        elseif is_wsl then
            vim.fn.jobstart({ "cmd.exe", "/C", "start", u })
        elseif is_win then
            vim.fn.jobstart({ "start", u })
        else
            vim.fn.jobstart({ "xdg-open", u })
        end
    end

    local function open_github_pr_files_changed()
        local branch = vim.fn.systemlist("git rev-parse --abbrev-ref HEAD")[1]

        local handle = io.popen("gh pr view " .. branch .. " --json number --jq '.number'")
        if not handle then
            print("Error: cannot retrieve PR number.")
            return
        end

        local pr_number = handle:read("*a")
        handle:close()

        pr_number = pr_number:gsub("%s+", "")

        if pr_number == "" then
            print("No PR found for branch '" .. branch .. "'.")
            return
        end

        local remote_url = vim.fn.systemlist("git remote get-url origin")[1] or ""
        remote_url = remote_url:gsub("%.git$", "")
        local owner, repo
        if remote_url:find("git@") then
            owner, repo = remote_url:match("git@github.com:([^/]+)/(.+)")
        else
            owner, repo = remote_url:match("github.com/?([^/]+)/([^/]+)")
        end

        if not (owner and repo) then
            print("Could not parse GitHub repository info.")
            return
        end

        local url = string.format("https://github.com/%s/%s/pull/%s/files", owner, repo, pr_number)

        open_url(url)
    end

    keymap('n', '<leader>pc', open_github_pr_files_changed, { silent = true, noremap = true })

    local function input_in_floating_win(prompt, on_done)
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

    local function create_pr()
        input_in_floating_win("Enter PR Title", function(title)
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
                                        open_url(pr_url)
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
            end)
        end)
    end

    keymap('n', '<leader>pb', create_pr, { silent = true, noremap = true })
end

return M
