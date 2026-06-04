#!/bin/sh
# Populate deps/{ctemplate,libetpan,tidy-html5} from upstream git repos
# at the revisions pinned by scripts/build-*-ios.sh. Idempotent: existing
# non-empty trees are left untouched.
set -e

pushd "`dirname "$0"`" > /dev/null
scriptpath="`pwd`"
popd > /dev/null

. "$scriptpath/include.sh/build-dep.sh"

DEPS_ROOT="$scriptpath/../deps"

fetch_dep()
{
  _name="$1"
  _url="$2"
  _rev="$3"
  _dest="$DEPS_ROOT/$_name"

  if test -d "$_dest/build-mac" ; then
    echo "==> $_name already populated at $_dest (skipping)"
    return 0
  fi

  if test -d "$_dest" ; then
    if test -z "`ls -A "$_dest" 2>/dev/null`" ; then
      rmdir "$_dest"
    else
      echo "ERROR: $_dest exists but has no build-mac/ directory."
      echo "       Remove it manually if you want to re-fetch."
      exit 1
    fi
  fi

  echo "==> Cloning $_name from $_url @ $_rev"
  git clone "$_url" "$_dest"
  git -C "$_dest" checkout -q "$_rev"

  if test ! -d "$_dest/build-mac" ; then
    echo "ERROR: $_name was cloned but build-mac/ is missing at this revision."
    exit 1
  fi
}

fetch_dep libetpan   https://github.com/dinhviethoa/libetpan.git 6dc099a813344ee9c48009d70a78016ae838afcc
fetch_dep ctemplate  https://github.com/dinhviethoa/ctemplate.git d004783679560176f501998fd620f50acfc233f0
fetch_dep tidy-html5 https://github.com/dinhviethoa/tidy-html5.git 71aaa8669c664447743bba73e07d70c291548dca

echo "==> All dependencies ready under $DEPS_ROOT"
