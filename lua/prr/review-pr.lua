local utilz = require('prr.utilz')
local action_state = require('telescope.actions.state')
local previewers = require('telescope.previewers')
local conf = require('telescope.config').values
local Job = require('plenary.job')
local actions = require('telescope.actions')
local finders = require('telescope.finders')
local pickers = require('telescope.pickers')

local M = {}

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

utilz.keymap('n', '<leader>pa', approve_pr, { noremap = true, silent = true })

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

function M.review_pr()
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

return M
