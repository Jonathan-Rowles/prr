# prr

`prr` is a Neovim plugin that integrates with the GitHub CLI (`gh`) and [Diffview.nvim](https://github.com/sindrets/diffview.nvim) to streamline common GitHub and Git workflows directly in your editor.

This plugin provides a collection of commands and features, including pull request management, branch diffing, PR approval/merging, and PR creation with floating window input.

---

## Installation

### Requirements

- [GitHub CLI (`gh`)](https://cli.github.com/) installed and authenticated.
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [Diffview.nvim](https://github.com/sindrets/diffview.nvim)

### Using `lazy.nvim`

```lua
{
    "Jonathan-Rowles/prr", -- Update with the actual location of the plugin
    dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-telescope/telescope.nvim",
        "sindrets/diffview.nvim",
    },
    config = function()
        require("gh-cli").setup()
    end,
    event = "VeryLazy",
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
| `<leader>dv`        | Open a Diffview comparing the selected branch to the HEAD.  `pick_branc_diff`                               |
| `<leader>pa`        | Approve and squash-merge the current PR. `approve_pr`                                                       |
| `<leader>pc`        | Open the files tab of the current PR in your default web browser. `open_github_pr_files_changed`            |
| `<leader>pb`        | Create a new PR using floating window prompts for title and body. `create_pr`                               |

---

## Usage

### Fetch and View Open Pull Requests

Press `<leader>pr` to list all open pull requests using Telescope. Selecting a PR will:

1. Open a diff view comparing the default branch to the PR branch.
2. Open a new tab with inline comments and conversation-level comments from the PR.

### Diffview Between Branches

Press `<leader>dv` to open a Diffview session. Use Telescope to pick a branch and compare it with the current `HEAD`.

### Approve and Merge a PR

Press `<leader>pa` to approve the current PR and squash-merge it. The GitHub CLI handles this process, and you will be notified of the result.

### Open Files Tab of a PR in the Browser

Press `<leader>pc` to open the files tab of the current PR in your default web browser.

### Create a New Pull Request

Press `<leader>pb` to open a floating window for entering the title and body of a new PR. Once the PR is created, the plugin will open its URL in your browser.

---

## Configuration

By default, the plugin does not require any additional configuration. However, you can customize it further by editing the keybindings or functions directly in your Neovim config.

To override a keybinding, simply map it to the desired function:

```lua
vim.keymap.set('n', '<custom-key>', require('gh-cli').function_name, { silent = true, noremap = true })
