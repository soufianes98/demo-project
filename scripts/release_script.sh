#!/usr/bin/env bash

export TERM=xterm-color

# upload log file as an asset!!
LOG_FILE="release_script.log"
LOG_LEVEL_INFO="INFO"
LOG_LEVEL_WARN="WARN"
LOG_LEVEL_ERROR="ERROR"

# Strict mode for better error handling
# set -euo pipefail

# https://docs.github.com/en/repositories/releasing-projects-on-github/automatically-generated-release-notes
# Unit tests https://github.com/bats-core/bats-core
# https://stackoverflow.com/questions/971945/unit-tests-for-shell-scripts

# Use single quote because `!` is a reserved symbol
# https://github.com/conventional-commits/conventionalcommits.org/issues/144#issuecomment-1615952692

# Those are secrets/environment variables and should be stored in a safe place
# We will gather those variables from our github workflow
# Global variables
#GPG_PRIVATE_KEY
#GPG_PASSPHRASE
#GPG_KEY_ID
#GH_TOKEN
#GIT_AUTHOR_EMAIL
#GIT_AUTHOR_NAME

# Declaring global variables
unset is_first_release
unset is_pre_release
unset latest_tag
unset next_tag

# First check if this is the first release
# List latest commits
# Parse commits
# Categorize commits based on scope and type
# TODO : WRITE/SAVE ALL RESULTS IN A LOG FILE
# TODO: GENERATE SHA

breaking_changes=()
new_features=()
bug_fixes=()
performance_improvements=()
reverts=()
docs=()
tests=()
code_refactoring=()
styling=()
chores=()
build=()
ci=()
# merged_pull_requests=()
# closed_issues=()

#
# cd /home/soufiane/Projects/git_playground/  to test the commands
#

# Logging utility
log() {
    local LOG_LEVEL=$1
    local MESSAGE=$2
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    case ${LOG_LEVEL} in
    INFO) COLOR="\033[;32m" ;;  # Green
    WARN) COLOR="\033[;33m" ;;  # Yellow
    ERROR) COLOR="\033[;31m" ;; # Red
    *) COLOR="\033[0m" ;;       # No color
    esac

    # Log to both console and file (tee)
    echo -e "${COLOR}[${TIMESTAMP}] [${LOG_LEVEL}] ${MESSAGE}\033[m" | tee -a ${LOG_FILE}
}

verify_conditions() {
    echo "===== Verify Conditions ======"

    required_commands=(git tee wget sed awk tr cut mapfile mktemp curl jq basename file)

    for cmd in "${required_commands[@]}"; do
        # Verify that a program exist
        if command -v "$cmd" &>/dev/null; then
            log "${LOG_LEVEL_INFO}" "$cmd does exist!"
        else
            log "${LOG_LEVEL_ERROR}" "Error: $cmd does not exist!"
            exit 1
        fi
    done

    log "${LOG_LEVEL_INFO}" "===== Setup Environment Variables ======"

    required_env_vars=(GH_TOKEN GIT_AUTHOR_EMAIL GPG_PRIVATE_KEY GPG_PASSPHRASE GPG_KEY_ID GIT_AUTHOR_NAME USERNAME REPOSITORY_NAME)

    for var in "${required_env_vars[@]}"; do
        # Verify that an environment variable exists
        if [[ -z "${!var}" ]]; then
            log "${LOG_LEVEL_ERROR}" "Error: $var is not set!"
            exit 1
        fi
    done

    log "${LOG_LEVEL_INFO}" "All required commands and environment variables are verified!"
    echo "==========================="
}

setup_git() {
    echo "===== Setup git ======"
    # GPG="Gnu Privacy Guard"

    # Import private key
    if ! echo "$GPG_PRIVATE_KEY" | gpg --batch --yes --passphrase "$GPG_PASSPHRASE" --import; then
        log "${LOG_LEVEL_ERROR}" "Error: Failed to import GPG private key!"
        return 1
    fi

    # Configure GPG directory with strict permissions
    mkdir -p ~/.gnupg
    chmod 700 ~/.gnupg

    # GPG configuration
    {
        echo "allow-loopback-pinentry"
        echo "pinentry-mode loopback"
    } >>~/.gnupg/gpg.conf

    # Create GPG wrapper script
    # Secure temporary file creation
    local gpg_program_path
    gpg_program_path=$(mktemp /tmp/gpg_and_passphrase.XXXXXX) || {
        log "${LOG_LEVEL_ERROR}" "Error: Failed to create temporary file for GPG wrapper!"
        return 1
    }

    trap 'rm -f "$gpg_program_path"' EXIT

    # `/usr/bin/gpg` is the default path of the GPG program in linux
    # `--no-tty` is an argument used by the GPG program to ensure that GPG does not use the terminal for any input
    cat >"$gpg_program_path" <<EOF
#!/usr/bin/env bash
/usr/bin/gpg --batch --no-tty --pinentry-mode loopback --passphrase '$GPG_PASSPHRASE' "\$@"
EOF

    #chmod +x "$gpg_program_path"
    chmod 0700 "$gpg_program_path"
    # Configure Git

    # Set username
    git config --global user.name "$GIT_AUTHOR_NAME"
    log "${LOG_LEVEL_INFO}" "Git author name set to: $(git config --global user.name "$GIT_AUTHOR_NAME")"

    # Set email
    git config --global user.email "$GIT_AUTHOR_EMAIL"
    log "${LOG_LEVEL_INFO}" "Git author name set to: $(git config --global user.email "$GIT_AUTHOR_EMAIL")"

    # Used to sign commits with GPG signing key
    git config --global user.signingkey "$GPG_KEY_ID"
    log "${LOG_LEVEL_INFO}" "GPG signing key configured"

    git config --global commit.gpgsign true
    log "${LOG_LEVEL_INFO}" "GPG signing key enabled"

    git config --global tag.gpgsign true
    log "${LOG_LEVEL_INFO}" "Tag signing enabled"
    git config --global gpg.program "$gpg_program_path"

    log "${LOG_LEVEL_INFO}" "Git setup complete. ✔️"
}

check_git_tags() {
    echo "===== Check git tags ======"

    # Check for tags that starts with "v" (e.g., v1.0.0)
    if [ -z "$(git tag --list "v*")" ] ; then
        log "${LOG_LEVEL_INFO}" "No tags found in $REPOSITORY_NAME project, This is likely the first release."
        is_first_release=true
        latest_tag=""
    else
        # Get the most recent tag and remove "v" prefix
        # `git describe --tags --abbrev=0` gets the most recent tag
        # sed removes the "v" prefix from the version number
        latest_tag=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//') # Example output 0.1.0

        if [ -n "$latest_tag" ]; then
            log "${LOG_LEVEL_INFO}" "Tags detected in the $REPOSITORY_NAME"
            log "${LOG_LEVEL_INFO}" "Latest tag found v$latest_tag"
            is_first_release=false
        else
            log "${LOG_LEVEL_ERROR}" "Error: Unable to determine the latest tag."
            exit 1
        fi
    fi

    log "${LOG_LEVEL_INFO}" "Result of function: check_git_tags()"
    log "${LOG_LEVEL_INFO}" "is_first_release = $is_first_release"
    log "${LOG_LEVEL_INFO}" "latest_tag = $latest_tag"

    echo "==========================="
}

# Get the latest commits since the latest tag
get_latest_commits_list() {
    # https://chatgpt.com/share/66fadabb-def8-800f-8e2e-a84503af7586

    # NOTE: You should get latest commits since the latest tag
    # TODO: Handle if there is no previous tag

    # Declare an empty array
    local commits_array=()

    #
    # Format <commit_hash> <subject> <body>
    local git_format="%h,%s,%b%x00" # Use null byte as separator

    if [ -n "$latest_tag" ]; then
        while IFS= read -r -d $'\0' commit; do
            # Only add non-empty commits
            if [ -n "$commit" ]; then
                # log "${LOG_LEVEL_INFO}" "commit = $commit"
                # Push one item to commits_array
                commits_array+=("$commit")
            fi
            # Capturing the output of git log since the latest tag
            # and feed the output to the while loop
        done < <(git log "v${latest_tag}"..HEAD --pretty=format:"${git_format}")
    else
        # If no tags exist, get all commits
        log "${LOG_LEVEL_INFO}" "No tags exist!"
        while IFS= read -r commit; do
            commits_array+=("$commit")
        done < <(git log --pretty=format:"${git_format}")
        log "${LOG_LEVEL_INFO}" "commits_array = ${commits_array[*]}"
    fi

    # Log all commits for debugging
    log "Found ${#commits_array[@]} commits since ${latest_tag:-(repository start)}"

    if [ ${#commits_array[@]} -eq 0 ]; then
        log "${LOG_LEVEL_INFO}" "Warning: No commits found since last tag"
    fi
    #

    # Return the array
    printf "%s\n" "${commits_array[@]}"
}

# Parse a single commit into its components
parse_commit() {
    local commit="$1"
    log "${LOG_LEVEL_INFO}" "commit = $commit"
    local commit_hash commit_subject commit_body

    # Verify if commit is not empty
    if [ -z "$commit" ]; then
        log "${LOG_LEVEL_ERROR}" "Error: Empty commit string provided"
        exit 1
    fi

    # Split the commit into hash , subject and body using `,` as the delimiter
    # -r prevents backslash escaping
    IFS=',' read -r commit_hash commit_subject commit_body <<<"$commit"

    # Trim whitespace from components
    commit_hash="${commit_hash##*( )}"
    commit_hash="${commit_hash%%*( )}"

    commit_subject="${commit_subject##*( )}"
    commit_subject="${commit_subject%%*( )}"

    commit_body="${commit_body##*( )}"
    commit_body="${commit_body%%*( )}"

    # Verify hash is not empty
    if [ -z "$commit_hash" ]; then
        log "${LOG_LEVEL_ERROR}" "Error: Failed to parse commit hash"
        return 1
    fi

    # Return parsed components
    echo "$commit_hash $commit_subject $commit_body"
    return 0
}

# Process commit
process_commit() {
    local commit="$1"
    log "${LOG_LEVEL_INFO}" "commit = $commit"

    # Parse the commit
    read -r commit_hash commit_subject commit_body <<<"$(parse_commit "$commit")"

    if [[ "$commit_subject" == "initial commit" ]]; then
        log "${LOG_LEVEL_INFO}" "initial commit"
        return 0
    fi

    # Extract commit scope from commit_subject
    commit_scope=$(echo -e "$commit_subject" | sed -n 's/.*(\(.*\)): .*/\1/p')

    # Check if there is a commit scope
    if [ -n "$commit_scope" ]; then
        # There is scope
        log "${LOG_LEVEL_INFO}" "Commit scope founded!"
        # In this case the commit type is anything before the first '('
        commit_type=$(echo -e "$commit_subject" | awk -F '(' '{print $1}')
        log "${LOG_LEVEL_INFO}" "$commit_type"
    else
        log "There is no scope!"
        # In this case the commit type is anything before ':'
        commit_type="${commit_subject%:*}"
    fi

    # Check if commit body starts with the word `BREAKING CHANGE: ` in the last or pre last line
    # https://github.com/semantic-release/semantic-release/commit/2904832967c9160d3e293ce4be7a12aef0318a95

    # TODO: Process breaking changes

    # Check for breaking change marker (!)
    if [[ "$commit_subject" =~ ^[^:]+! ]]; then
        breaking_changes+=("${commit_scope},${commit_content}")
    fi

    # RS = Record separator
    # gsub(/\n/, " ") is used to replace
    # commit_body="item1\nhello world\n\nitem2\n\nitem3"
    mapfile -t body_lines_array < <(echo -e "$commit_body" | awk -v RS='\n\n' '{gsub(/\n/, " "); print}')

    for value in "${body_lines_array[@]}"; do
        #echo -n "$value"

        if [[ "${value:0:16}" == "BREAKING CHANGE: " ]]; then
            breaking_change_length="${#value}"
            breaking_change_content="${value:17:"$((breaking_change_length - 1))"}"

            # TODO

            breaking_changes+=("${commit_scope},${breaking_change_content}")
        fi
    done

    # TODO

    # We trim the white space from our commit subject
    commit_content=$(echo -e "${commit_subject#*:}" | tr -d ' ')

    # Process commit type
    case $commit_type in
    "feat")
        new_features+=("${commit_scope},${commit_content},${commit_hash}")
        # If we want to use it we need to split it
        ;;
    "fix")
        bug_fixes+=("${commit_scope},${commit_content},${commit_hash}")
        ;;
    "build")
        build+=("${commit_scope},${commit_content},${commit_hash}")
        ;;
    "chore")
        chores+=("${commit_scope},${commit_content},${commit_hash}")
        ;;
    "ci")
        ci+=("${commit_scope},${commit_content},${commit_hash}")
        ;;
    "docs")
        docs+=("${commit_scope},${commit_content},${commit_hash}")
        ;;
    "style")
        styling+=("${commit_scope},${commit_content},${commit_hash}")
        ;;
    "refactor")
        code_refactoring+=("${commit_scope},${commit_content},${commit_hash}")
        ;;
    "perf")
        performance_improvements+=("${commit_scope},${commit_content},${commit_hash}")
        ;;
    "test")
        tests+=("${commit_scope},${commit_content},${commit_hash}")
        ;;
    "revert")
        reverts+=("${commit_scope},${commit_content},${commit_hash}")
        ;;
    *)
        # TODO:
        log "${LOG_LEVEL_INFO}" "Warning: Unknown commit type '$commit_type' for commit $commit_hash"
        ;;
    esac
}

# Parse a tag into major, minor, and patch versions
parse_latest_commits() {
    echo "===== Parse latest commits ======"

    # Fetch latest commits
    local commits_array

    mapfile -t commits_array < <(get_latest_commits_list)
    for commit in "${commits_array[@]}"; do
        log "${LOG_LEVEL_INFO}" "$commit"
    done

    if [ ${#commits_array[@]} -eq 0 ]; then
        log "${LOG_LEVEL_INFO}" "Warning: No commits found"
        exit 1
    fi

    log "${LOG_LEVEL_INFO}" "Found ${#commits_array[@]} commits to process"

    # Process each commit
    local commit_count=0

    for commit in "${commits_array[@]}"; do
        ((commit_count++))
        log "${LOG_LEVEL_INFO}" "Processing commit $commit_count/${commits_array[*]}"

        if ! process_commit "$commit"; then
            log "${LOG_LEVEL_INFO}" "Warning: Failed to process commit: $commit"
            continue
        fi
    done

    log "${LOG_LEVEL_INFO}" "===== Commits parsing complete ====="
    echo "==========================="

    return 0
}

# Determine the next version based on changes
parse_latest_tag() {
    local latest_tag="$1"
    local major minor patch

    # TODO: Validate input
    if [ -z "$latest_tag" ]; then
        log "${LOG_LEVEL_ERROR}" "Error: Empty tag provided"
        return 1 # exit 1
    fi

    # TODO: Validate semantic version format (x.y.z)
    if [[ "$latest_tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log "${LOG_LEVEL_ERROR}" "Error: Invalid semantic version format. Expected 'x.y.z' but got '$latest_tag'"
        return 1 # exit 1
    fi

    # Split the version into components, into major, minor and patch using `.` as the delimiter
    IFS='.' read -r major minor patch <<<"$latest_tag"

    # Return components
    echo "$major $minor $patch"
    return 0
}

bump_version() {
    echo "===== Bumping versions ======"

    # NOTE: https://chatgpt.com/share/675616ba-109c-800f-b2b2-018234f97e9a

    # Create a git tag if all conditions met

    # Handle first release
    if [[ "$is_first_release" = true ]]; then
        # initial commit | first commit
        next_tag="0.1.0"
        is_pre_release=true
        log "${LOG_LEVEL_INFO}" "First release: v$next_tag (pre-release)"
        return 0
    fi

    if ! read -r major minor patch <<<"$(parse_latest_tag "$latest_tag")"; then
        log "${LOG_LEVEL_ERROR}" "Error: Failed to parse current version $latest_tag"
        exit 1
    fi

    # Determine version bump based on changes
    # Array size of: ${#breaking_changes[@]}
    if [[ ${#breaking_changes[@]} -ne 0 ]]; then
        # Bump major(major version increment)
        next_tag="$((++major)).0.0"
        log "${LOG_LEVEL_INFO}" "Major version bump to: v$next_tag"
        is_pre_release=false

        log "${LOG_LEVEL_INFO}" "Breaking changes (${#breaking_changes[@]}):"
        for change in "${breaking_changes[@]}"; do
            log "${LOG_LEVEL_INFO}" "   - $change"
        done

        return 0 # Exit/Break this function and move to the next function
    fi

    if [[ ${#new_features[@]} -ne 0 || ${#performance_improvements[@]} -ne 0 ]]; then
        # Bump minor
        next_tag="$major.$((++minor)).0"
        log "${LOG_LEVEL_INFO}" "Minor version bump to: v$next_tag"

        is_pre_release=("$major" -eq 0)

        log "${LOG_LEVEL_INFO}" "New Features: ${#new_features[@]}"
        log "${LOG_LEVEL_INFO}" "Performance Improvements: ${#performance_improvements[@]}"

        return 0 # Exit/Break this function and move to the next function
    fi

    if [[ ${#bug_fixes[@]} -ne 0 ]]; then
        # Bump patch
        next_tag="$major.$minor.$((++patch))"
        log "${LOG_LEVEL_INFO}" "Patch version bump to: v$next_tag"

        is_pre_release=("$major" -eq 0)

        log "${LOG_LEVEL_INFO}" "Bug Fixes: ${#bug_fixes[@]}"

        return 0 # Exit/Break this function and move to the next function
    fi

    log "${LOG_LEVEL_INFO}" "No version-impacting changes detected in codebase!"
    log "${LOG_LEVEL_INFO}" "Current version remains at v$latest_tag"

    log "${LOG_LEVEL_INFO}" "Change summary:"
    log "${LOG_LEVEL_INFO}" "Breaking changes: (${#breaking_changes[@]})"
    log "${LOG_LEVEL_INFO}" "New Features: ${#new_features[@]}"
    log "${LOG_LEVEL_INFO}" "Performance Improvements: ${#performance_improvements[@]}"
    log "${LOG_LEVEL_INFO}" "Bug Fixes: ${#bug_fixes[@]}"
    log "${LOG_LEVEL_INFO}" "Documentation: (${#docs[@]}):"
    log "${LOG_LEVEL_INFO}" "Chores: ${#chores[@]}"
    log "${LOG_LEVEL_INFO}" "Refactoring: ${#refactoring[@]}"
    log "${LOG_LEVEL_INFO}" "Styling: ${#styling[@]}"
    log "${LOG_LEVEL_INFO}" "Build: (${#build[@]})"
    log "${LOG_LEVEL_INFO}" "Continuous Integration: ${#ci[@]}"
    log "${LOG_LEVEL_INFO}" "Code Refactoring: ${#code_refactoring[@]}"
    log "${LOG_LEVEL_INFO}" "Reverts: ${#reverts[@]}"

    # The following code will exit the entire script
    exit 0

    # TODO more conditions

}

parse_commit_subject() {
    local subject="$1"
    local commit_scope commit_content commit_hash

    if [ -z "$subject" ]; then
        log "${LOG_LEVEL_ERROR}" "Error: Empty commit subject provided"
        return 1
    fi

    # Split the vale into scope , content and hash using `,` as the delimiter
    IFS=',' read -r commit_scope commit_content commit_hash <<<"$subject"

    # Trim whitespace from components
    commit_scope="${commit_scope##*( )}"
    commit_scope="${commit_scope%%*( )}"

    commit_content="${commit_content##*( )}"
    commit_content="${commit_content%%*( )}"

    commit_hash="${commit_hash##*( )}"
    commit_hash="${commit_hash%%*( )}"

    # Validate hash exists
    if [ -z "$commit_hash" ]; then
        log "${LOG_LEVEL_ERROR}" "Error: Missing commit hash in subject: $subject"
        return 1
    fi

    echo "$commit_scope $commit_content $commit_hash"
    return 0
}

create_commit_hash_url() {
    local username="$1"
    local repository_name="$1"
    local commit_hash="$1"

    # Return the URL
    echo "https://github.com/$username/$repository_name/commit/$commit_hash"
}

prepare_latest_changelog() {
    echo "===== Generate release notes ======"

    local release_notes=""

    if [[ "$is_first_release" = true ]]; then
        release_notes="initial commit"

        # This is like a return value
        echo "$release_notes"
        return 0
    fi

    if [ ${#breaking_changes[@]} -ne 0 ]; then
        # Append release_notes
        release_notes+="**BREAKING CHANGES**\n\n"

        for value in "${breaking_changes[@]}"; do
            commit_scope=$(echo "$value" | cut -d ',' -f1)
            breaking_change_content=$(echo "$value" | cut -d ',' -f2)

            if [ -n "$commit_scope" ]; then
                release_notes+="* $commit_scope: $breaking_change_content\n"
            else
                release_notes+="* $breaking_change_content\n"
            fi
        done
    else
        log "${LOG_LEVEL_INFO}" "No breaking changes found!"
    fi

    if [ ${#new_features[@]} -ne 0 ]; then
        # Append release_notes
        release_notes+="**Features**\n\n"

        for value in "${new_features[@]}"; do
            read -r commit_scope commit_content commit_hash <<<"$(parse_commit_subject "$value")"

            log "${LOG_LEVEL_INFO}" "$commit_scope, $commit_content, $commit_hash"

            commit_hash_url=$(create_commit_hash_url "$USERNAME" "$REPOSITORY_NAME" "$commit_hash")

            if [ -n "$commit_scope" ]; then
                release_notes+="* $commit_scope: $commit_content ([#$commit_hash]($commit_hash_url))\n"
            else
                release_notes+="* $commit_content ([#$commit_hash]($commit_hash_url))\n"
            fi
        done
    else
        log "${LOG_LEVEL_INFO}" "No new features found!"
    fi

    # Here we check if the array is not empty
    # `-ne` means not equal
    # `${#bug_fixes[@]}` gives us the length of the array
    if [ ${#bug_fixes[@]} -ne 0 ]; then
        # Append release_notes
        release_notes+="**Bug Fixes**\n\n"

        for value in "${bug_fixes[@]}"; do
            read -r commit_scope commit_content commit_hash <<<"$(parse_commit_subject "$value")"
            log "${LOG_LEVEL_INFO}" "$commit_scope, $commit_content, $commit_hash"

            commit_hash_url=$(create_commit_hash_url "$USERNAME" "$REPOSITORY_NAME" "$commit_hash")

            if [ -n "$commit_scope" ]; then
                release_notes+="* $commit_scope: $commit_content ([#$commit_hash]($commit_hash_url))\n"
            else
                release_notes+="* $commit_content ([#$commit_hash]($commit_hash_url))\n"
            fi
        done
    else
        log "${LOG_LEVEL_INFO}" "No bug fixes found!"
    fi

    if [ ${#performance_improvements[@]} -ne 0 ]; then
        # Append release_notes
        release_notes+="**Performance Improvements**\n\n"

        for value in "${performance_improvements[@]}"; do
            read -r commit_scope commit_content commit_hash <<<"$(parse_commit_subject "$value")"
            log "${LOG_LEVEL_INFO}" "$commit_scope, $commit_content, $commit_hash"

            commit_hash_url=$(create_commit_hash_url "$USERNAME" "$REPOSITORY_NAME" "$commit_hash")

            if [ -n "$commit_scope" ]; then
                release_notes+="* $commit_scope: $commit_content ([#$commit_hash]($commit_hash_url))\n"
            else
                release_notes+="* $commit_content ([#$commit_hash]($commit_hash_url))\n"
            fi
        done
    else
        log "${LOG_LEVEL_INFO}" "No new performance improvements found!"
    fi

    if [ ${#reverts[@]} -ne 0 ]; then
        # Append release_notes
        release_notes+="**Reverts**\n\n"

        for value in "${reverts[@]}"; do
            read -r commit_scope commit_content commit_hash <<<"$(parse_commit_subject "$value")"
            log "${LOG_LEVEL_INFO}" "$commit_scope, $commit_content, $commit_hash"

            commit_hash_url=$(create_commit_hash_url "$USERNAME" "$REPOSITORY_NAME" "$commit_hash")

            if [ -n "$commit_scope" ]; then
                release_notes+="* $commit_scope: $commit_content ([#$commit_hash]($commit_hash_url))\n"
            else
                release_notes+="* $commit_content ([#$commit_hash]($commit_hash_url))\n"
            fi
        done
    else
        log "${LOG_LEVEL_INFO}" "No new reverts found!"
    fi

    if [ ${#docs[@]} -ne 0 ]; then
        # Append release_notes
        release_notes+="**Documentation**\n\n"

        for value in "${docs[@]}"; do
            read -r commit_scope commit_content commit_hash <<<"$(parse_commit_subject "$value")"
            log "${LOG_LEVEL_INFO}" "$commit_scope, $commit_content, $commit_hash"

            commit_hash_url=$(create_commit_hash_url "$USERNAME" "$REPOSITORY_NAME" "$commit_hash")

            if [ -n "$commit_scope" ]; then
                release_notes+="* $commit_scope: $commit_content ([#$commit_hash]($commit_hash_url))\n"
            else
                release_notes+="* $commit_content ([#$commit_hash]($commit_hash_url))\n"
            fi
        done
    else
        log "${LOG_LEVEL_INFO}" "No new docs updates found!"
    fi

    if [ ${#tests[@]} -ne 0 ]; then
        # Append release_notes
        release_notes+="**Tests**\n\n"

        for value in "${tests[@]}"; do
            read -r commit_scope commit_content commit_hash <<<"$(parse_commit_subject "$value")"
            log "${LOG_LEVEL_INFO}" "$commit_scope, $commit_content, $commit_hash"

            commit_hash_url=$(create_commit_hash_url "$USERNAME" "$REPOSITORY_NAME" "$commit_hash")

            if [ -n "$commit_scope" ]; then
                release_notes+="* $commit_scope: $commit_content ([#$commit_hash]($commit_hash_url))\n"
            else
                release_notes+="* $commit_content ([#$commit_hash]($commit_hash_url))\n"
            fi
        done
    else
        log "${LOG_LEVEL_INFO}" "No new tests found!"
    fi

    if [ ${#code_refactoring[@]} -ne 0 ]; then
        # Append release_notes
        release_notes+="**Code Refactoring**\n\n"

        for value in "${code_refactoring[@]}"; do
            read -r commit_scope commit_content commit_hash <<<"$(parse_commit_subject "$value")"
            log "${LOG_LEVEL_INFO}" "$commit_scope, $commit_content, $commit_hash"

            commit_hash_url=$(create_commit_hash_url "$USERNAME" "$REPOSITORY_NAME" "$commit_hash")

            if [ -n "$commit_scope" ]; then
                release_notes+="* $commit_scope: $commit_content ([#$commit_hash]($commit_hash_url))\n"
            else
                release_notes+="* $commit_content ([#$commit_hash]($commit_hash_url))\n"
            fi
        done
    else
        log "${LOG_LEVEL_INFO}" "No new code refactoring found!"
    fi

    if [ ${#styling[@]} -ne 0 ]; then
        # Append release_notes
        release_notes+="**Styles**\n\n"

        for value in "${styling[@]}"; do
            read -r commit_scope commit_content commit_hash <<<"$(parse_commit_subject "$value")"
            log "${LOG_LEVEL_INFO}" "$commit_scope, $commit_content, $commit_hash"

            commit_hash_url=$(create_commit_hash_url "$USERNAME" "$REPOSITORY_NAME" "$commit_hash")

            if [ -n "$commit_scope" ]; then
                release_notes+="* $commit_scope: $commit_content ([#$commit_hash]($commit_hash_url))\n"
            else
                release_notes+="* $commit_content ([#$commit_hash]($commit_hash_url))\n"
            fi
        done
    else
        log "${LOG_LEVEL_INFO}" "No new style updates found!"
    fi

    if [ ${#chores[@]} -ne 0 ]; then
        # Append release_notes
        release_notes+="**Chores**\n\n"

        for value in "${chores[@]}"; do
            read -r commit_scope commit_content commit_hash <<<"$(parse_commit_subject "$value")"
            log "${LOG_LEVEL_INFO}" "$commit_scope, $commit_content, $commit_hash"

            commit_hash_url=$(create_commit_hash_url "$USERNAME" "$REPOSITORY_NAME" "$commit_hash")

            if [ -n "$commit_scope" ]; then
                release_notes+="* $commit_scope: $commit_content ([#$commit_hash]($commit_hash_url))\n"
            else
                release_notes+="* $commit_content ([#$commit_hash]($commit_hash_url))\n"
            fi
        done
    else
        log "${LOG_LEVEL_INFO}" "No new chores found!"
    fi

    if [ ${#build[@]} -ne 0 ]; then
        # Append release_notes
        release_notes+="**Build**\n\n"

        for value in "${reverts[@]}"; do
            read -r commit_scope commit_content commit_hash <<<"$(parse_commit_subject "$value")"
            log "${LOG_LEVEL_INFO}" "$commit_scope, $commit_content, $commit_hash"

            commit_hash_url=$(create_commit_hash_url "$USERNAME" "$REPOSITORY_NAME" "$commit_hash")

            if [ -n "$commit_scope" ]; then
                release_notes+="* $commit_scope: $commit_content ([#$commit_hash]($commit_hash_url))\n"
            else
                release_notes+="* $commit_content ([#$commit_hash]($commit_hash_url))\n"
            fi
        done
    else
        log "${LOG_LEVEL_INFO}" "No build found!"
    fi

    if [ ${#ci[@]} -ne 0 ]; then
        # Append release_notes
        release_notes+="**Continuous Integration**\n\n"

        for value in "${ci[@]}"; do
            read -r commit_scope commit_content commit_hash <<<"$(parse_commit_subject "$value")"
            log "${LOG_LEVEL_INFO}" "$commit_scope, $commit_content, $commit_hash"

            commit_hash_url=$(create_commit_hash_url "$USERNAME" "$REPOSITORY_NAME" "$commit_hash")

            if [ -n "$commit_scope" ]; then
                release_notes+="* $commit_scope: $commit_content ([#$commit_hash]($commit_hash_url))\n"
            else
                release_notes+="* $commit_content ([#$commit_hash]($commit_hash_url))\n"
            fi
        done
    else
        log "${LOG_LEVEL_INFO}" "No new CI updates found!"
    fi

    # TODO

    # This is like a return value
    echo "$release_notes"
}

generate_changelog() {
    echo "===== Generate changelog ======"

    local latest_changelog
    latest_changelog=$(prepare_latest_changelog)

    current_date=$(date +%Y-%m-%d)

    # https://chat.openai.com/share/404f983a-046b-4112-a86c-6b3bf0c07be5
    # Append or create a CHANGELOG.md file
    local changelog_file="CHANGELOG.md"

    if [ "$is_first_release" = true ]; then
        # https://github.com/USERNAME/project-name/releases/tag/v0.1.0
        url="https://github.com/$USERNAME/$REPOSITORY_NAME/releases/tag/v$next_tag"

        changelog="# Changelog\n\n## [$next_tag]($url) ($current_date)\n\n$latest_changelog"
        # Create the first changelog file
        echo -e "$changelog" >"$changelog_file"
    elif [ "$is_first_release" = false ]; then
        # https://github.com/USERNAME/project-name/compare/v0.1.0...v0.2.0
        url="https://github.com/$USERNAME/$REPOSITORY_NAME/compare/v$latest_tag...v$next_tag"

        # Remove the first line that contains the phrase '# Changelog'
        sed -i '/^# Changelog/d' "$changelog_file"

        # Create new changelog content
        changelog="# Changelog \n\n## [$next_tag]($url) ($current_date)\n\n$latest_changelog\n\n$(cat "$changelog_file")"

        # Prepend the new changelog content to the existing file
        echo -e "$changelog" | cat - "$changelog_file" >temp_changelog && mv temp_changelog "$changelog_file"
    fi

    log "${LOG_LEVEL_INFO}" "Changelog created"
    echo "==========================="
}

# NOTE: Always publish changelog before creating a new tag
publish_changelog() {
    echo "===== Publish changelog ======"

    commit_message="chore(release): update changelog for v$next_tag"
    git add CHANGELOG.md
    git commit -S -m "$commit_message"
    git log --show-signature
    git push

    log "${LOG_LEVEL_INFO}" "Changelog successfully published"
    echo "==========================="
}

create_new_github_tag() {
    echo "===== Create a new Github tag ======"

    # Create a signed and annotated git tag
    git tag -s -a "v$next_tag" -m "Release version $next_tag"

    # Verify signed tag
    # git tag -v "v$next_tag"

    message="The tag has been successfully published 🎉"

    # Push the tag to remote
    git push origin "v$next_tag" && log "${LOG_LEVEL_INFO}" "$message"

    # Show the tag details
    git show "v$next_tag"
    echo "==========================="
}

create_github_release() {
    echo "===== Create a new Github release ======"

    # First check if the remote tag is pushed and available in github
    # git ls-remote --tags origin

    # push release to github using curl using: <https://docs.github.com/en/rest> , <https://docs.github.com/en/rest/releases/releases> , <https://docs.github.com/en/rest/releases/assets>

    # TODO: Every release should contain shipped source code and all assets(Artifacts) like:
    # https://github.com/jgraph/drawio/releases
    # https://github.com/ssdev98/test_technique/releases/new
    # https://www.lucavall.in/blog/how-to-create-a-release-with-multiple-artifacts-from-a-github-actions-workflow-using-the-matrix-strategy
    # https://stackoverflow.com/questions/71816958/how-to-upload-artifacts-to-existing-release
    # https://stackoverflow.com/questions/75164222/how-to-upload-a-release-in-github-action-using-github-script-action

    # Make sure to add release notes or setup via github

    # https://docs.github.com/en/rest/releases/releases?apiVersion=2022-11-28
    # To list all releases

    # Boolean value
    echo "$is_pre_release"

    # TODO: Before publishing a release check if the git tag is published to github

    curl -L \
        -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $GH_TOKEN" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        https://api.github.com/repos/"$USERNAME"/"$REPOSITORY_NAME"/releases
    log "${LOG_LEVEL_INFO}" 'Checking if the tag is published to github'

    #
    #
    #
    #
    #

    local release_notes
    release_notes=$(prepare_latest_changelog)

    log "${LOG_LEVEL_INFO}" "release_notes: $release_notes"

    # Create a new release
    RELEASE_RESPONSE=$(
        curl -L \
            -X POST \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer $GH_TOKEN" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            https://api.github.com/repos/"$USERNAME"/"$REPOSITORY_NAME"/releases \
            -d "{
        \"tag_name\": \"v$next_tag\",
        \"target_commitish\": \"main\",
        \"name\": \"v$next_tag\",
        \"body\": \"$release_notes\",
        \"draft\": false,
        \"prerelease\": $is_pre_release,
        \"generate_release_notes\": true
    }"
    )

    echo "RELEASE_RESPONSE = $RELEASE_RESPONSE"

    RELEASE_ID=$(echo "$RELEASE_RESPONSE" | jq -r '.id')

    if [[ "$RELEASE_RESPONSE" == "null" ]]; then
        echo "ERROR"
        echo "$RELEASE_RESPONSE" | jq '.message, .errors'
        log "${LOG_LEVEL_ERROR}" 'Error: Failed to create a new release in GitHub'
        exit 1
    fi

    log "${LOG_LEVEL_INFO}" "Release created with ID: $RELEASE_ID"

    log "${LOG_LEVEL_INFO}" "Uploading artifacts for the latest release"
    # TODO:
    artifacts_paths=("$HOME/Downloads/artifacts/artifact1.js" "$HOME/Downloads/artifacts/artifact2.txt")

    for artifact_path in "${artifacts_paths[@]}"; do

        # Extract filename from the path
        artifact_filename=$(basename "$artifact_path")

        # Get the MIME type dynamically
        mime_type=$(file -b --mime-type "$artifact_path")

        log "${LOG_LEVEL_INFO}" "Uploading $artifact_path..."

        curl -L \
            -X POST \
            -H "Authorization: Bearer $GH_TOKEN" \
            -H "Content-Type: $mime_type" \
            --data-binary @"$artifact_path" \
            "https://uploads.github.com/repos/$USERNAME/$REPOSITORY_NAME/releases/$RELEASE_ID/assets?name=$artifact_filename-$next_tag"
        # || {
        #     log "${LOG_LEVEL_ERROR}" 'Error: Failed to attach artifacts to release in GitHub'
        #     exit 1
        # }

        log "${LOG_LEVEL_INFO}" "- $artifact_path file uploaded successfully."
    done

    log "${LOG_LEVEL_INFO}" "All artifacts uploaded successfully."

    # Then check the response status code is 201 (created) to make sure the release is published in github
    # And also print the release info and maybe export it to a service using jq command and curl
    # and display a message to confirm that the release is published to github
    # like
    log "${LOG_LEVEL_INFO}" "Release published successfully! 🎉"
    echo "==========================="
}

post_release() {
    # TODO: Cleanup
    # TODO: Delete temporary files
    echo "==========================="
    return 0
}

main() {
    verify_conditions
    setup_git
    check_git_tags
    parse_latest_commits
    bump_version
    generate_changelog
    publish_changelog
    create_new_github_tag
    create_github_release
    post_release
}

# Program entry point
main
