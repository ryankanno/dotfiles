#!/usr/bin/env bash
set -uo pipefail
die() { echo "git-crypt merge driver: $*" >&2; exit 1; }
# Plaintext stays out of the worktree, where `git add -A` can commit it.
git_dir="$(git rev-parse --git-dir)" || die "not in a git repository"
tmp_dir="$(mktemp -d "${git_dir}/git-crypt-merge.XXXXXXXX")" || die "mktemp failed in ${git_dir}"
trap 'rm -rf "${tmp_dir}"' EXIT
# Ending by the signal itself gives git the same status as an untrapped kill.
on_signal() { rm -rf "${tmp_dir}"; trap - "$1"; kill -"$1" $$; }
trap 'on_signal INT' INT
trap 'on_signal TERM' TERM
trap 'on_signal HUP' HUP
ancestor_decrypted="${tmp_dir}/ancestor"
current_decrypted="${tmp_dir}/current"
other_decrypted="${tmp_dir}/other"
echo ""
echo "###########################"
echo "# Git crypt driver called #"
echo "###########################"
echo ""

echo "Decrypting ancestor file..."
cat "$1" | git-crypt smudge > "${ancestor_decrypted}" || die "git-crypt smudge failed on the ancestor file"
echo "Decrypting current file..."
cat "$2" | git-crypt smudge > "${current_decrypted}" || die "git-crypt smudge failed on the current file"
echo "Decrypting other file..."
cat "$3" | git-crypt smudge > "${other_decrypted}" || die "git-crypt smudge failed on the other file"
echo ""

echo "Merging ..."
exit_code=0
git merge-file -L "current branch" -L "ancestor branch" -L "other branch" "${current_decrypted}" "${ancestor_decrypted}" "${other_decrypted}" || exit_code=$?
# A failed clean must not truncate git's result temp.
cat "${current_decrypted}" | git-crypt clean > "${tmp_dir}/result" || die "git-crypt clean failed on the merge result"
mv "${tmp_dir}/result" "$2" || die "moving the merge result over $2 failed"

if [ "$exit_code" -eq "0" ]
then
    echo "@@@ No conflict!"
else
    echo "@@@ You need to solve some conflicts..."
fi

exit $exit_code
