#!/usr/bin/env bash
# Run the existing CI regression suites on independent Haxe, Node and PHP
# runners. Do not skip target parity: a failed command fails its matrix job.
set -euo pipefail

target="${1:?expected a CI regression target}"

run_timed() {
  local label="$1"
  shift
  local begin=$SECONDS
  echo "::group::$label"
  if "$@"; then
    local elapsed=$((SECONDS - begin))
    echo "::endgroup::"
    echo "::notice title=CI timing::$label: ${elapsed}s"
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
      printf '| %s | %ss |\n' "$label" "$elapsed" >> "$GITHUB_STEP_SUMMARY"
    fi
  else
    local status=$?
    echo "::endgroup::"
    echo "::error title=Regression failed::$label failed with exit code $status"
    exit "$status"
  fi
}

run_haxe() {
  local suite="$1"
  run_timed "Haxe/$suite" haxe "$suite-test-interp.hxml"
}

run_node() {
  local suite="$1"
  run_timed "Node/$suite compile" haxe "$suite-test-js.hxml"
  run_timed "Node/$suite execute" node "build/tests/$suite.js"
}

run_php() {
  local suite="$1"
  run_timed "PHP/$suite compile" haxe "$suite-test-php.hxml"
  run_timed "PHP/$suite execute" env XDEBUG_MODE=off php "build/tests/php-$suite/index.php"
}

common_suites=(
  source-analysis
  host-functions
  host-source-imports
  context-block-probe
  nail-typechecker
  module-source-imports
  official-bootstrap
  modern-numbers
  arithmetic-relations
  relation-module-abi
  single-pass-macro
  runtime-core
  type-declaration-lowering
  nary-relations
  modern-module-abi
  host-text-writes
  trusted-module-images
  revocable-capabilities
  signed-manifests
  shared-result
  exact-rounding
  explicit-relations
  boot
)

case "$target" in
  haxe|haxe-typechecker|node|php-macro|php-runtime-0|php-runtime-1|php-modern-numbers|php-type-lowering|php-exact-rounding|php-rest) ;;
  *) echo "Unknown CI target: $target" >&2; exit 2 ;;
esac

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  printf '### Regression timings: %s\n\n| Stage | Duration |\n|---|---:|\n' "$target" >> "$GITHUB_STEP_SUMMARY"
fi

# Each runner needs its own compiled source-free standard-library image.
run_timed "Bootstrap image/$target" haxe seed-image.hxml

# BootTestMain embeds build/bootstrap/self-image.json, not the stage-zero
# stdlib image. The former serial workflow created it via the Node fixed-point
# check before running boot tests. Each independent runner must do the same.
# Keep it just-in-time so PHP macro/runtime jobs do not pay this cost.
prepare_self_image() {
  run_timed "Self-image/fixed point compile" haxe rebootstrap-node.hxml
  run_timed "Self-image/fixed point verify" node build/tests/rebootstrap-node.js
  test -s build/bootstrap/self-image.json
}

case "$target" in
  haxe)
    for suite in "${common_suites[@]}"; do
      # Run the expensive checker as a separate, equally required matrix job.
      if [[ "$suite" == nail-typechecker ]]; then continue; fi
      if [[ "$suite" == boot ]]; then prepare_self_image; fi
      run_haxe "$suite"
    done
    # These checks exist only for the Haxe interpreter.
    run_haxe host-capabilities
    run_haxe module-host-grants
    ;;
  haxe-typechecker)
    run_haxe nail-typechecker
    ;;
  node)
    for suite in "${common_suites[@]}"; do
      if [[ "$suite" == boot ]]; then prepare_self_image; fi
      run_node "$suite"
    done
    # Node-only checks from the original CI; retain every one.
    run_node modern-bootstrap
    run_timed "Node/sign-modules" node --test tools/sign-modules.test.mjs
    ;;
  php-macro)
    run_php single-pass-macro
    ;;
  php-runtime-0|php-runtime-1)
    # Preserve independent Vm/BootRuntime construction per source form.
    # Two shards cover all four runtime parity cases without repetition.
    NAIL_CI_RUNTIME_CORE_SHARD="${target##*-}" run_php runtime-core
    ;;
  php-modern-numbers)
    run_php modern-numbers
    ;;
  php-type-lowering)
    run_php type-declaration-lowering
    ;;
  php-exact-rounding)
    run_php exact-rounding
    ;;
  php-rest)
    for suite in "${common_suites[@]}"; do
      case "$suite" in
        single-pass-macro|runtime-core|modern-numbers|type-declaration-lowering|exact-rounding)
          continue ;;
      esac
      if [[ "$suite" == boot ]]; then prepare_self_image; fi
      run_php "$suite"
    done
    ;;
esac
