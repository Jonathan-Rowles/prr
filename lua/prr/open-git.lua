local utilz = require('prr.utilz')

local M = {}

function M.open_github()
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

    utilz.open_url(url)
end

return M
