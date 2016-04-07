#!/bin/bash

# This script takes a filename as a command line arg
#   and parses the input file, expecting a pull
#   request number on each line.  It applies them
#   in order on the destination branch (old -> new)

# It also expects you to have a remote 'upstream' that
#  points to the repo you want to use for PRs

# Get the prod branch
echo "Enter the branch that you want to be based on"
printf "(approved) "
read master_branch

if [[ -z $master_branch ]]; then
	master_branch="approved"
fi

# Get the base branch from the PR (where the PR was merged into)
echo "Enter the base branch of the PRs (where the PRs are merged into)"
printf "(develop) "
read base_branch

if [[ -z $base_branch ]]; then
	base_branch="develop"
fi

# Get the branch we'll put all of the rebased code onto
echo "Enter the destination branch (new branch for the results)"
read destination_branch

echo "\n==========================================\n"
echo "Would you like to automatically resolve rebases and merge conflicts with the code in the rebased commit?"
printf "(y/n)"
read auto_resolve_conflict_states

if [ $auto_resolve_conflict_states = "y" ]; then
	auto_resolve_conflict_states=true
:
else
	auto_resolve_conflict_states=false
fi

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

	# Get the hash of the merge commit in the base_branch
	merge_commit=$(git log $base_branch --pretty=oneline --all --grep="Merge pull request #$PR" | grep -o "^[[:alnum:]]\{40\}")

	# Make sure we found the merge commit
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

	# Rebase feature branch onto master_branch through pr branch
	git rebase --onto $master_branch develop-$PR~1 $feature_branch

	# Check if we're rebasing
	if ! git rev-parse --abbrev-ref HEAD | grep -q "$feature_branch"; then
		echo "It looks like we're rebasing"

		if auto_resolve_conflict_states; then
			while ! git rebase --continue; do
				git accept-theirs
			done
		:
		else
			exit 1
		fi

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
			echo "Merge conflict"
			if auto_resolve_conflict_states; then
				git accept-theirs
				git commit --file .git/MERGE_MSG
				git branch -D $feature_branch
			:
			else
				exit 1
			fi
		fi

		printf "\n========================\n"
		git status
	fi
done < "$1"
