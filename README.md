# Puppet module for removing Ubuntu advertising

[![CI](https://github.com/bwitt/puppet-unspamify/actions/workflows/ci.yml/badge.svg)](https://github.com/bwitt/puppet-unspamify/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/bwitt/puppet-unspamify.svg)](https://github.com/bwitt/puppet-unspamify/blob/main/LICENSE)

## Table of Contents

* [Description](#description)
* [Usage](#usage)
* [Reference](#reference)
* [Limitations](#limitations)
* [Development](#development)
* [Credits](#credits)

## Description

Applies the recommendations from
[UnspamifyUbuntu](https://github.com/Skyedra/UnspamifyUbuntu)
to remove Ubuntu Pro, ESM and MOTD advertising from APT,
login messages and Software Updater.
See [REFERENCE.md](REFERENCE.md) for what each parameter does.

## Usage

```puppet
include unspamify
```

Opt-in extras, here via Hiera:

```yaml
unspamify::keep_distro_info: true
unspamify::patch_apt_check: true
unspamify::patch_livepatch_tip: true
```

The defaults remove the Ubuntu Pro client,
so on hosts that need Pro (ESM, Livepatch, etc.)
keep it and just hide APT news:

```puppet
class { 'unspamify':
  replace_ua_tools => false,
  disable_apt_news => true,
}
```

## Reference

See [REFERENCE.md](REFERENCE.md).

## Limitations

* Ubuntu only.
* `patch_apt_check` and `patch_livepatch_tip` edit packaged files; upgrades
  revert them until the next Puppet run.

## Development

Unit tests and static checks:

```sh
bundle install
bundle exec rake test
```

Acceptance tests run in Docker with Beaker:

```sh
BEAKER_PUPPET_COLLECTION=openvox8 \
BEAKER_SETFILE=ubuntu2404-64 \
bundle exec rake beaker
```

Regenerate `REFERENCE.md` after changing parameters:

```sh
bundle exec rake strings:generate:reference
```

## Credits

Based on [UnspamifyUbuntu](https://github.com/Skyedra/UnspamifyUbuntu) by
Skye. `files/fake-ubuntu-advantage-tools.deb` is redistributed unmodified
from that project under the MIT license; see
[files/fake-ubuntu-advantage-tools.LICENSE](files/fake-ubuntu-advantage-tools.LICENSE).
