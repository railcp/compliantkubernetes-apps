#!/usr/bin/env bats

# Generated from tests/unit/templates/bin-init.bats.gotmpl

# bats file_tags=static,bin:init,azure

setup_file() {
  load "../../bats.lib.bash"
  load_common "env.bash"
  load_common "gpg.bash"
  load_common "yq.bash"

  gpg.setup
  env.setup

  env.init azure capi prod
}

setup() {
  load "../../bats.lib.bash"
  load_common "env.bash"
  load_assert
  load_file
  load "../templates/bin-init.bash"

  env.private
}

teardown() {
  env.teardown
}

teardown_file() {
  env.teardown
  gpg.teardown
}

@test "init is successful - azure:capi:prod" {
  test_init_successful
}

@test "init is idempotent - azure:capi:prod" {
  test_init_idempotent
}
