#!/bin/bash
# Fill the newest <release> stub from the Debian changelog inside the .deb.
# Usage: .github/fill-release-notes.sh [changelog]
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if [[ ${1-} ]]; then
    changelog=$1
else
    changelog=$tmp/changelog
    url=$(grep -oE 'https://[^ ]*/surfshark_[0-9][^ ]*_amd64\.deb' com.surfshark.Surfshark.yaml | head -1)
    echo "Fetching changelog from $url" >&2
    curl -fsSL "$url" -o "$tmp/surfshark.deb"
    bsdtar -Oxf "$tmp/surfshark.deb" data.tar.xz |
        bsdtar -xOf - '*/doc/surfshark/changelog.gz' | gzip -dc >"$changelog"
fi

ver=$(sed -n '1s/^surfshark (\(.*\)).*/\1/p' "$changelog")
meta_ver=$(grep -oE '<release version="[^"]+"' com.surfshark.Surfshark.metainfo.xml | head -1)
meta_ver=${meta_ver#*version=\"}
meta_ver=${meta_ver%\"}
[[ $meta_ver == "$ver" ]] || {
    echo "Newest metainfo is $meta_ver, changelog is $ver" >&2
    exit 1
}

{
    echo '            <description>'
    echo '                <ul>'
    while IFS= read -r line; do
        [[ $line == ' -- '* ]] && break
        [[ $line =~ ^[[:space:]]+\*[[:space:]]+(.*)$ ]] || continue
        text=${BASH_REMATCH[1]}
        text=${text//'&'/'&amp;'}
        text=${text//'<'/'&lt;'}
        text=${text//'>'/'&gt;'}
        echo "                    <li>$text</li>"
    done <"$changelog"
    echo '                </ul>'
    echo '            </description>'
} >"$tmp/desc"
grep -q '<li>' "$tmp/desc" || { echo "No changelog bullets for $ver" >&2; exit 1; }

want=0
filled=0
while IFS= read -r line; do
    if (( want )); then
        want=0
        if [[ $line == *'<description></description>'* || $line == *'<description/>'* ]]; then
            cat "$tmp/desc"
            filled=1
            continue
        fi
    fi
    [[ $line == *"<release version=\"$ver\""* ]] && want=1
    printf '%s\n' "$line"
done <com.surfshark.Surfshark.metainfo.xml >"$tmp/out"

if (( filled )); then
    mv "$tmp/out" com.surfshark.Surfshark.metainfo.xml
    echo "Filled release $ver" >&2
else
    echo "Release $ver already has notes" >&2
fi
