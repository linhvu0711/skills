# build-page.sh: Markdown in, the built page's DATA out.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

build() { run python3 "$here/../scripts/build-page.py" "$@"; }
page_data() { sed -n 's/^const DATA = \(.*\);$/\1/p' "$1" | jq -S .; }

t_build_ticket() {
  T="$(mktemp -d)"
  cp "$here/build-page/ticket.md" "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 0 "$code"
  eq stdout "page: $T/plan-acme-shop-42.html" "$out"
  eq DATA "$(jq -S . "$here/build-page/ticket.json")" "$(page_data "$T/plan-acme-shop-42.html")"
}

cases=(
  "build-page builds a ticket page from its .md|t_build_ticket"
)
