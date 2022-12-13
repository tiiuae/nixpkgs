#!/usr/bin/env bash
set -euo pipefail
shopt -s inherit_errexit

if test -z "${TEST_LIB:-}"; then
  TEST_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
fi

tmp="$(mktemp -d)"
clean_up() {
  rm -rf "$tmp"
}
trap clean_up EXIT
mkdir -p "$tmp/work"
cd "$tmp/work"

# Deterministic seed for random generator
seed=${1:-$RANDOM}
echo >&2 "Using seed $seed, use \`lib/tests/path.sh $seed\` to reproduce this result"

# The number of random paths to generate
count=500

# Set this to 1 or 2 to enable debug output
debug=0

# Fine tuning of the path generator in ./pathgen.awk
# These values were chosen to balance the number of generated invalid paths
# to the variance in generated paths. Enable debug output to see the paths
extradotweight=64   # The larger this value, the more dots are generated
extraslashweight=64 # The larger this value, the more slashes are generated
extranullweight=16  # The larger this value, the shorter the generated strings

# Use
#     || die
die() {
  echo >&2 "test case failed: " "$@"
  exit 1
}

if [[ "$debug" -ge 1 ]]; then
    echo >&2 "Generating $count random path-like strings"
fi

mkdir -p "$tmp/strings"
index=0
while [[ "$index" -lt "$count" ]] && IFS= read -r -d $'\0' str; do
    echo -n "$str" > "$tmp/strings/$index"
    ((index++)) || true
done < <(awk \
    -v seed="$seed" \
    -v extradotweight="$extradotweight" \
    -v extraslashweight="$extraslashweight" \
    -v extranullweight="$extranullweight" \
    -f "$TEST_LIB"/tests/pathgen.awk)

if [[ "$debug" -ge 1 ]]; then
    echo >&2 "Trying to normalise the generated path-like strings with Nix"
fi

nix-instantiate --eval --strict --json --read-write-mode \
    --arg libpath "$TEST_LIB" \
    --arg dir "$tmp/strings" \
    "$TEST_LIB"/tests/pathNormalise.nix \
    >"$tmp/result.json"

# Turns the results into an associative bash array
declare -A results="($(jq '
    to_entries
    | map("[\(.key | @sh)]=\(.value | @sh)")
    | join(" \n")' -r < "$tmp/result.json"))"

# Looks up the normalisation result while, while checking that it only failed for invalid paths
# Returns 0 for valid paths, 1 for invalid paths
# Prints a valid path on stdout
normalise() {
    local str=$1
    # Uses the same check for validity as in ../path.nix
    if [[ "$str" == "" || "$str" == /* || "$str" =~ ^(.*/)?\.\.(/.*)?$ ]]; then
        valid=
    else
        valid=1
    fi

    normalised=${results[$str]}
    # An empty string indicates failure
    if [[ -n "$normalised" ]]; then
        if [[ -n "$valid" ]]; then
            echo "$normalised"
        else
            die "For invalid subpath \"$str\", lib.path.subpath.normalise returned this result: \"$normalised\""
        fi
    else
        if [[ -n "$valid" ]]; then
            die "For valid subpath \"$str\", lib.path.subpath.normalise failed"
        else
            if [[ "$debug" -ge 2 ]]; then
                echo >&2 "String $str is not a valid substring"
            fi
            # Invalid and it correctly failed, we let the caller continue if they catch the exit code
            return 1
        fi
    fi
}

if [[ "$debug" -ge 1 ]]; then
    echo >&2 "Checking idempotency of each result and making sure the realpath result isn't changed"
fi

declare -A norm_to_real
invalid=0

for str in "${!results[@]}"; do
    if ! result=$(normalise "$str"); then
        ((invalid++)) || true
        continue
    fi

    if ! doubleResult=$(normalise "$result"); then
        die "For valid subpath \"$str\", the normalisation \"$result\" was not a valid subpath"
    fi

    # Checking idempotency law
    if [[ "$doubleResult" != "$result" ]]; then
        die "For valid subpath \"$str\", normalising it once gives \"$result\" but normalising it twice gives a different result: \"$doubleResult\""
    fi

    # Check the law that it doesn't change the result of a realpath
    mkdir -p -- "$str" "$result"
    real_orig=$(realpath -- "$str")
    real_norm=$(realpath -- "$result")

    if [[ "$real_orig" != "$real_norm" ]]; then
        die "realpath of the original string \"$str\" (\"$real_orig\") is not the same as realpath of the normalisation \"$result\" (\"$real_norm\")"
    fi

    if [[ "$debug" -ge 2 ]]; then
        echo >&2 "String $str gets normalised to $result and file path $real_orig"
    fi
    norm_to_real["$result"]="$real_orig"
done

if [[ "$debug" -ge 1 ]]; then
    echo >&2 "$(bc <<< "scale=1; 100 / $count * $invalid")% of the total $count generated strings were invalid subpath strings"
    echo >&2 "Checking for the uniqueness law"
fi

for norm_p in "${!norm_to_real[@]}"; do
    real_p=${norm_to_real["$norm_p"]}
    for norm_q in "${!norm_to_real[@]}"; do
        real_q=${norm_to_real["$norm_q"]}
        # Checks normalisation uniqueness law
        if [[ "$norm_p" != "$norm_q" && "$real_p" == "$real_q" ]]; then
            die "Normalisations \"$norm_p\" and \"$norm_q\" are different, but the realpath of them is the same: \"$real_p\""
        fi
    done
done

echo >&2 tests ok
