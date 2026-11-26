# Source this file, then call load_operator_ssh_public_key.
# The operator SSH public key is not secret, but keep the key selection explicit.
load_operator_ssh_public_key() {
  local auto_approve="${1:-false}"
  local default_key_file="${HOME}/.ssh/chat-operator.pub"
  local key_file answer key

  [[ -r "$default_key_file" ]] || {
    printf 'ERROR: default SSH public key is missing or unreadable: %s\n' "$default_key_file" >&2
    return 1
  }

  if [[ "$auto_approve" == true ]]; then
    key_file="$default_key_file"
    printf 'Using the default operator public key due to -y: %s\n' "$default_key_file"
  else
    printf 'Use the default operator public key at %s? [Y/n] ' "$default_key_file"
    IFS= read -r answer || return 1
    case "$answer" in
      ""|y|Y|yes|YES|Yes)
        key_file="$default_key_file"
        ;;
      n|N|no|NO|No)
        printf 'Alternate public-key file path: '
        IFS= read -r key_file || return 1
        [[ -n "$key_file" ]] || {
          printf 'ERROR: alternate public-key path was empty\n' >&2
          return 1
        }
        case "$key_file" in
          "~") key_file="$HOME" ;;
          "~/"*) key_file="$HOME/${key_file:2}" ;;
        esac
        ;;
      *)
        printf 'ERROR: answer yes to use the default or no to select another key file\n' >&2
        return 1
        ;;
    esac
  fi

  [[ -f "$key_file" && -r "$key_file" ]] || {
    printf 'ERROR: selected SSH public-key file is missing or unreadable: %s\n' "$key_file" >&2
    return 1
  }
  command -v ssh-keygen >/dev/null 2>&1 && ssh-keygen -lf "$key_file" >/dev/null 2>&1 || {
    printf 'ERROR: selected file is not a valid SSH public key: %s\n' "$key_file" >&2
    return 1
  }
  key="$(awk 'NF { if (found++) exit 1; value=$0 } END { if (!found) exit 1; print value }' "$key_file")" || {
    printf 'ERROR: selected file must contain exactly one public-key line: %s\n' "$key_file" >&2
    return 1
  }

  OPERATOR_SSH_PUBLIC_KEY="$key"
  export OPERATOR_SSH_PUBLIC_KEY
  printf 'Loaded operator public key from %s\n' "$key_file"
}
