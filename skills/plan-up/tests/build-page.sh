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

t_build_run() {
  T="$(mktemp -d)"
  cp "$here/build-page/run.md" "$T/plan-acme-shop-71-run.md"
  build "$T/plan-acme-shop-71-run.md"
  eq exit 0 "$code"
  eq DATA "$(jq -S . "$here/build-page/run.json")" "$(page_data "$T/plan-acme-shop-71-run.html")"
}

t_build_run_one() {
  T="$(mktemp -d)"
  cp "$here/build-page/run-one.md" "$T/plan-acme-shop-75-run.md"
  build "$T/plan-acme-shop-75-run.md"
  eq exit 0 "$code"
  eq DATA "$(jq -S . "$here/build-page/run-one.json")" "$(page_data "$T/plan-acme-shop-75-run.html")"
}

t_build_none_map() {
  T="$(mktemp -d)"
  cp "$here/build-page/none-map.md" "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 0 "$code"
  eq DATA "$(jq -S . "$here/build-page/none-map.json")" "$(page_data "$T/plan-acme-shop-42.html")"
}

cases=(
  "build-page builds a ticket page from its .md|t_build_ticket"
  "build-page builds a run page from its .md|t_build_run"
  "build-page builds a one-layer run page from its .md|t_build_run_one"
  "build-page builds a None map page|t_build_none_map"
)
