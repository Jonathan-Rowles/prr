# PRR

`prr` is a Neovim plugin that integrates with the GitHub CLI (`gh`) and [Diffview.nvim](https://github.com/sindrets/diffview.nvim) 

This plugin provides a collection of commands and features, including pull request management, branch diffing, PR approval/merging, and PR creation with floating window input.

---

## Installation

### Requirements

- [GitHub CLI (`gh`)](https://cli.github.com/)  installed and authenticated.
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [Diffview.nvim](https://github.com/sindrets/diffview.nvim)

### Using `lazy.nvim`

```lua
{
    "Jonathan-Rowles/prr",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-telescope/telescope.nvim",
        "sindrets/diffview.nvim",
    },
    config = function()
        require("prr").setup()
    end
}
```

## Features

- Open a diff view between the default branch and a target branch.
- Fetch and view open PRs, with details and inline comments.
- Approve and squash-merge PRs directly from Neovim.
- Create new PRs using a floating window for input.
- Open the files tab of a PR in your browser.

---

## Keybindings

Below are the default keybindings provided by the plugin. These can be customized if needed by directly mapping the plugin functions.

| **Keybinding**      |  **Action**                                                                                                 |
|---------------------|-------------------------------------------------------------------------------------------------------------|
| `<leader>pr`        | Fetch and list open PRs in Telescope. Select one to view its diff and comments. `pick_branch_with_open_pr()`|
| `<leader>dv`        | Open a Diffview comparing the selected branch to the HEAD.  `pick_branch_diff`                               |
| `<leader>pa`        | Approve and squash-merge the current PR. `approve_pr`                                                       |
| `<leader>pc`        | Open the files tab of the current PR in your default web browser. `open_github_pr_files_changed`            |
| `<leader>pb`        | Create a new PR using floating window prompts for title and body. `create_pr`                               |

