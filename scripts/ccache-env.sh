#!/usr/bin/env bash
# Shared ccache settings for all WebKitGTK CI builds.
# Inspired by WebKit Source/cmake/WebKitCCache.cmake (macOS launcher path) and
# applied on Linux where upstream only sets a weak default.
#
# Critical for GHA: CCACHE_BASEDIR + CCACHE_NOHASHDIR so object hashes stay
# stable across runners/containers even when absolute checkout paths differ.
#
# shellcheck disable=SC2034
: "${CCACHE_DIR:=/ccache}"
: "${CCACHE_MAXSIZE:=40G}"
export CCACHE_DIR
export CCACHE_MAXSIZE
export CCACHE_COMPRESS="${CCACHE_COMPRESS:-1}"
export CCACHE_COMPRESSLEVEL="${CCACHE_COMPRESSLEVEL:-5}"
# Hash portable relative to source tree (set CCACHE_BASEDIR to WEBKIT_DIR in callers).
export CCACHE_NOHASHDIR="${CCACHE_NOHASHDIR:-true}"
export CCACHE_PCH_EXTSUM="${CCACHE_PCH_EXTSUM:-true}"
# Prefer depfile hashing (cheap miss path) when ccache supports it.
export CCACHE_DEPEND="${CCACHE_DEPEND:-true}"
export CCACHE_COMPILERCHECK="${CCACHE_COMPILERCHECK:-content}"
export CCACHE_SLOPPINESS="${CCACHE_SLOPPINESS:-pch_defines,time_macros,include_file_mtime,include_file_ctime,file_macro}"
# Do not cache assembler-only noise if present
export CCACHE_IGNOREOPTIONS="${CCACHE_IGNOREOPTIONS:--fdebug-prefix-map=* -fmacro-prefix-map=*}"

# Put real ccache first if PATH has /usr/lib64/ccache wrappers.
if command -v ccache >/dev/null 2>&1; then
  :
fi

ccache_print_config() {
  echo "CCACHE_DIR=${CCACHE_DIR}"
  echo "CCACHE_MAXSIZE=${CCACHE_MAXSIZE}"
  echo "CCACHE_BASEDIR=${CCACHE_BASEDIR:-"(unset)"}"
  echo "CCACHE_NOHASHDIR=${CCACHE_NOHASHDIR}"
  echo "CCACHE_DEPEND=${CCACHE_DEPEND}"
  echo "CCACHE_SLOPPINESS=${CCACHE_SLOPPINESS}"
  ccache -p 2>/dev/null | head -n 40 || true
  ccache -s 2>/dev/null || true
}
