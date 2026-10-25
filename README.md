# dotwatch
A simple tool built in Zig 0.17 for my own needs to track dotfiles and append them to the git repo.
It monitors targeted files and directories (ignoring symlinks), tracking changes using filesystem modification timestamps and copies them to a specified repo, automatically commiting all the changes.

## Configuration
`dotwatch` reads its tracking state from a central configuration file. The file enforces explicit layout sections. All three components (`repo`, `tracked`, and `config`) are required.

## Example config
```zon
.{
    // Array of files/dirs to track
    .tracked = .{
        "/home/user/.config/fish",
        "/home/user/.config/helix",
        "/home/user/.config/lazygit",
        "/home/user/.config/yazi",
        "/home/user/.config/starship.toml",
    },

    // Destination repo
    .repo = "/home/user/Github/dotfiles",
    
    // Files matching this patterns are skipped
    .ignore = .{
        "*.db",
    },
}
```

# Building
```zig build``` to build
```zig build run``` to build and run the app

# Dependencies
Uses `libgit2` to interact with git repo and zig standard library.
