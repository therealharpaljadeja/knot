#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
contracts_root="${repository_root}/contracts"

install_dependency() {
  local directory="$1"
  local repository="$2"
  local version="$3"
  local package_file="${contracts_root}/lib/${directory}/package.json"

  if [[ -f "${package_file}" ]]; then
    local installed_version
    installed_version="$(node -p "require('${package_file}').version")"
    if [[ "${installed_version}" != "${version#v}" ]]; then
      echo "${directory} ${installed_version} is installed; expected ${version#v}." >&2
      echo "Remove contracts/lib/${directory} and rerun this command." >&2
      exit 1
    fi
    echo "${directory} ${installed_version} is already installed."
    return
  fi

  if [[ -e "${contracts_root}/lib/${directory}" ]]; then
    echo "contracts/lib/${directory} exists but is incomplete; remove it and rerun." >&2
    exit 1
  fi

  forge install \
    --root "${contracts_root}" \
    "${repository}@${version}" \
    --no-git
}

install_dependency "openzeppelin-contracts" "OpenZeppelin/openzeppelin-contracts" "v5.4.0"
install_dependency "aave-address-book" "bgd-labs/aave-address-book" "v4.61.2"
install_dependency "forge-std" "foundry-rs/forge-std" "v1.16.2"
