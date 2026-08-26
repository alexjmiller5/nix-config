{ config, pkgs, lib, ... }:

# Zsh, fully nix-managed. Ported 1:1 from the pre-nix ~/.config/zsh setup
# (ZDOTDIR layout preserved via dotDir). Aliases live in home/aliases/*.nix
# (categorized; hosts import the categories they want); functions stay plain
# zsh in home/zsh/functions.zsh. The old custom PS1 is replaced by starship.
{
  programs.zsh = {
    enable = true;
    # XDG layout (the original pre-nix ZDOTDIR setup, and home-manager's
    # default from stateVersion 26.05): zsh dotfiles live in ~/.config/zsh,
    # keeping $HOME clean. hm generates the ZDOTDIR bootstrap.
    dotDir = "${config.xdg.configHome}/zsh";
    # Typing a directory path as a command cd's into it: `..`, `../../..`,
    # `../some-folder/deeper`, bare subdir names — all work without `cd`.
    autocd = true;

    enableCompletion = true;
    completionInit = ''
      autoload -Uz compinit
      compinit -d "$HOME/.config/zsh/.zcompdump"
    '';

    history = {
      path = "$HOME/.config/zsh/.zsh_history";
      size = 50000;
      save = 50000;
    };

    # Goes to .zshenv (read by every shell, incl. non-interactive).
    envExtra = ''
      # uv-installed tools
      export PATH="$HOME/.local/bin:$PATH"
    '';

    initContent = ''
      # --- PATH stack ---
      export PATH="$PATH:/Applications/Docker.app/Contents/Resources/bin/"

      # Homebrew env + its zsh completions
      if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        fpath=($HOMEBREW_PREFIX/share/zsh/site-functions $fpath)
      fi
      # Nix profiles ahead of brew shellenv's prepend: declared packages must
      # shadow same-named brew formulae (e.g. node, riding in as a dep of
      # `skills`, would otherwise win over pkgs.nodejs).
      export PATH="/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH"

      # ($EDITOR comes from programs.neovim.defaultEditor in cli-tools.nix)

      # macOS-style arrow navigation (Ghostty sends opt+arrows as alt+arrows and,
      # via keybinds in its config, cmd+arrows as Home/End/Ctrl+Home/Ctrl+End)
      bindkey '^[[1;3D' backward-word     # opt+left
      bindkey '^[[1;3C' forward-word      # opt+right
      bindkey '^[[H' beginning-of-line    # cmd+left (Home)
      bindkey '^[[F' end-of-line          # cmd+right (End)
      bindkey '^[[1;5H' redisplay         # cmd+up: no-op in shell
      bindkey '^[[1;5F' redisplay         # cmd+down: no-op in shell

      # 1Password as the default ssh authenticator (guarded: the desktop app —
      # and thus the socket — only exists on machines with a GUI 1Password)
      _op_sock="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
      [[ -S "$_op_sock" ]] && export SSH_AUTH_SOCK="$_op_sock"
      unset _op_sock

      # Make sure secrets aren't saved to .zsh_history; zsh hook, not a function
      zshaddhistory() {
          local line="''${1%%$'\n'}"
          local secrets="export|KEY|SECRET|TOKEN|PASSWORD"
          if [[ "$line" =~ "$secrets" ]]; then
              return 1
          fi
          return 0
      }

      # gh/gcloud op auth: PATH-level wrappers (scripts.nix / macbook-air.nix)
      # inject tokens via op read in EVERY context — the old interactive-only
      # `op plugin run` aliases (~/.config/op/plugins.sh) are retired.

      # Agent-shell detection: AGENT_SHELL is the agent-agnostic seam - every
      # per-agent env var maps to it here, and everything downstream gates on
      # AGENT_SHELL only. Adding a new agent CLI = one more detection line.
      # (Headless op auth lives elsewhere: shell-init.sh exports the SA token
      # before every Claude Bash call, and the gh/gcloud/gog/modal PATH
      # wrappers self-inject via agent-op-env.sh - a zshrc export can't do it,
      # since env vars set here never survive into agent Bash calls.)
      if [[ -n $CLAUDECODE || -n $CLAUDE_CODE_ENTRYPOINT ]]; then
          export AGENT_SHELL=claude
      fi

      # Agent shells: SA-authed op can't reach the Personal vault; op-personal
      # strips the token and uses desktop auth (one Touch ID per call).
      if [[ -n $AGENT_SHELL ]]; then
          op-personal() {
              env -u OP_SERVICE_ACCOUNT_TOKEN sh -c \
                  'op signin --account my.1password.com >/dev/null 2>&1; exec op "$@"' sh "$@"
          }
      fi

      # Per-call agent env (Claude Code sources this before every Bash call;
      # env vars don't survive between calls, functions/aliases do). The file
      # lives in agent-config: claude/shell-init.sh - env exports ONLY.
      export CLAUDE_ENV_FILE="$HOME/.claude/shell-init.sh"

      # Shell functions (plain zsh, edited in the repo)
      source ${./zsh/functions.zsh}

      # zsh autosuggestions — sourced explicitly (not via the HM option) so the
      # custom Tab widget below is guaranteed to register AFTER the plugin loads.
      source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh
      # Tab accepts the suggestion when one is visible, otherwise completes as normal
      tab-accept-or-complete() {
          if [[ -n $POSTDISPLAY ]]; then
              zle autosuggest-accept
          else
              zle expand-or-complete
          fi
      }
      zle -N tab-accept-or-complete
      # Plugin wrappers unset POSTDISPLAY before running the widget, so keep ours unwrapped
      ZSH_AUTOSUGGEST_IGNORE_WIDGETS+=(tab-accept-or-complete)
      bindkey '^I' tab-accept-or-complete
    '';
  };

  # fzf with shell integration: ctrl-R fuzzy history, ctrl-T file picker,
  # alt-C fuzzy cd (the package alone wires none of these).
  programs.fzf.enable = true;

  # Prompt: starship, configured to match the old custom PS1
  # (path in blue, git branch in magenta, green ✔ / red ✖, bold ❯;
  # user@host appears automatically only over SSH — starship's default).
  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      format = "$username$hostname$directory$git_branch$character";
      directory = {
        style = "blue";
        truncation_length = 0;
        truncate_to_repo = false;
      };
      git_branch = {
        # symbol left at starship's default (the branch glyph)
        format = "[$symbol$branch]($style) ";
        # starship's name for magenta is "purple" — "magenta" is silently ignored
        style = "purple";
      };
      character = {
        success_symbol = "[✔](green) [❯](bold)";
        error_symbol = "[✖](red) [❯](bold)";
      };
    };
  };
}
