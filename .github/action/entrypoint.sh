#!/bin/sh -l

set -euo pipefail

# Configuration
INFO_COLOR="\033[34;1m"
RESET_COLOR="\033[0m"
ACCEPT_HEADER="Accept: application/vnd.github.v3+json"
CONTENT_HEADER="Content-Type: application/json"

# Solved detected dubious ownership in repository
git config --global --add safe.directory /github/workspace

# Define home_dir
home_dir=$(pwd)

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

# Function to validate PR environment
validate_pr_environment() {
  if [ -z "${GITHUB_EVENT_PATH:-}" ] || [ -z "${GITHUB_TOKEN:-}" ]; then
    info "GITHUB_EVENT_PATH or GITHUB_TOKEN environment variable missing."
    exit 1
  fi

  PR_NUMBER=$(jq -r ".pull_request.number" "$GITHUB_EVENT_PATH")
  if [ "$PR_NUMBER" = "null" ]; then
    info "This isn't a PR."
    exit 0
  fi

  PR_COMMENTS_URL=$(jq -r ".pull_request.comments_url" "$GITHUB_EVENT_PATH")
  PR_COMMENT_URI=$(jq -r ".repository.issue_comment_url" "$GITHUB_EVENT_PATH" | sed "s|{/number}||g")
}

# Function to delete existing comment
delete_existing_comment() {
  local directory=$1
  info "Looking for an existing plan PR comment for $directory."
  local comment_id
  comment_id=$(curl -sS -H "Authorization: token $GITHUB_TOKEN" -H "$ACCEPT_HEADER" -L "$PR_COMMENTS_URL" | jq --arg directory "$directory" '.[] | select(.body | test("### Terraform `plan` Succeeded for Directory `"+$directory+"`")) | .id')

  if [ -n "$comment_id" ]; then
    info "Deleting existing plan PR comment: $comment_id."
    curl -sS -X DELETE -H "Authorization: token $GITHUB_TOKEN" -H "$ACCEPT_HEADER" -L "$PR_COMMENT_URI/$comment_id" > /dev/null
  fi
}

# Function to post a new comment
post_new_comment() {
  local directory=$1
  local clean_plan=$2
  local details_state=${EXPAND_SUMMARY_DETAILS:-true}
  details_state=$([ "$details_state" = "true" ] && echo " open" || echo "")

  local comment_body="### Terraform \`plan\` Succeeded for Directory \`$directory\`
<details${details_state}><summary>Show Output</summary>

\`\`\`diff
$clean_plan
\`\`\`
</details>"

  info "Adding plan comment to PR for $directory."
  curl -sS -X POST -H "Authorization: token $GITHUB_TOKEN" -H "$ACCEPT_HEADER" -H "$CONTENT_HEADER" -d "$(echo '{}' | jq --arg body "$comment_body" '.body = $body')" -L "$PR_COMMENTS_URL" > /dev/null
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
  local modified_dirs
  modified_dirs=$(get_modified_dirs)

  for folder in $modified_dirs; do
    run_terraform_command "$folder" "$subcommand" "$@"
  done

  if [ "${GITHUB_EVENT_NAME:-}" = "pull_request" ]; then
    handle_pull_request_comments "$modified_dirs"
  fi
}

# Function to run Terraform commands in a specified directory
run_terraform_command() {
  local folder=$1
  local subcommand=$2
  shift 2 # Remove first two arguments

  info "Running '$subcommand' in ${folder##*/}"
  (
    cd "${folder}"
    case "$subcommand" in
      plan)
        execute_terraform_plan "$@"
        ;;
      apply)
        terraform apply -auto-approve -input=false -lock=false "$@"
        ;;
      validate)
        terraform validate -no-color -lock=false "$@"
        ;;
      init)
        terraform init "$@"
        ;;
      fmt)
        terraform fmt -check "$@"
        ;;
    esac
  )
}

# Function to execute Terraform plan command and show the plan output
execute_terraform_plan() {
  terraform plan -no-color -input=false -out=tfplan -lock=false "$@"
  if [ -f tfplan ]; then
    terraform show -no-color tfplan > plan_output.txt
    PLAN_OUTPUT=$(cat plan_output.txt)
    echo "${PLAN_OUTPUT}"
  else
    info "Plan file not found"
  fi
}

# Function to handle comments on pull requests
handle_pull_request_comments() {
  local modified_dirs=$1

  for folder in $modified_dirs; do
    (
      cd "${folder}"
      local directory=$(basename "$folder")
      info "Formatting tfplan for PR Commenter on $folder"

      delete_existing_comment "$directory"
      post_pr_comment_if_plan_exists "$directory"
    )
    cd "$home_dir"
  done
}

# Function to post a pull request comment if a plan file exists
post_pr_comment_if_plan_exists() {
  local directory=$1
  local input

  if [ -f tfplan ]; then
    input=$(terraform show tfplan -no-color)
    if [ "$input" != "This plan does nothing." ]; then
      local clean_plan=${input::65300}
      clean_plan=$(echo "$clean_plan" | sed -r 's/^([[:blank:]]*)([-+~])/\2\1/g')
      [ "${HIGHLIGHT_CHANGES:-true}" = 'true' ] && clean_plan=$(echo "$clean_plan" | sed -r 's/^~/!/g')

      post_new_comment "$directory" "$clean_plan"
    else
      info "Plan is empty for $directory"
    fi
  else
    info "Plan file not found for $directory"
  fi
}

# Main function to handle command line arguments
main() {
  check_prerequisites
  validate_pr_environment

  local current_branch
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  info "Comparing changes with main since $current_branch"

  local arg=$1
  case "$arg" in
  fmt | init | validate | plan | apply)
    do_terraform "$arg"
    ;;
  *)
    info "Usage: $0 {fmt|init|validate|plan|apply}"
    exit 1
    ;;
  esac
}

main "$@"
