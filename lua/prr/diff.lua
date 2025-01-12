local actions = require('telescope.actions')
local telescope_builtin = require('telescope.builtin')
local action_state = require('telescope.actions.state')

local M = {}

function M.diff()
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

return M
