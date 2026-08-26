#!/usr/bin/env bash
# Pre-flight for the integrator.
#
# The sandbox silently resets HEAD to the session's base commit while the
# working files stay on disk. It has happened five times. The failure mode is
# not losing work — everything pushed is safe — it is committing on top of the
# base and producing a commit whose diff deletes every other agent's work. A
# push of that commit is rejected only by luck, when the remote happens to be
# ahead.
#
# So: never commit without running this. It answers one question — is what I am
# about to commit on top of what is actually on the server.
set -uo pipefail

# Pass your own session branch. The default is the current integration branch;
# it has changed three times, because an Arena session is pinned to the branch
# Arena created for it and a session cannot outlive its own branch. Relying on
# the default from an agent that owns a different branch is how this script
# reports "ok" against somebody else's tip.
BRANCH="${1:-arena/01a03bca-arandommenu}"

remote_tip="$(git ls-remote origin "refs/heads/${BRANCH}" | cut -f1)"
if [ -z "${remote_tip}" ]; then
    echo "preflight: no remote branch ${BRANCH}" >&2
    exit 1
fi

local_head="$(git rev-parse HEAD)"

if [ "${local_head}" = "${remote_tip}" ]; then
    echo "preflight ok · HEAD is the remote tip ($(git log --oneline -1))"
    exit 0
fi

if git merge-base --is-ancestor "${remote_tip}" "${local_head}"; then
    ahead="$(git rev-list --count "${remote_tip}..${local_head}")"
    echo "preflight ok · ${ahead} local commit(s) ahead of the remote tip"
    exit 0
fi

cat >&2 <<MESSAGE
preflight FAILED · HEAD is not built on the remote tip.

  remote ${BRANCH}: ${remote_tip}
  local HEAD:       ${local_head}

Committing now would produce a diff that deletes work already pushed. This is
the sandbox resetting HEAD to the session base while your files stay on disk.

Recover without losing anything on disk:

  git stash -u                     # only if you have uncommitted work to keep
  git fetch origin ${BRANCH}
  git reset --hard FETCH_HEAD
  git stash pop                    # then re-run this script

If you already committed on the wrong base, do not force-push. Save the files
out of the bad commit first:

  git show <bad-sha>:path/to/file > /tmp/file
MESSAGE
exit 1
