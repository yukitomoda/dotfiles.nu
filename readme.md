# dotfiles.nu

A simple nu script for managing dotfiles.

## Usage

0. `use dotfiles.nu *`
1. `dotfiles init`
2. `dotfiles import` to import config file or directory. Or you can also `dotfiles new file`, `dotfiles new dir` to add empty config file or directory.
3. `dotfiles set path` to set config path for another platform if you want.
4. `dotfiles install` to install all entries in dotfiles.yaml. (*required privileges* on Windows)

## Example

```nu
# First, on Windows...
use dotfiles.nu *

dotfiles init
# Import Nushell configuration folder
# Copy the folder into current working directory, then add an entry to the config file (dotfiles.yaml).
dotfiles import nushell ~\AppData\Roaming\nushell
```

```nu
# Next, for another platform...

# Set the Nushell's configuration directory path on Ubuntu in the config file.
# Now we have the configuration paths for Windows and Ubuntu.
dotfiles set path nushell ~/.config/nushell/config.nu
```

```nu
# Install all the entries in config file to current platform.
dotfiles install

# or this is shorthand for that
nu dotfiles.nu install
```

## known issue

- `dotfiles install` fails when broken symlink already exists at config path.
