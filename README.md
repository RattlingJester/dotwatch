# dotwatch
A simple tool built in Zig 0.17 for my own needs to track dotfiles and append them to the git repo.
It monitors targeted files and directories, tracking changes using filesystem modification timestamps and copies them to a specified repo, automatically commiting all the changes.

## Configuration
`dotwatch` reads its tracking state from a central configuration file. The file enforces explicit layout sections. All three components (`repo`, `tracked`, and `config`) are required.
## Example config
```toml
# Destination repo
repo = "/home/user/clones/dotfiles"

# Array of files/dirs to track
tracked = [
  "/home/user/.config/helix"
  "/home/user/.config/starship.toml"
]

[config]
# Files/dirs matching this patterns are skipped
ignore_files = [
  "*.db"
  "secret.txt"
]
```

# Building
```zig build``` to build
```zig build run``` to build and run the app

# Dependencies
Uses `libgit2` to interact with git repo and zig standard library.
