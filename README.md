# cmp-git

Git source for [hrsh7th/nvim-cmp](https://github.com/hrsh7th/nvim-cmp)

- `#` to trigger `issues` completion
- `@` to trigger `mentions` (contributors) completion

## Installation

### Dependencies

- git
- curl
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [GitHub CLI](https://cli.github.com/) (optional, will use curl instead if not avaliable)

### GitHub Private Repository

- `curl`: Generate a personal token with `repo` scope in
  [settings](https://github.com/settings/tokens) and set `GITHUB_API_TOKEN`
  environment variable.
- `GitHub CLI`: Run [gh auth login](https://cli.github.com/manual/gh_auth_login)

[vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'nvim-lua/plenary.nvim'
Plug 'petertriho/cmp-git'
```

[packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use("petertriho/cmp-git", requires = "nvim-lua/plenary.nvim")
```

## Setup

```lua
require("cmp-git").setup({
  -- defaults
  filetypes = { "gitcommit" },
  github = {
      issues = {
          filter = "all", -- assigned, created, mentioned, subscribed, all, repos
          limit = 100,
          state = "open", -- open, closed, all
      },
      mentions = {
          limit = 100,
      },
  },
})
```

## Acknowledgements

Special thanks to [tjdevries](https://github.com/tjdevries) for their informative video and starting code.

- [TakeTuesday E01: nvim-cmp](https://www.youtube.com/watch?v=_DnmphIwnjo)
- [tjdevries/config_manager](https://github.com/tjdevries/config_manager)

## Alternatives

- [neoclide/coc-git](https://github.com/neoclide/coc-git)

## License

[MIT](https://choosealicense.com/licenses/mit/)
