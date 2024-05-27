#!/bin/sh -l

set -euo pipefail

# Define colors for output
INFO_COLOR="\033[34;1m"
RESET_COLOR="\033[0m"

# Solved detected dubious ownership in repository
git config --global --add safe.directory /github/workspace

# Helper function to print info messages
info() {
	echo -e "${INFO_COLOR}INFO:${RESET_COLOR} $1" >&2
}

# Function to check prerequisites
check_prerequisites() {
	terraform --version >/dev/null || {
		info "Terraform is not installed"
		exit 1
	}
	tfenv list >/dev/null || {
		info "tfenv is not installed"
		exit 1
	}
}

# Function to get modified directories
get_modified_dirs() {
	if git rev-parse --verify HEAD^ >/dev/null 2>&1; then
		git diff HEAD^..HEAD --name-only -- '*.tf' '*.tfvars' |
			xargs -I{} dirname "{}" |
			sort -u |
			sed '/^\./d' |
			cut -d/ -f 1-2
	else
		# In case of initial commit, use all directories
		find . -type d -not -path '*/\.*' -not -path '.' |
			sort -u |
			cut -d/ -f 2
	fi
}

# Function to execute Terraform commands
do_terraform() {
	local subcommand=$1
	shift # Remove first argument
	local modified_dirs=$(get_modified_dirs)

	for folder in $modified_dirs; do
		# Change to the directory and execute in a subshell
		(
			cd "${folder}"
			case "$subcommand" in
			"plan")
				info "Running '$subcommand' in ${folder##*/}"
				terraform plan -no-color -input=false -out=tfplan -lock=false "$@"
				;;
			"apply")
				info "Running '$subcommand' in ${folder##*/}"
				terraform apply -auto-approve -input=false -lock=false "$@"
				;;
			"validate")
				info "Running '$subcommand' in ${folder##*/}"
				terraform validate -no-color -lock=false "$@"
				;;
			"init")
				info "Running '$subcommand' in ${folder##*/}"
				terraform init "$@"
				;;
			"fmt")
				info "Running '$subcommand' in ${folder##*/}"
				terraform fmt -check "$@"
				;;
			esac
		)
	done
}

# Main function to handle command line arguments
main() {
	check_prerequisites
	local current_branch=$(git rev-parse --abbrev-ref HEAD)
	info "Comparing changes with main since $current_branch"

	case "$1" in
	fmt | init | validate | plan | apply)
		do_terraform "$@"
		;;
	*)
		info "Usage: $0 {fmt|init|validate|plan|apply}"
		exit 1
		;;
	esac
}

main "$@"