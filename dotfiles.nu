use std

const DOTFILES_CONFIG = "dotfiles.yaml"
const DOTFILES_DIR_PATH = "dotfiles"

def when [
  cond: bool,
  filter: closure
] : any -> any {
  let input = $in
  $input | if $cond {
    do $filter $input
  } else { }
}

def is-executable [] : string -> bool {
  (which $in | length) > 0
}

def is-symlink [] : string -> bool {
  ($in | path type) == "symlink"
}

def get-symlink-target [] : string -> string {
  $in | path expand
}

def get-symlink-target-type [] : string -> string {
  $in | get-symlink-target | path type
}

def get-host-name [] {
  (sys).host.name
}

def is-windows [] : nothing -> bool {
  (get-host-name) == "Windows"
}

def remove-file-dir-symlink [
] : string -> nothing {
  let path = $in | path expand -n

  match ($path | path type) {
    "dir" => { rm -r $path },
    _ => { rm $path }
  }
}

def assert-valid-entry-name [] : string -> nothing {
  let name = $in
  std assert ($name =~ "^[-a-zA-Z_:.]+$" ) "Invalid entry name"
}

def create-dir-symlink [dest: string] : string -> nothing {
  let target = $in | path expand -n

  mkdir ($dest | path dirname)
  
  if ("ln" | is-executable) {
    run-external "ln" "-s" $target $dest
  } else if ((is-windows) or ("mklink" | is-executable)) {
    mklink "/D" $dest $target
  } else {
    error make {
      msg: "Cannot create symlink. ln or mklink command required."
    }
  }
}

def create-file-symlink [dest: string] : string -> nothing {
  let target = $in | path expand -n

  mkdir ($dest | path dirname)
  
  if ("ln" | is-executable) {
    run-external "ln" "-s" $target $dest
  } else if ((is-windows) or ("mklink" | is-executable)) {
    mklink $dest $target
  } else {
    error make {
      msg: "Cannot create symlink. ln or mklink command required."
    }
  }
}

def overwrite [
  callback: closure
] : string -> nothing {
  let path = $in
  $path | remove-file-dir-symlink
  $path | do $callback $path
}

def prompt-overwrite [
] : string -> boolean {
  let path = $in
  let answer = (["yes", "no"] | input list $"($path) already exists. Do you want to overwrite?");
  $answer == "yes"
}

def try-write [
  callback: closure,
  --force
] : string -> bool {
  let path = $in

  if ($path | path exists) {
    if (($path | prompt-overwrite) or ($force)) {
      $path | overwrite $callback
      true
    } else {
      print "Cancelled."
      false
    }
  } else {
    $path | do $callback $path
    true
  }
}

def create-default-config [
] {
  {
    entries: {
    }
  }
}

def has-config [] : nothing -> bool {
  ($DOTFILES_CONFIG | path expand | path type) == "file"
}

def load-config [] : nothing -> record {
  open $DOTFILES_CONFIG
}

def save-config [
  --force(-f)
] : table -> nothing {
  $in | save --force=($force) $DOTFILES_CONFIG
}

def assert-has-config [] {
  if not (has-config) {
    error make {
      msg: "Config file doesn't exist. Please run \"dotfiles init\" first."
    }
  }
}

def create-empty-entry-stuff [
  name: string,
  type: string
] : string -> nothing {
  match ($type) {
    "file" => {
      touch ($name | get-entry-files-path)
    },
    "dir" => {
      mkdir ($name | get-entry-files-path)
    }
  }
}

def import-entry-stuff [
  name: string
] : string -> nothing {
  let path = $in
  cp -r $path ($name | get-entry-files-path)
}

def remove-entry-stuff [
  name: string
] : string -> nothing {
  ($name | get-entry-files-path) | remove-file-dir-symlink
}

def has-entry [
  name: string
] : record -> bool { 
  let entry = $in
    | get entries
    | get -i $name
  $entry != null
}

def assert-has-entry [
  name: string
] : record -> nothing {
  let config = $in
  if not ($config | has-entry $name) {
    error make {
      msg: $"Missing entry: ($name)"
    }
  }
}

def get-entry [
  name: string
] : record -> record {
  $in
    | get entries
    | get $name
}

def create-file-entry [
  type: string
] {
  {
    type: $type,
    path: {}
  }
}

def add-entry [
  name: string,
  entry: record
] : record -> record {
  $in | update entries {
    insert $name $entry
  }
}

def remove-entry [
  name: string
] : record -> record {
  $in | update entries {
    reject $name
  }
}

def upsert-path [
  name: string,
  platform: string,
  path: string
] : recrod -> record {
  $in | update entries {
    update $name {
      update path {
        upsert $platform $path
      }
    }
  }
}

def get-entry-files-path [
] : string -> string {
  let name = $in
  $DOTFILES_DIR_PATH | path join $name
}

def is-entry-installed [
  name: string
] : record -> bool {
  let entry = $in
  let type = $entry.type
  let path = $entry.path | get (get-host-name) | path expand -n
  let entry_files_path = $name | get-entry-files-path | path expand -n

  ($path | is-symlink) and (
    ($path | get-symlink-target) == $entry_files_path) and (
    ($path | get-symlink-target-type) == $type)
}

def install-entry [
  name: string,
  --force
] : record -> nothing {
  let entry = $in
  let type = $entry.type
  let path = $entry.path | get -i (get-host-name) | path expand -n
  if ($path == null) { return }
  let entry_files_path = $name | get-entry-files-path
  
  if ($entry | is-entry-installed $name) {
    print $"($name) is already installed."
    return
  }

  print $"Installing ($name)..."

  let result = match ($type) {
    "file" => {
      $path | try-write --force=$force {|path|
        $entry_files_path | create-file-symlink $path
      }
    },
    "dir" => {
      $path | try-write --force=$force {|path|
        $entry_files_path | create-dir-symlink $path
      }
    }
  }

  if not ($result) {
    print $"Installing ($name) failed."
  }
}

def uninstall-entry [
  name: string,
] : record -> nothing {
  let entry = $in
  let path = $entry | get path | get -i (get-host-name) | path expand -n
  if ($path == null) { return }
  
  if ($entry | is-entry-installed $name) {
    print $"Uninstalling ($name)..."
    rm $path
  } else {
    print $"($name) is not installed yet."
  }
}

# Initialize dotfile directory.
#
# Example:
#   > dotfiles init
export def "dotfiles init" [
  --force(-f)
] {
  let result = $DOTFILES_CONFIG | try-write --force=$force {|path|
    create-default-config | save $path
  }
  if not ($result) {
    print "Cannot create config file."
  }

  let result = $DOTFILES_DIR_PATH | try-write --force=$force {|path|
    mkdir $DOTFILES_DIR_PATH
  }
  if not ($result) {
    print "Cannot create dotfiles directory."
  }
}

export def "dotfiles ls" [] {
  assert-has-config

  load-config
    | get entries
    | items {|key, value|
      let platforms = $value | get path | columns
      let content_path = $key | get-entry-files-path
      {
        name: $key,
        platforms: $platforms,
        content_path: $content_path
      }
    }
}

export def "dotfiles status" [] {
  assert-has-config

  load-config
    | get entries
    | items {|key, value|
      let supported = (get-host-name) in ($value | get path | columns)
      let installed = if ($supported) { $value | is-entry-installed $key } else { false }

      {
        name: $key,
        installed: $installed,
        supported: $supported
      }
    }
}

export def "dotfiles import" [
  path: string,
  --name(-n): string,
  --config-path(-c): string,
  --force(-f)
] {
  assert-has-config

  let config = load-config
  let path_metadata = metadata $path
  let resolved_path = $path | path expand
  let name = $name | default ($resolved_path | path basename)
  $name | assert-valid-entry-name
  let config_path = $config_path | default $path

  if (($config | has-entry $name) and (not $force)) {
    error make {
      msg: $"The entry ($name) already exists."
    }
  }

  print $resolved_path
  match ($resolved_path | path type) {
    "file" => {
      $resolved_path | import-entry-stuff $name
      $config
        | add-entry $name (create-file-entry "file")
        | upsert-path $name (get-host-name) $config_path
        | save-config -f
    },
    "dir" => {
      $resolved_path | import-entry-stuff $name
      $config
        | add-entry $name (create-file-entry "dir")
        | upsert-path $name (get-host-name) $config_path
        | save-config -f
    },
    _ => {
      error make {
        msg: $"Invalid path.",
        label: {
          text: $"This path must be a file or directory.",
          span: $path_metadata.span
        }
      } 
    }
  }

  print $"($name) imported successfully."
}

export def "dotfiles new file" [
  name: string,
  --path(-p): string,
  --platform(-P): string,
  --ignore-error(-i)
] {
  assert-has-config
  $name | assert-valid-entry-name

  let config = load-config
  if ($config | has-entry $name) {
    if (not $ignore_error) {
      error make {
        msg: $"The entry ($name) already exists."
      }
    }
    return
  }

  create-empty-entry-stuff $name "file"
  $config
    | add-entry $name (create-file-entry "file")
    | when ($path != null) { upsert-path $name ($platform | default (get-host-name)) $path }
    | save-config -f
}

export def "dotfiles new dir" [
  name: string,
  --path(-p): string,
  --platform(-P): string,
  --ignore-error(-i)
] {
  assert-has-config
  $name | assert-valid-entry-name

  let config = load-config
  if ($config | has-entry $name) {
    if (not $ignore_error) {
      error make {
        msg: $"The entry ($name) already exists."
      }
    }
    return
  }

  create-empty-entry-stuff $name "dir"
  $config
    | add-entry $name (create-file-entry "dir")
    | when ($path != null) { upsert-path $name ($platform | default (get-host-name)) $path }
    | save-config -f
}

export def "dotfiles remove" [
  name: string
] {
  assert-has-config
  $name | assert-valid-entry-name

  let config = load-config
  $config | assert-has-entry $name

  remove-entry-stuff $name
  $config
    | remove-entry $name
    | save-config -f
    
  print $"The entry ($name) was removed successfully."
}

export def "dotfiles set path" [
  name: string,
  path: string,
  --platform(-P): string
] {
  assert-has-config

  let config = load-config
  $config | assert-has-entry $name

  let platform = $platform | default (get-host-name)
  
  $config
    | upsert-path $name $platform $path
    | save-config -f
}

export def "dotfiles install" [
  --force(-f)
] {
  assert-has-config

  let config = load-config

  $config
    | get entries
    | items {|key, value|
      $value | install-entry $key --force=$force
    }
    
  print $"Dotfiles installed successfully."
}

export def "dotfiles uninstall" [] {
  assert-has-config

  let config = load-config

  $config
    | get entries
    | items {|key, value|
      $value | uninstall-entry $key
    }
    
  print $"Dotfiles uninstalled successfully."
}

# Run dotfiles init, ls, status, install or uninstall
# This is the shorthand of
# > use dotfiles.nu "dotfiles init"; dotfiles init;
# and so on.
def main [
  task: string # The task name to run: init, ls, status, install or uninstall
  --force(-f)
] {
  match ($task) {
    "init" => { dotfiles init --force=$force },
    "install" => { dotfiles install --force=$force },
    "uninstall" => { dotfiles uninstall },
    "ls" => { dotfiles ls },
    "status" => { dotfiles status },
    _ => {
      print "Unrecognized task."
    }
  }
}