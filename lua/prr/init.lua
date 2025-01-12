local utilz = require('prr.utilz')
local create = require('prr.create-pr')
local dv = require('prr.diff')
local open = require('prr.open-git')
local review = require('prr.review-pr')

local M = {}

function M.setup()
    utilz.keymap('n', '<leader>pc', open.open_github, { silent = true, noremap = true })

    utilz.keymap('n', '<leader>dv', dv.diff, { silent = true, noremap = true })

    utilz.keymap('n', '<leader>pr', review.review_pr, { silent = true, noremap = true })

    utilz.keymap('n', '<leader>pb', create.create_pr, { silent = true, noremap = true })
end

return M
