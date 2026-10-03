#!/bin/bash
# Signs the release zip built by build-release.sh and writes dist/appcast.xml,
# the Sparkle feed that installed copies read (SUFeedURL points at the
# appcast.xml attached to the latest GitHub release).
#
# The private EdDSA key comes from $SPARKLE_PRIVATE_KEY (CI secret) or, when
# that's unset, from the login Keychain (where generate_keys stores it).
#
# Usage: scripts/make-appcast.sh <version>   (after build-release.sh <version>)
set -euo pipefail

cd "$(dirname "$0")/.."
version="${1:?usage: scripts/make-appcast.sh <version>}"
repo="${GITHUB_REPOSITORY:-kitkas1412/thenotch}"
app="build/DerivedData/Build/Products/Release/thenotch.app"
zip="dist/thenotch-$version.zip"
sign_update="build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"

[ -f "$zip" ] || { echo "error: $zip not found; run scripts/build-release.sh $version first" >&2; exit 1; }
[ -x "$sign_update" ] || { echo "error: Sparkle's sign_update not found at $sign_update" >&2; exit 1; }

plist="$app/Contents/Info.plist"
build=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$plist")
minimum=$(/usr/libexec/PlistBuddy -c "Print LSMinimumSystemVersion" "$plist")

# sparkle:edSignature="…" length="…"
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
  signature=$(echo "$SPARKLE_PRIVATE_KEY" | "$sign_update" --ed-key-file - "$zip")
else
  signature=$("$sign_update" "$zip")
fi
grep -q 'sparkle:edSignature=' <<<"$signature" || { echo "error: signing failed" >&2; exit 1; }

# Release notes: this version's CHANGELOG section as simple HTML.
notes=$(awk -v v="$version" '
  $0 ~ "^## \\[" v "\\]" { found = 1; next }
  found && /^(## )?\[/ { exit }
  found { print }
' CHANGELOG.md | python3 -c '
import html, re, sys
out, in_list = [], False
for line in sys.stdin.read().strip().splitlines():
    text = html.escape(line.strip(), quote=False)
    text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text)
    text = re.sub(r"`(.+?)`", r"<code>\1</code>", text)
    text = re.sub(r"\[(.+?)\]\((.+?)\)", r"<a href=\"\2\">\1</a>", text)
    is_item = text.startswith("- ")
    if in_list and not is_item:
        out.append("</ul>"); in_list = False
    if text.startswith("### "):
        out.append(f"<h3>{text[4:]}</h3>")
    elif is_item:
        if not in_list:
            out.append("<ul>"); in_list = True
        out.append(f"<li>{text[2:]}</li>")
    elif text:
        out.append(f"<p>{text}</p>")
if in_list:
    out.append("</ul>")
print("\n".join(out))
')
[ -n "$notes" ] || { echo "error: no CHANGELOG section for $version" >&2; exit 1; }

cat > dist/appcast.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>thenotch</title>
    <item>
      <title>thenotch $version</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minimum</sparkle:minimumSystemVersion>
      <description><![CDATA[
$notes
      ]]></description>
      <enclosure url="https://github.com/$repo/releases/download/v$version/thenotch-$version.zip" type="application/octet-stream" $signature/>
    </item>
  </channel>
</rss>
EOF
echo "Wrote dist/appcast.xml for $version ($build)"
