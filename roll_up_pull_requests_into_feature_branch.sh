#!/bin/bash

# This script takes a filename as a command line arg
#   and parses the input file, expecting a pull
#   request number on each line.  It applies them
#   in order on the destination branch

# It also expects you to have a remote 'upstream' that
#  points to the repo you want to use for PRs

# Get the branch we'll put all of the rebased code onto
echo "Enter the destination branch"
read destination_branch

# Add the accept-theirs alias we use to resolve merge conflicts during rebase
git config --global alias.accept-theirs '!f() { git checkout --theirs -- \"${@:-.}\"; git add -u \"${@:-.}\"; }; f'

while IFS='' read -r line || [[ -n "$line" ]]; do

	PR=$line

	# Get the PR that represented the feature branch when it was merged
	if ! git fetch upstream pull/$PR/head:feature_branch_$PR; then
		echo "Cannot find that pull request"
		exit 1
	fi

	# Set a reference to the feature branch/PR
	feature_branch=feature_branch_$PR

	# Get the commit of the merge commit
	merge_commit=$(git log --pretty=oneline --all --grep="Merge pull request #$PR" | grep -o "^[[:alnum:]]\{40\}")

	# Get a version of develop before the merge
	if [[ -z "${merge_commit// }" ]]; then
		echo "Failed to find a merge commit matching $PR"
		exit 1
	:
	else
		git checkout $merge_commit~1
		git checkout -b develop-$PR
	fi

	# Checkout the feature branch locally
	if ! git checkout $feature_branch; then
		echo "Failed to checkout the feature branch ($feature_branch)"
		exit 1
	fi

	# Rebase feature branch onto master through pr branch
	git rebase --onto master develop-$PR~1 $feature_branch

	# Check if we're rebasing
	if ! git rev-parse --abbrev-ref HEAD | grep -q "$feature_branch"; then
		echo "It looks like we're rebasing"

		while ! git rebase --continue; do
			git accept-theirs
		done
	fi

	# Delete the develop PR branch
	git branch -D develop-$PR

	# Merge the newly rebased feature branch into the user feature branch
	if ! git co $destination_branch; then
		echo "Create the roll up feature branch and merge $feature_branch into it"
		exit 1
	:
	else
		if git merge $feature_branch; then
			git branch -D $feature_branch
		:
		else
			git accept-theirs
			git commit --file .git/MERGE_MSG
			git branch -D $feature_branch
		fi

		printf "\n========================\n"
		git status
	fi
done < "$1"
